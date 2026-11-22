import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/crop.dart';

void main() {
  late String path;
  late img.Image photo;

  setUpAll(() {
    // Dark desk with a bright paper at x 100..300, y 60..260.
    photo = img.Image(width: 400, height: 320);
    img.fill(photo, color: img.ColorRgb8(30, 30, 30));
    img.fillRect(photo, x1: 100, y1: 60, x2: 300, y2: 260, color: img.ColorRgb8(235, 235, 230));
    path = '${Directory.systemTemp.path}/lembar_crop_test.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(photo));
  });

  test('guessPaper finds the bright rectangle', () {
    final q = guessPaper(photo);
    expect(q.tl.$1, closeTo(0.25, 0.03));
    expect(q.tl.$2, closeTo(0.1875, 0.03));
    expect(q.br.$1, closeTo(0.75, 0.03));
    expect(q.br.$2, closeTo(0.8125, 0.03));
  });

  test('cropQuad outputs the quad region with its size', () async {
    final bytes = await cropQuad(CropJob(path, const Quad((0.25, 0.1875), (0.75, 0.1875), (0.75, 0.8125), (0.25, 0.8125))));
    final out = img.decodeJpg(bytes)!;
    expect(out.width, closeTo(200, 4));
    expect(out.height, closeTo(200, 4));
    final c = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect(c.r, greaterThan(200));
  });
}
