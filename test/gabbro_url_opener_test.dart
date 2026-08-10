import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/android_url_opener.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/linux_url_opener.dart';

/// Records calls instead of running anything.
class _RecordingLinux extends LinuxUrlOpener {
  _RecordingLinux() : super(runProcess: _never);

  static Future<ProcessResult> _never(String _, List<String> _) async =>
      ProcessResult(0, 0, '', '');

  final opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

class _RecordingAndroid extends AndroidUrlOpener {
  final opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

void main() {
  late _RecordingLinux linux;
  late _RecordingAndroid android;

  setUp(() {
    linux = _RecordingLinux();
    android = _RecordingAndroid();
    GabbroUrlOpener.linuxOpener = linux;
    GabbroUrlOpener.androidOpener = android;
  });

  tearDown(GabbroUrlOpener.reset);

  test('5: on Linux the link goes to the desktop handler', () async {
    GabbroUrlOpener.isLinux = () => true;

    final opened = await GabbroUrlOpener.open('https://example.com');

    expect(opened, isTrue);
    expect(linux.opened.single, Uri.parse('https://example.com'));
    expect(android.opened, isEmpty);
  });

  test('5: off Linux the link goes to the Android channel', () async {
    GabbroUrlOpener.isLinux = () => false;

    final opened = await GabbroUrlOpener.open('https://example.com');

    expect(opened, isTrue);
    expect(android.opened.single, Uri.parse('https://example.com'));
    expect(linux.opened, isEmpty);
  });

  test('5: a URL saved without a scheme still reaches a browser', () async {
    GabbroUrlOpener.isLinux = () => true;

    await GabbroUrlOpener.open('example.com/login');

    expect(linux.opened.single, Uri.parse('https://example.com/login'));
  });

  test('5: browserUri keeps the behaviour entry_detail had', () {
    expect(GabbroUrlOpener.browserUri('example.com'),
        Uri.parse('https://example.com'));
    expect(GabbroUrlOpener.browserUri('http://example.com/x'),
        Uri.parse('http://example.com/x'));
    expect(GabbroUrlOpener.browserUri('http://[::1'), isNull);
  });

  test('5: an address that cannot be read opens nothing', () async {
    GabbroUrlOpener.isLinux = () => true;

    expect(await GabbroUrlOpener.open('http://[::1'), isFalse);
    expect(linux.opened, isEmpty);
  });

  test('5: a failure from the platform is passed back', () async {
    GabbroUrlOpener.isLinux = () => true;
    linux.result = false;

    expect(await GabbroUrlOpener.open('https://example.com'), isFalse);
  });

  // 6: entry URLs are user data, and this button means "open a web page".
  // Handing the system anything else would let a saved entry reach a local
  // file or another program, so only web addresses are passed on.
  group('6: web pages only', () {
    setUp(() => GabbroUrlOpener.isLinux = () => true);

    test('http and https are opened', () async {
      expect(await GabbroUrlOpener.open('http://example.com'), isTrue);
      expect(await GabbroUrlOpener.open('https://example.com'), isTrue);
      expect(linux.opened, hasLength(2));
    });

    test('a local file is refused', () async {
      expect(await GabbroUrlOpener.open('file:///etc/passwd'), isFalse);
      expect(linux.opened, isEmpty);
    });

    test('ftp and ssh are refused', () async {
      expect(await GabbroUrlOpener.open('ftp://example.com'), isFalse);
      expect(await GabbroUrlOpener.open('ssh://example.com'), isFalse);
      expect(linux.opened, isEmpty);
    });

    test('the scheme is judged whatever its case', () async {
      expect(await GabbroUrlOpener.open('HTTPS://example.com'), isTrue);
      expect(await GabbroUrlOpener.open('FILE:///etc/passwd'), isFalse);
      expect(linux.opened, hasLength(1));
    });
  });
}
