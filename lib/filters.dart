import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models.dart';

class PageJob {
  const PageJob(
    this.file,
    this.turns,
    this.filter, {
    this.maxSide = 0,
    this.quality = 85,
    this.brightness = 0,
    this.contrast = 1,
    this.signature,
  });

  /// The page as the user sees it: rotation, filter, adjustments and signature.
  factory PageJob.of(PageItem p, {int maxSide = 0, int quality = 85}) => PageJob(
        p.file,
        p.turns,
        p.filter,
        maxSide: maxSide,
        quality: quality,
        brightness: p.brightness,
        contrast: p.contrast,
        signature: p.signature,
      );

  final String file;
  final int turns;
  final ScanFilter filter;

  /// Longest side in pixels; 0 keeps the original size.
  final int maxSide;

  /// JPEG quality, 1..100.
  final int quality;
  final double brightness;
  final double contrast;

  /// Signature to stamp on the page, if any.
  final SignaturePlacement? signature;
}

class PageResult {
  const PageResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Runs in an isolate via `compute`: decode, rotate, resize, filter, adjust,
/// stamp signature, re-encode.
Future<PageResult> processPage(PageJob job) async {
  final decoded = await img.decodeImageFile(job.file);
  if (decoded == null) throw StateError('Gagal membaca gambar: ${job.file}');
  var image = img.bakeOrientation(decoded);

  final turns = job.turns % 4;
  if (turns != 0) image = img.copyRotate(image, angle: turns * 90);

  if (job.maxSide > 0 && math.max(image.width, image.height) > job.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: job.maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: job.maxSide, interpolation: img.Interpolation.average);
  }

  switch (job.filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.grayscale:
      image = img.grayscale(image);
    case ScanFilter.color:
      image = flattenIllumination(image, gray: false);
    case ScanFilter.document:
      image = flattenIllumination(image, gray: true);
    case ScanFilter.magic:
      image = boostColor(flattenIllumination(image, gray: false));
  }

  if (job.brightness != 0 || job.contrast != 1) {
    image = adjustBrightnessContrast(image, job.brightness, job.contrast);
  }

  final sig = job.signature;
  if (sig != null) {
    final stamp = await img.decodePngFile(sig.file);
    if (stamp != null) {
      image = stampSignature(image, stamp, sig);
    }
  }

  return PageResult(
    Uint8List.fromList(img.encodeJpg(image, quality: job.quality)),
    image.width,
    image.height,
  );
}

