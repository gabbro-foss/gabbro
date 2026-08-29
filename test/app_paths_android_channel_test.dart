import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';

// S1 of the path_provider replacement: on Android the app-support dir comes
// from our own `app.gabbro.gabbro/paths` channel (Kotlin returns
// `filesDir.path` - exactly what path_provider_android returned).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.gabbro.gabbro/paths');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('androidAppSupportDir asks the paths channel for getAppSupportDir',
      () async {
    String? calledMethod;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calledMethod = call.method;
      return '/data/user/0/app.gabbro.gabbro/files';
    });

    final dir = await GabbroPaths.androidAppSupportDir();

    expect(calledMethod, 'getAppSupportDir');
    expect(dir, '/data/user/0/app.gabbro.gabbro/files');
  });

  test('androidAppSupportDir throws when the channel returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await expectLater(
      GabbroPaths.androidAppSupportDir(),
      throwsA(isA<Exception>()),
    );
  });
}
