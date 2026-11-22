import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lembar/filters.dart';
import 'package:lembar/models.dart';

void main() {
  test('note and tags round-trip through JSON', () {
    final d = Doc(id: '1', name: 'a', created: DateTime(2026), note: 'penting', tags: ['kontrak', 'pajak']);
    final back = Doc.fromJson(d.toJson());
    expect(back.note, 'penting');
    expect(back.tags, ['kontrak', 'pajak']);
    final bare = Doc.fromJson(Doc(id: '2', name: 'b', created: DateTime(2026)).toJson());
    expect(bare.note, isNull);
    expect(bare.tags, isEmpty);
  });

  test('boostColor raises saturation but keeps white and black', () {
    final im = img.Image(width: 3, height: 1);
    im.setPixelRgb(0, 0, 255, 255, 255);
    im.setPixelRgb(1, 0, 0, 0, 0);
    im.setPixelRgb(2, 0, 200, 120, 120);
    final out = boostColor(im);
    expect(out.getPixel(0, 0).r, 255);
    expect(out.getPixel(1, 0).r, lessThan(20));
    final p = out.getPixel(2, 0);
    expect(p.r - p.g, greaterThan(200 - 120));
  });

  test('magic filter is selectable', () {
    expect(ScanFilter.values.map((f) => f.name), contains('magic'));
  });
}
