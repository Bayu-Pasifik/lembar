import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/crop.dart';

img.Image scene(List<(int, int)> poly, {required int bg, required int fg, int w = 600, int h = 800}) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(bg, bg, bg));
  img.fillPolygon(im, vertices: [for (final p in poly) img.Point(p.$1, p.$2)], color: img.ColorRgb8(fg, fg, fg));
  // "text" inside the paper
  for (var y = 300; y < 500; y += 20) {
    img.drawLine(im, x1: 250, y1: y, x2: 380, y2: y, color: img.ColorRgb8(30, 30, 30), thickness: 3);
  }
  return im;
}

void expectNear(Quad q, List<(double, double)> want, {double tol = 0.04}) {
  for (var i = 0; i < 4; i++) {
    final g = q.points[i];
    expect((g.$1 - want[i].$1).abs(), lessThan(tol), reason: 'corner $i x ${g.$1} vs ${want[i].$1}');
    expect((g.$2 - want[i].$2).abs(), lessThan(tol), reason: 'corner $i y ${g.$2} vs ${want[i].$2}');
  }
}

void main() {
  test('finds a tilted white sheet on a mid-gray desk', () {
    final poly = [(120, 100), (480, 160), (440, 700), (80, 640)];
    final q = guessPaper(scene(poly, bg: 110, fg: 235));
    expectNear(q, [for (final p in poly) (p.$1 / 600, p.$2 / 800)]);
  });

  test('finds a sheet on a bright background via colour difference', () {
    final poly = [(100, 120), (500, 100), (520, 680), (90, 700)];
    final q = guessPaper(scene(poly, bg: 215, fg: 250));
    expectNear(q, [for (final p in poly) (p.$1 / 600, p.$2 / 800)], tol: 0.06);
  });

  test('uniform photo falls back to a sane quad', () {
    final im = img.Image(width: 300, height: 400, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(200, 200, 200));
    final q = guessPaper(im);
    expect(q.tl.$1, lessThan(0.5));
    expect(q.br.$1, greaterThan(0.5));
  });
}
