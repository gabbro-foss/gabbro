import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/android_file_picker.dart';

/// Stands in for the Kotlin side: records what Dart asked for and replies with
/// whatever the test sets up.
class _FakePlatform {
  final calls = <MethodCall>[];
  Object? reply;
  Object? error;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFilePicker.channel, (call) async {
      calls.add(call);
      if (error != null) {
        throw PlatformException(code: 'PICKER_FAILED', message: '$error');
      }
      return reply;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFilePicker.channel, null));
  }

  Map<Object?, Object?> get lastArguments =>
      calls.last.arguments as Map<Object?, Object?>;
}

void main() {
  late _FakePlatform platform;
  late AndroidFilePicker picker;

  setUp(() {
    platform = _FakePlatform();
    picker = AndroidFilePicker();
  });

  testWidgets('7: open-with-location sends the start location and returns '
      'path + location; null on cancel', (tester) async {
    platform
      ..install(tester)
      ..reply = {
        'path': '/cache/picker/2/x.json',
        'uri': 'content://docs/document/primary%3ADownload%2Fx.json',
      };
    final picked = await picker.openFileWithLocation(
        allowedExtensions: ['json'],
        initialLocation: 'content://docs/document/primary%3ADownload');
    expect(platform.calls.single.method, 'pick_file');
    expect(platform.lastArguments['initial_uri'],
        'content://docs/document/primary%3ADownload');
    expect(picked, (
      path: '/cache/picker/2/x.json',
      location: 'content://docs/document/primary%3ADownload%2Fx.json',
    ));

    platform.reply = null;
    expect(await picker.openFileWithLocation(), isNull);
  });

  testWidgets('1: open sends the requested extensions and returns the path',
      (tester) async {
    platform
      ..install(tester)
      ..reply = {
        'path': '/data/user/0/app.gabbro.gabbro/cache/picker/1/vault.gabbro',
        'uri': 'content://docs/document/primary%3ADownload%2Fvault.gabbro',
      };

    final path = await picker.openFile(allowedExtensions: ['gabbro']);

    expect(path, '/data/user/0/app.gabbro.gabbro/cache/picker/1/vault.gabbro');
    expect(platform.calls.single.method, 'pick_file');
    expect(platform.lastArguments['extensions'], ['gabbro']);
  });

  testWidgets('2: open with no filter sends no extensions', (tester) async {
    platform
      ..install(tester)
      ..reply = {'path': '/cache/picker/1/any.bin', 'uri': 'content://x'};

    await picker.openFile();

    expect(platform.lastArguments['extensions'], isNull);
  });

  testWidgets('3: open returns null when the user cancels', (tester) async {
    platform
      ..install(tester)
      ..reply = null;

    expect(await picker.openFile(allowedExtensions: ['gabbro']), isNull);
  });

  testWidgets('4: open-with-bytes returns the name and bytes', (tester) async {
    platform
      ..install(tester)
      ..reply = {
        'name': 'doc.pdf',
        'bytes': Uint8List.fromList([1, 2, 3]),
      };

    final picked = await picker.openFileWithData();

    expect(picked, isNotNull);
    expect(picked!.name, 'doc.pdf');
    expect(picked.bytes, [1, 2, 3]);
    expect(platform.calls.single.method, 'pick_file_bytes');
  });

  testWidgets('5: open-with-bytes returns null when the user cancels',
      (tester) async {
    platform
      ..install(tester)
      ..reply = null;

    expect(await picker.openFileWithData(), isNull);
  });

  testWidgets('6: folder pick returns the path, null on cancel',
      (tester) async {
    platform
      ..install(tester)
      ..reply = '/storage/emulated/0/Download/Gabbro';

    expect(await picker.pickDirectory(), '/storage/emulated/0/Download/Gabbro');
    expect(platform.calls.single.method, 'pick_dir');

    platform.reply = null;
    expect(await picker.pickDirectory(), isNull);
  });

  testWidgets('7: a platform failure propagates so runPicker can catch it',
      (tester) async {
    platform
      ..install(tester)
      ..error = 'no activity';

    await expectLater(
        picker.openFile(allowedExtensions: ['gabbro']), throwsA(isException));
    await expectLater(picker.openFileWithData(), throwsA(isException));
    await expectLater(picker.pickDirectory(), throwsA(isException));
  });
}

