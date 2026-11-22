import 'package:flutter_test/flutter_test.dart';
import 'package:lembar/models.dart';

void main() {
  test('deleted timestamp round-trips through JSON', () {
    final d = Doc(id: '1', name: 'a', created: DateTime(2026), deleted: DateTime(2026, 2, 3));
    final back = Doc.fromJson(d.toJson());
    expect(back.deleted, DateTime(2026, 2, 3));
    expect(Doc.fromJson(Doc(id: '2', name: 'b', created: DateTime(2026)).toJson()).deleted, isNull);
  });
}
