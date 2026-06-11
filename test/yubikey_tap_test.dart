import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void _setChannelMock(Future<dynamic> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_yubikeyChannel, handler);
}

void _clearChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_yubikeyChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Force the Android (MethodChannel) dispatch branch on the Linux test host.
  setUp(() => isLinuxForTapDispatch = () => false);
  tearDown(() {
    _clearChannelMock();
    isLinuxForTapDispatch = () => Platform.isLinux;
  });

  group('getYubikeyHmacSecret (single-key Android dispatch)', () {
    final credentialId = Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd]);
    final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));
    const hmacHex =
        'eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011';

    test('invokes get_hmac_secret with hex args and returns parsed hmac',
        () async {
      MethodCall? captured;
      _setChannelMock((call) async {
        captured = call;
        return hmacHex;
      });

      final hmac = await getYubikeyHmacSecret(
        credentialId: credentialId,
        salt: salt,
        pin: '123456',
        transport: 'usb',
      );

      expect(captured!.method, 'get_hmac_secret');
      final args = captured!.arguments as Map;
      expect(args['credentialId'], _hex(credentialId));
      expect(args['salt'], _hex(salt));
      expect(args['pin'], '123456');
      expect(args['transport'], 'usb');
      expect(_hex(hmac), hmacHex);
    });
  });

  group('getAnyYubikeyHmacSecret (multi-key Android dispatch)', () {
    final recordA = YubikeyRecordData(
      credentialId: Uint8List.fromList([0x01, 0x02, 0x03]),
      salt: Uint8List.fromList([0x10, 0x11, 0x12]),
    );
    final recordB = YubikeyRecordData(
      credentialId: Uint8List.fromList([0x04, 0x05, 0x06]),
      salt: Uint8List.fromList([0x13, 0x14, 0x15]),
    );
    const hmacHex =
        'eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011';

    test('invokes get_hmac_secret_multi with hex records and parses the match',
        () async {
      MethodCall? captured;
      _setChannelMock((call) async {
        captured = call;
        return {'hmac': hmacHex, 'credentialId': _hex(recordB.credentialId)};
      });

      final match = await getAnyYubikeyHmacSecret(
        records: [recordA, recordB],
        pin: '654321',
        transport: 'nfc',
      );

      expect(captured!.method, 'get_hmac_secret_multi');
      final args = captured!.arguments as Map;
      final records = (args['records'] as List).cast<Map>();
      expect(records[0]['credentialId'], _hex(recordA.credentialId));
      expect(records[0]['salt'], _hex(recordA.salt));
      expect(records[1]['credentialId'], _hex(recordB.credentialId));
      expect(records[1]['salt'], _hex(recordB.salt));
      expect(args['pin'], '654321');
      expect(args['transport'], 'nfc');
      expect(_hex(match.hmac), hmacHex);
      expect(_hex(match.credentialId), _hex(recordB.credentialId));
    });
  });
}
