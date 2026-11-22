import 'package:flutter_test/flutter_test.dart';
import 'package:lembar/update_check.dart';

void main() {
  test('isNewer compares semver, ignores v prefix and build', () {
    expect(isNewer('v1.0.1', '1.0.0'), true);
    expect(isNewer('v1.1.0', '1.0.9+3'), true);
    expect(isNewer('v1.0.0', '1.0.0+5'), false);
    expect(isNewer('v0.9.9', '1.0.0'), false);
    expect(isNewer('2', '1.9.9'), true);
  });
}
