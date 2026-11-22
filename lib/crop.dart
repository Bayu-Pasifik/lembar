import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Normalized (0..1) corner positions of a quadrilateral, in the order
/// top-left, top-right, bottom-right, bottom-left.
class Quad {
  const Quad(this.tl, this.tr, this.br, this.bl);
  final (double, double) tl, tr, br, bl;

  List<(double, double)> get points => [tl, tr, br, bl];

  /// x,y pairs in tl, tr, br, bl order, for JSON.
  List<double> toList() => [for (final p in points) ...[p.$1, p.$2]];

  factory Quad.fromList(List<double> v) => Quad((v[0], v[1]), (v[2], v[3]), (v[4], v[5]), (v[6], v[7]));

  static const inset = Quad((0.08, 0.08), (0.92, 0.08), (0.92, 0.92), (0.08, 0.92));
  static const full = Quad((0, 0), (1, 0), (1, 1), (0, 1));
}

class CropJob {
  const CropJob(this.file, this.quad, {this.maxSide = 3000});
  final String file;
  final Quad quad;
  final int maxSide;
}

class CropInput {
  const CropInput(this.bytes, this.width, this.height, this.guess);
  final Uint8List bytes;
  final int width;
  final int height;
  final Quad guess;
}

/// Decodes [file] upright, caps its size, and guesses where the paper is.
/// Runs in an isolate via `compute`.
Future<CropInput> prepareForCrop(String file) async {
  final decoded = await img.decodeImageFile(file);
  if (decoded == null) throw StateError('Gagal membaca gambar: $file');
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > 3000) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 3000)
        : img.copyResize(image, height: 3000);
  }
  return CropInput(
    Uint8List.fromList(img.encodeJpg(image, quality: 92)),
    image.width,
    image.height,
    guessPaper(image),
  );
}

/// Cheap paper finder: on a small grayscale copy, take the bounding box of the
/// bright pixels (Otsu threshold). Falls back to an inset rectangle when the
/// result looks implausible. The user can always drag the corners.
Quad guessPaper(img.Image source) {
  const side = 160;
  final small = source.width >= source.height
      ? img.copyResize(source, width: side)
      : img.copyResize(source, height: side);
  final g = img.grayscale(small);
  final w = g.width, h = g.height;

  final hist = List<int>.filled(256, 0);
  for (final p in g) {
    hist[p.r.toInt()]++;
  }
  final total = w * h;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, thr = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t;
    }
  }

  // Ignore stray bright pixels: a row/column counts only if enough of it is bright.
  final rowBright = List<int>.filled(h, 0);
  final colBright = List<int>.filled(w, 0);
  var bright = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (g.getPixel(x, y).r > thr) {
        rowBright[y]++;
        colBright[x]++;
        bright++;
      }
    }
  }
  final area = bright / total;
  if (area < 0.2 || area > 0.95) return Quad.inset;

  int first(List<int> a, int min) => a.indexWhere((v) => v >= min);
  int last(List<int> a, int min) => a.lastIndexWhere((v) => v >= min);
  final top = first(rowBright, (w * 0.15).round());
  final bottom = last(rowBright, (w * 0.15).round());
  final left = first(colBright, (h * 0.15).round());
  final right = last(colBright, (h * 0.15).round());
  if (top < 0 || left < 0 || bottom - top < h * 0.3 || right - left < w * 0.3) {
    return Quad.inset;
  }
  final x0 = left / w, x1 = (right + 1) / w, y0 = top / h, y1 = (bottom + 1) / h;
  return Quad((x0, y0), (x1, y0), (x1, y1), (x0, y1));
}

/// Perspective-corrects the quad out of the image and returns JPEG bytes.
/// Runs in an isolate via `compute`.
Future<Uint8List> cropQuad(CropJob job) async {
  final decoded = await img.decodeImageFile(job.file);
  if (decoded == null) throw StateError('Gagal membaca gambar: ${job.file}');
  final src = img.bakeOrientation(decoded);
  final w = src.width.toDouble(), h = src.height.toDouble();

  img.Point pt((double, double) p) => img.Point(p.$1 * (w - 1), p.$2 * (h - 1));
  final tl = pt(job.quad.tl), tr = pt(job.quad.tr);
  final br = pt(job.quad.br), bl = pt(job.quad.bl);

  double dist(img.Point a, img.Point b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  var outW = math.max(dist(tl, tr), dist(bl, br));
  var outH = math.max(dist(tl, bl), dist(tr, br));
  final longest = math.max(outW, outH);
  if (longest > job.maxSide) {
    final k = job.maxSide / longest;
    outW *= k;
    outH *= k;
  }
  final dst = img.Image(
    width: math.max(outW.round(), 16),
    height: math.max(outH.round(), 16),
    numChannels: 3,
  );
  final out = img.copyRectify(
    src,
    topLeft: tl,
    topRight: tr,
    bottomLeft: bl,
    bottomRight: br,
    interpolation: img.Interpolation.linear,
    toImage: dst,
  );
  return Uint8List.fromList(img.encodeJpg(out, quality: 92));
}

/// A captured page waiting to be stored: the corrected image, plus the photo
/// and corners it came from (when known) so the crop can be edited later.
class ScanShot {
  const ScanShot(this.cropped, {this.original, this.quad});
  final String cropped;
  final String? original;
  final Quad? quad;
}

/// Puts an ID card's front and back on one A4 page (150 dpi), front above
/// back, on white. [paths] holds the two images. Runs in an isolate via `compute`.
Future<Uint8List> combineIdCard(List<String> paths) async {
  const w = 1240, h = 1754, maxW = 1000, maxH = 700;
  final page = img.Image(width: w, height: h, numChannels: 3);
  img.fill(page, color: img.ColorRgb8(255, 255, 255));
  final centres = [h * 0.27, h * 0.73];
  for (var i = 0; i < paths.length && i < 2; i++) {
    final decoded = await img.decodeImageFile(paths[i]);
    if (decoded == null) throw StateError('Gagal membaca gambar: ${paths[i]}');
    final card = img.bakeOrientation(decoded);
    final k = math.min(maxW / card.width, maxH / card.height);
    final cw = (card.width * k).round(), ch = (card.height * k).round();
    final scaled = img.copyResize(card, width: cw, height: ch, interpolation: img.Interpolation.average);
    img.compositeImage(page, scaled, dstX: ((w - cw) / 2).round(), dstY: (centres[i] - ch / 2).round());
  }
  return Uint8List.fromList(img.encodeJpg(page, quality: 92));
}
