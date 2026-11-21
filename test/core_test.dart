import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/filters.dart';
import 'package:lembar/models.dart';

void main() {
  test('Doc JSON roundtrip keeps pages, rotation and filter', () {
    final doc = Doc(
      id: '1',
      name: 'Tes',
      created: DateTime(2026, 11, 22, 8, 30),
      pages: [
        PageItem(file: 'a.jpg', turns: 3, filter: ScanFilter.grayscale),
        PageItem(file: 'b.jpg'),
      ],
    );
    final back = Doc.fromJson(doc.toJson());
    expect(back.name, 'Tes');
    expect(back.pages.length, 2);
    expect(back.pages[0].turns, 3);
    expect(back.pages[0].filter, ScanFilter.grayscale);
    expect(back.pages[1].filter, ScanFilter.document);
  });

  test('OCR text survives JSON roundtrip and is omitted when null', () {
    final withText = PageItem(file: 'a.jpg', text: 'Halo dunia');
    expect(PageItem.fromJson(withText.toJson()).text, 'Halo dunia');
    expect(PageItem(file: 'b.jpg').toJson().containsKey('text'), isFalse);
  });

  test('unknown filter name falls back to document', () {
    final p = PageItem.fromJson({'file': 'x.jpg', 'filter': 'nope'});
    expect(p.filter, ScanFilter.document);
  });

  group('processPage', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lembar_test');
      // 40x20 image, light-grey background.
      final image = img.Image(width: 40, height: 20);
      img.fill(image, color: img.ColorRgb8(200, 200, 200));
      path = '${dir.path}/in.jpg';
      await File(path).writeAsBytes(img.encodeJpg(image));
    });

    tearDown(() => dir.delete(recursive: true));

    test('rotation by one turn swaps dimensions', () async {
      final r = await processPage(PageJob(path, 1, ScanFilter.original));
      expect(r.width, 20);
      expect(r.height, 40);
    });

    test('document filter pushes light grey towards white', () async {
      final r = await processPage(PageJob(path, 0, ScanFilter.document));
      final out = img.decodeJpg(r.bytes)!;
      final px = out.getPixel(10, 10);
      expect(px.r, greaterThan(230));
    });

    test('document filter removes a shadow gradient and keeps the ink', () async {
      // Paper lit from 110 (dark, left) to 230 (bright, right) with a dark text bar.
      final paper = img.Image(width: 400, height: 300);
      for (final p in paper) {
        final v = 110 + (120 * p.x / 399).round();
        p
          ..r = v
          ..g = v
          ..b = v;
      }
      img.fillRect(paper, x1: 150, y1: 140, x2: 250, y2: 150, color: img.ColorRgb8(30, 30, 30));
      final f = '${dir.path}/shadow.png';
      await File(f).writeAsBytes(img.encodePng(paper));

      final r = await processPage(PageJob(f, 0, ScanFilter.document));
      final out = img.decodeJpg(r.bytes)!;
      expect(out.getPixel(15, 40).r, greaterThan(235), reason: 'dark side of paper');
      expect(out.getPixel(385, 40).r, greaterThan(235), reason: 'bright side of paper');
      expect(out.getPixel(200, 145).r, lessThan(90), reason: 'ink stays dark');
    });

    test('colour filter keeps hue but whitens the paper', () async {
      final paper = img.Image(width: 200, height: 200);
      img.fill(paper, color: img.ColorRgb8(180, 170, 140)); // yellowish, dim
      img.fillRect(paper, x1: 90, y1: 90, x2: 110, y2: 100, color: img.ColorRgb8(200, 20, 20));
      final f = '${dir.path}/colour.png';
      await File(f).writeAsBytes(img.encodePng(paper));

      final out = img.decodeJpg((await processPage(PageJob(f, 0, ScanFilter.color))).bytes)!;
      final bg = out.getPixel(10, 10);
      expect(bg.r, greaterThan(225));
      expect(bg.g, greaterThan(225));
      expect(bg.b, greaterThan(225));
      final red = out.getPixel(100, 95);
      expect(red.r, greaterThan(red.g + 60));
    });

    test('maxSide shrinks the longest side', () async {
      final r = await processPage(PageJob(path, 0, ScanFilter.original, maxSide: 20));
      expect(r.width, 20);
      expect(r.height, 10);
    });

    test('grayscale filter removes colour', () async {
      final colour = img.Image(width: 10, height: 10);
      img.fill(colour, color: img.ColorRgb8(220, 30, 30));
      final p = '${dir.path}/c.jpg';
      await File(p).writeAsBytes(img.encodeJpg(colour));
      final r = await processPage(PageJob(p, 0, ScanFilter.grayscale));
      final px = img.decodeJpg(r.bytes)!.getPixel(5, 5);
      expect((px.r - px.g).abs(), lessThan(8));
      expect((px.g - px.b).abs(), lessThan(8));
    });
  });
}
