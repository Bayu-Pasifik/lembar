import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/crop.dart';
import 'package:lembar/filters.dart';
import 'package:lembar/models.dart';

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('lembar_adj'));

  String grey(int v) {
    final im = img.Image(width: 40, height: 30);
    img.fill(im, color: img.ColorRgb8(v, v, v));
    final f = '${dir.path}/g$v.jpg';
    File(f).writeAsBytesSync(img.encodeJpg(im, quality: 100));
    return f;
  }

  int centre(PageResult r) => img.decodeJpg(r.bytes)!.getPixel(20, 15).r.toInt();

  test('brightness raises and contrast stretches mid-greys', () async {
    final f = grey(100);
    final base = centre(await processPage(PageJob(f, 0, ScanFilter.original)));
    final bright = centre(await processPage(PageJob(f, 0, ScanFilter.original, brightness: 0.2)));
    final contrasty = centre(await processPage(PageJob(f, 0, ScanFilter.original, contrast: 2)));
    expect(bright, greaterThan(base + 40));
    expect(contrasty, lessThan(base - 20)); // below mid-grey gets darker
  });

  test('signature is stamped where placed', () async {
    final f = grey(240);
    final stamp = img.Image(width: 20, height: 10, numChannels: 4);
    img.fill(stamp, color: img.ColorRgba8(0, 0, 0, 255));
    final sigPath = '${dir.path}/sig.png';
    File(sigPath).writeAsBytesSync(img.encodePng(stamp));
    final r = await processPage(PageJob(f, 0, ScanFilter.original, signature: SignaturePlacement(sigPath, 0.75, 0.5, 0.25)));
    final out = img.decodeJpg(r.bytes)!;
    expect(out.getPixel(30, 15).r, lessThan(60)); // inside the stamp
    expect(out.getPixel(5, 15).r, greaterThan(200)); // untouched
  });

  test('PageItem JSON keeps crop, adjustments and signature', () {
    final p = PageItem(
      file: 'a.jpg',
      original: 'o.jpg',
      quad: Quad.inset.toList(),
      brightness: 0.1,
      contrast: 1.4,
      signature: const SignaturePlacement('s.png', 0.5, 0.6, 0.3),
    );
    final back = PageItem.fromJson(p.toJson());
    expect(back.original, 'o.jpg');
    expect(Quad.fromList(back.quad!).br, Quad.inset.br);
    expect(back.brightness, 0.1);
    expect(back.contrast, 1.4);
    expect(back.signature!.file, 's.png');
    expect(back.signature!.width, 0.3);
    // Old pages without the new fields still load.
    final old = PageItem.fromJson({'file': 'x.jpg'});
    expect(old.adjusted, false);
    expect(old.signature, isNull);
  });
}
