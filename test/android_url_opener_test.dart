import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/android_url_opener.dart';

/// Stands in for the Kotlin side: records what Dart asked for and replies with
/// whatever the test sets up.
class _FakePlatform {
  final calls = <MethodCall>[];
  Object? reply;
  Object? error;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidUrlOpener.channel, (call) async {
      calls.add(call);
      if (error != null) {
        throw PlatformException(code: 'OPEN_FAILED', message: '$error');
      }
      return reply;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidUrlOpener.channel, null));
  }

  Map<Object?, Object?> get lastArguments =>
      calls.last.arguments as Map<Object?, Object?>;
}

void main() {
  late _FakePlatform platform;
  late AndroidUrlOpener opener;

  setUp(() {
    platform = _FakePlatform();
    opener = AndroidUrlOpener();
  });

  testWidgets('3: opening sends the URL and reports what the system did',
      (tester) async {
    platform
      ..install(tester)
      ..reply = true;

    final opened = await opener.open(Uri.parse('https://example.com/docs'));

    expect(opened, isTrue);
    expect(platform.calls.single.method, 'open_url');
    expect(platform.lastArguments['url'], 'https://example.com/docs');
  });

  testWidgets('3: no app to handle the link reports failure', (tester) async {
    platform
      ..install(tester)
      ..reply = false;

    expect(await opener.open(Uri.parse('https://example.com')), isFalse);
  });

  testWidgets('3: a platform failure reports failure, it does not throw',
      (tester) async {
    platform
      ..install(tester)
      ..error = 'no activity';

    expect(await opener.open(Uri.parse('https://example.com')), isFalse);
  });
}
