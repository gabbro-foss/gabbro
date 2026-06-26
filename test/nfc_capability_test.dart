import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/nfc_capability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.gabbro.gabbro/yubikey');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockHasNfc(Object? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'has_nfc') return handler(call);
      return null;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    nfcAvailable = false;
  });

  test('nfcAvailable becomes true when has_nfc returns true', () async {
    mockHasNfc((_) => true);
    await initNfcCapability();
    expect(nfcAvailable, isTrue);
  });

  test('nfcAvailable becomes false when has_nfc returns false', () async {
    nfcAvailable = true;
    mockHasNfc((_) => false);
    await initNfcCapability();
    expect(nfcAvailable, isFalse);
  });

  test('nfcAvailable is false when the channel throws', () async {
    nfcAvailable = true;
    mockHasNfc((_) => throw PlatformException(code: 'BOOM'));
    await initNfcCapability();
    expect(nfcAvailable, isFalse);
  });

  test('nfcAvailable is false when no handler is registered (Linux)', () async {
    nfcAvailable = true;
    // No handler set -> MissingPluginException, treated as no NFC.
    await initNfcCapability();
    expect(nfcAvailable, isFalse);
  });
}
