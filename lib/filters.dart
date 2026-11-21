import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models.dart';

class PageJob {
  const PageJob(this.file, this.turns, this.filter, {this.maxSide = 0});
  final String file;
  final int turns;
  final ScanFilter filter;

  /// Longest side in pixels; 0 keeps the original size.
  final int maxSide;
}

class PageResult {
  const PageResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Runs in an isolate via `compute`: decode, rotate, resize, filter, re-encode.
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
  }
  return PageResult(
    Uint8List.fromList(img.encodeJpg(image, quality: 85)),
    image.width,
    image.height,
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
