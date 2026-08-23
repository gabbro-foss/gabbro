import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_passkeys_flag.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.gabbro.gabbro/app_passkeys');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    debugAppPasskeysIsAndroid = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugAppPasskeysIsAndroid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pushes the enabled flag over the channel', () async {
    await pushAppPasskeysFlag(true);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setAppPasskeys');
    expect(calls.single.arguments, isTrue);
  });

  test('pushes false when disabled', () async {
    await pushAppPasskeysFlag(false);
    expect(calls.single.arguments, isFalse);
  });

  test('does nothing off Android', () async {
    debugAppPasskeysIsAndroid = false;
    await pushAppPasskeysFlag(true);
    expect(calls, isEmpty);
  });

  testWidgets('updateSettings pushes the changed flag over the channel',
      (tester) async {
    await tester.pumpWidget(
      GabbroApp(
        registry: VaultRegistry([]),
        vaultPath: null,
        settings: const AppSettings(),
        // The real home needs the native lib; the flag push does not.
        initialScreen: const SizedBox(),
      ),
    );
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    // Not awaited: save() is real file IO the fake-async test zone never
    // completes; the channel push happens before it.
    unawaited(state.updateSettings(const AppSettings(appPasskeys: true)));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.arguments, isTrue);
  });

  test('a channel failure never escapes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    await pushAppPasskeysFlag(true); // must not throw
  });
}
