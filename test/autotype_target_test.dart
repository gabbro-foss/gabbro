import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/autotype_target.dart';

void main() {
  group('AutotypeTarget', () {
    test('defaults to no target', () {
      expect(AutotypeTarget().loginId, isNull);
    });

    test('setLogin records the id', () {
      final t = AutotypeTarget()..setLogin('login-a');
      expect(t.loginId, 'login-a');
    });

    test('clear resets to null', () {
      final t = AutotypeTarget()..setLogin('login-a');
      t.clear();
      expect(t.loginId, isNull);
    });

    test('clearIf clears when the id matches the current target', () {
      final t = AutotypeTarget()..setLogin('login-a');
      t.clearIf('login-a');
      expect(t.loginId, isNull);
    });

    test('clearIf leaves a newer target untouched when the id differs', () {
      // An older detail screen disposing must not wipe a target a newer screen
      // has since registered.
      final t = AutotypeTarget()..setLogin('login-b');
      t.clearIf('login-a');
      expect(t.loginId, 'login-b');
    });
  });
}