/// Pushes colours away from their gray value (saturation x1.45) and adds a
/// little contrast, so ink and highlights look vivid on a white page.
img.Image boostColor(img.Image src) {
  final rgb = src.convert(format: img.Format.uint8, numChannels: 3);
  final px = rgb.getBytes(order: img.ChannelOrder.rgb);
  const sat = 1.45;
  for (var i = 0; i < px.length; i += 3) {
    final g = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
    for (var c = 0; c < 3; c++) {
      final v = g + (px[i + c] - g) * sat;
      px[i + c] = (((v - 128) * 1.08) + 128).round().clamp(0, 255);
    }
  }
  return img.Image.fromBytes(
    width: rgb.width,
    height: rgb.height,
    bytes: px.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

/// Linear levels: out = (v - 128) * contrast + 128 + brightness * 255.
img.Image adjustBrightnessContrast(img.Image src, double brightness, double contrast) {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = ((v - 128) * contrast + 128 + brightness * 255).round().clamp(0, 255);
  }
  final out = src.convert(format: img.Format.uint8, numChannels: 3);
  final bytes = out.getBytes(order: img.ChannelOrder.rgb);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = lut[bytes[i]];
  }
  return img.Image.fromBytes(
    width: out.width,
    height: out.height,
    bytes: bytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

/// Alpha-blends [stamp] onto [page] at [at] (centre and width as page fractions).
img.Image stampSignature(img.Image page, img.Image stamp, SignaturePlacement at) {
  final w = math.max(8, (at.width * page.width).round());
  final h = math.max(4, (w * stamp.height / stamp.width).round());
  final scaled = img.copyResize(stamp, width: w, height: h, interpolation: img.Interpolation.average);
  final rgb = page.convert(format: img.Format.uint8, numChannels: 3);
  return img.compositeImage(
    rgb,
    scaled,
    dstX: (at.x * page.width - w / 2).round(),
    dstY: (at.y * page.height - h / 2).round(),
  );
}

/// Shadow removal: estimate the paper's background brightness with a large
/// local-maximum filter (text strokes are thin, so they vanish from the
/// estimate), then divide the image by it. Uneven light and shadows flatten out
/// and the paper becomes white. A levels curve then darkens the ink.
img.Image flattenIllumination(img.Image src, {required bool gray}) {
  final rgb = src.convert(format: img.Format.uint8, numChannels: 3);
  final w = rgb.width;
  final h = rgb.height;
  final px = rgb.getBytes(order: img.ChannelOrder.rgb);
  final ch = gray ? 1 : 3;

  final Uint8List base;
  if (gray) {
    base = Uint8List(w * h);
    for (var i = 0, p = 0; i < base.length; i++, p += 3) {
      base[i] = (0.299 * px[p] + 0.587 * px[p + 1] + 0.114 * px[p + 2]).round();
    }
  } else {
    base = px;
  }

  // 1. Block-average down to a small map (~160 px on the long side).
  final scale = math.max(1, math.max(w, h) ~/ 160);
  final sw = (w / scale).ceil();
  final sh = (h / scale).ceil();
  var small = Uint8List(sw * sh * ch);
  for (var by = 0; by < sh; by++) {
    final y0 = by * scale;
    final y1 = math.min(h, y0 + scale);
    for (var bx = 0; bx < sw; bx++) {
      final x0 = bx * scale;
      final x1 = math.min(w, x0 + scale);
      final count = (y1 - y0) * (x1 - x0);
      for (var c = 0; c < ch; c++) {
        var sum = 0;
        for (var y = y0; y < y1; y++) {
          var i = (y * w + x0) * ch + c;
          for (var x = x0; x < x1; x++, i += ch) {
            sum += base[i];
          }
        }
        small[(by * sw + bx) * ch + c] = sum ~/ count;
      }
    }
  }

  // 2. Local maximum (drops ink) then blur (smooths the estimate).
  small = _maxFilter(small, sw, sh, ch, 4);
  small = _boxBlur(small, sw, sh, ch, 3);
  small = _boxBlur(small, sw, sh, ch, 3);

  // 3. Divide by the background, apply levels.
  final lowPoint = gray ? 70 : 20;
  final highPoint = gray ? 225 : 232;
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = ((v - lowPoint) * 255 / (highPoint - lowPoint)).round().clamp(0, 255);
  }

  final x0s = Int32List(w);
  final x1s = Int32List(w);
  final txs = Float32List(w);
  for (var x = 0; x < w; x++) {
    final fx = ((x + 0.5) / scale - 0.5).clamp(0.0, sw - 1.0);
    final i0 = fx.floor();
    x0s[x] = i0;
    x1s[x] = math.min(sw - 1, i0 + 1);
    txs[x] = fx - i0;
  }

  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final fy = ((y + 0.5) / scale - 0.5).clamp(0.0, sh - 1.0);
    final y0 = fy.floor();
    final y1 = math.min(sh - 1, y0 + 1);
    final ty = fy - y0;
    for (var x = 0; x < w; x++) {
      final xa = x0s[x];
      final xb = x1s[x];
      final tx = txs[x];
      final o = (y * w + x) * 3;
      for (var c = 0; c < ch; c++) {
        final a = small[(y0 * sw + xa) * ch + c];
        final b = small[(y0 * sw + xb) * ch + c];
        final d = small[(y1 * sw + xa) * ch + c];
        final e = small[(y1 * sw + xb) * ch + c];
        final top = a + (b - a) * tx;
        final bottom = d + (e - d) * tx;
        final bg = math.max(1.0, top + (bottom - top) * ty);
        final v = base[(y * w + x) * ch + c] * 255 / bg;
        final mapped = lut[v > 255 ? 255 : v.toInt()];
        if (gray) {
          out[o] = out[o + 1] = out[o + 2] = mapped;
          break;
        }
        out[o + c] = mapped;
      }
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
}

Uint8List _maxFilter(Uint8List src, int w, int h, int ch, int r) {
  final tmp = Uint8List(src.length);
  final dst = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < ch; c++) {
        var m = 0;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          final v = src[(y * w + k) * ch + c];
          if (v > m) m = v;
        }
        tmp[(y * w + x) * ch + c] = m;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < ch; c++) {
        var m = 0;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          final v = tmp[(k * w + x) * ch + c];
          if (v > m) m = v;
        }
        dst[(y * w + x) * ch + c] = m;
      }
    }
  }
  return dst;
}

Uint8List _boxBlur(Uint8List src, int w, int h, int ch, int r) {
  final tmp = Uint8List(src.length);
  final dst = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < ch; c++) {
        var sum = 0;
        var n = 0;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          sum += src[(y * w + k) * ch + c];
          n++;
        }
        tmp[(y * w + x) * ch + c] = sum ~/ n;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < ch; c++) {
        var sum = 0;
        var n = 0;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          sum += tmp[(k * w + x) * ch + c];
          n++;
        }
        dst[(y * w + x) * ch + c] = sum ~/ n;
      }
    }
  }
  return dst;
}

/// Flattens an image with transparency onto white and returns JPEG bytes.
/// PDF renderers hand back transparent pages; without this they decode as black.
/// Runs in an isolate via `compute`.
Future<Uint8List> flattenOnWhite(String file) async {
  final src = await img.decodeImageFile(file);
  if (src == null) throw StateError('Gagal membaca gambar: $file');
  final canvas = img.Image(width: src.width, height: src.height, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, src);
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
}
