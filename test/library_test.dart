import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/crop.dart';
import 'package:lembar/filters.dart';
import 'package:lembar/models.dart';

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('lembar_lib'));

  Doc doc(String name, DateTime t, {int pages = 1, String? folder}) => Doc(
        id: name,
        name: name,
        created: t,
        folder: folder,
        pages: [for (var i = 0; i < pages; i++) PageItem(file: '$i.jpg')],
      );

  test('DocSort orders documents and Doc keeps its folder', () {
    final a = doc('banana', DateTime(2026, 1, 1), pages: 3, folder: 'Kerja');
    final b = doc('Apple', DateTime(2026, 3, 1));
    final c = doc('cherry', DateTime(2026, 2, 1), pages: 2);
    List<String> order(DocSort s) => ([a, b, c]..sort(s.compare)).map((d) => d.name).toList();
    expect(order(DocSort.newest), ['Apple', 'cherry', 'banana']);
    expect(order(DocSort.oldest), ['banana', 'cherry', 'Apple']);
    expect(order(DocSort.name), ['Apple', 'banana', 'cherry']);
    expect(order(DocSort.pages), ['banana', 'cherry', 'Apple']);
    expect(Doc.fromJson(a.toJson()).folder, 'Kerja');
    expect(Doc.fromJson(b.toJson()).folder, isNull);
  });

  test('flattenOnWhite turns transparent areas white', () async {
    final im = img.Image(width: 20, height: 20, numChannels: 4); // fully transparent
    final f = '${dir.path}/t.png';
    File(f).writeAsBytesSync(img.encodePng(im));
    final out = img.decodeJpg(await flattenOnWhite(f))!;
    expect(out.getPixel(10, 10).r, greaterThan(250));
  });

  test('combineIdCard stacks front above back on an A4 page', () async {
    Future<String> card(int v) async {
      final im = img.Image(width: 300, height: 190);
      img.fill(im, color: img.ColorRgb8(v, v, v));
      final f = '${dir.path}/card$v.png';
      File(f).writeAsBytesSync(img.encodePng(im));
      return f;
    }

    final out = img.decodeJpg(await combineIdCard([await card(30), await card(120)]))!;
    expect(out.width, 1240);
    expect(out.height, 1754);
    expect(out.getPixel(620, (1754 * 0.27).round()).r, lessThan(60)); // front, upper
    final back = out.getPixel(620, (1754 * 0.73).round()).r;
    expect(back, inInclusiveRange(90, 150)); // back, lower
    expect(out.getPixel(20, 20).r, greaterThan(250)); // white margin
  });
}
