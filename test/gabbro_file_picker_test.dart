import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/android_file_picker.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/linux_file_picker.dart';

/// Records calls instead of talking to any bus.
class _RecordingLinuxPicker extends LinuxFilePicker {
  final calls = <(String, Object?)>[];

  @override
  Future<String?> openFile({List<String>? allowedExtensions}) async {
    calls.add(('openFile', allowedExtensions));
    return '/tmp/from-linux.gabbro';
  }

  @override
  Future<String?> saveFile(
      {String? fileName, List<String>? allowedExtensions}) async {
    calls.add(('saveFile', fileName));
    return '/tmp/saved-linux.gabbro';
  }

  @override
  Future<String?> pickDirectory() async {
    calls.add(('pickDirectory', null));
    return '/tmp/from-linux-folder';
  }
}

/// Cancels every dialog, so no path is ever read from disk.
class _CancellingLinuxPicker extends LinuxFilePicker {
  @override
  Future<String?> openFile({List<String>? allowedExtensions}) async => null;

  @override
  Future<String?> saveFile(
          {String? fileName, List<String>? allowedExtensions}) async =>
      null;

  @override
  Future<String?> pickDirectory() async => null;
}

/// Returns a fixed path (or null) from openFile.
class _PathReturningLinuxPicker extends LinuxFilePicker {
  _PathReturningLinuxPicker(this.path);
  final String? path;

  @override
  Future<String?> openFile({List<String>? allowedExtensions}) async => path;
}

/// Stands in for the Kotlin picker handler, so a test can see which channel
/// method the facade's Android leg actually reaches.
class _RecordingChannel {
  final calls = <MethodCall>[];
  Object? reply;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFilePicker.channel, (call) async {
      calls.add(call);
      return reply;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFilePicker.channel, null));
  }
}

void main() {
  late bool Function() origIsLinux;
  late LinuxFilePicker origLinux;
  late Future<String?> Function({List<String>? allowedExtensions}) origAndroidPick;

  setUp(() {
    origIsLinux = GabbroFilePicker.isLinux;
    origLinux = GabbroFilePicker.linuxPicker;
    origAndroidPick = GabbroFilePicker.androidPickPath;
  });

  tearDown(() {
    GabbroFilePicker.isLinux = origIsLinux;
    GabbroFilePicker.linuxPicker = origLinux;
    GabbroFilePicker.androidPickPath = origAndroidPick;
  });

  test('T7: on Linux the facade routes to the portal client, filters intact',
      () async {
    final linux = _RecordingLinuxPicker();
    GabbroFilePicker.isLinux = () => true;
    GabbroFilePicker.linuxPicker = linux;

    final picked =
        await GabbroFilePicker.pickPath(allowedExtensions: ['gabbro']);
    expect(picked, '/tmp/from-linux.gabbro');

    final saved = await GabbroFilePicker.savePath(fileName: 'vault.gabbro');
    expect(saved, '/tmp/saved-linux.gabbro');

    expect(linux.calls, hasLength(2));
    expect(linux.calls[0].$1, 'openFile');
    expect(linux.calls[0].$2, ['gabbro']);
    expect(linux.calls[1].$1, 'saveFile');
    expect(linux.calls[1].$2, 'vault.gabbro');
  });

  test('T8: pickFileWithData loads name and bytes from the picked path',
      () async {
    final tmp = await Directory.systemTemp.createTemp('gabbro_pick_test');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/doc.pdf');
    await file.writeAsBytes([1, 2, 3]);

    GabbroFilePicker.isLinux = () => true;
    GabbroFilePicker.linuxPicker = _PathReturningLinuxPicker(file.path);

    final picked = await GabbroFilePicker.pickFileWithData();

    expect(picked, isNotNull);
    expect(picked!.name, 'doc.pdf');
    expect(picked.bytes, [1, 2, 3]);
  });

  test('T8: pickFileWithData returns null on cancel', () async {
    GabbroFilePicker.isLinux = () => true;
    GabbroFilePicker.linuxPicker = _PathReturningLinuxPicker(null);

    expect(await GabbroFilePicker.pickFileWithData(), isNull);
  });

  testWidgets('13: off Linux pickPath asks our picker channel to open a file',
      (tester) async {
    final linux = _RecordingLinuxPicker();
    final channel = _RecordingChannel()
      ..install(tester)
      ..reply = '/data/cache/gabbro_picker/0/vault.gabbro';
    GabbroFilePicker.isLinux = () => false;
    GabbroFilePicker.linuxPicker = linux;

    final picked =
        await GabbroFilePicker.pickPath(allowedExtensions: ['gabbro']);

    expect(picked, '/data/cache/gabbro_picker/0/vault.gabbro');
    expect(channel.calls.single.method, 'pick_file');
    expect((channel.calls.single.arguments as Map)['extensions'], ['gabbro']);
    expect(linux.calls, isEmpty);
  });

  testWidgets(
      '13: off Linux pickFileWithData asks our picker channel for the bytes',
      (tester) async {
    final linux = _RecordingLinuxPicker();
    final channel = _RecordingChannel()
      ..install(tester)
      ..reply = {
        'name': 'doc.pdf',
        'bytes': Uint8List.fromList([7, 8]),
      };
    GabbroFilePicker.isLinux = () => false;
    GabbroFilePicker.linuxPicker = linux;

    final picked = await GabbroFilePicker.pickFileWithData();

    expect(picked, isNotNull);
    expect(picked!.name, 'doc.pdf');
    expect(picked.bytes, [7, 8]);
    expect(channel.calls.single.method, 'pick_file_bytes');
    expect(linux.calls, isEmpty);
  });

  testWidgets('13: the folder leg asks our picker channel for a directory',
      (tester) async {
    final channel = _RecordingChannel()
      ..install(tester)
      ..reply = '/storage/emulated/0/Download/Gabbro';
    GabbroFilePicker.isLinux = () => false;

    expect(await GabbroFilePicker.androidPickDirectory(),
        '/storage/emulated/0/Download/Gabbro');
    expect(channel.calls.single.method, 'pick_dir');
  });

  test('N5: on Linux no Android leg is called', () async {
    final origPick = GabbroFilePicker.androidPickPath;
    final origPickData = GabbroFilePicker.androidPickFileWithData;
    final origPickDir = GabbroFilePicker.androidPickDirectory;
    addTearDown(() {
      GabbroFilePicker.androidPickPath = origPick;
      GabbroFilePicker.androidPickFileWithData = origPickData;
      GabbroFilePicker.androidPickDirectory = origPickDir;
    });

    final androidCalls = <String>[];
    GabbroFilePicker.isLinux = () => true;
    GabbroFilePicker.linuxPicker = _CancellingLinuxPicker();
    GabbroFilePicker.androidPickPath = ({allowedExtensions}) async {
      androidCalls.add('pickPath');
      return null;
    };
    GabbroFilePicker.androidPickFileWithData = () async {
      androidCalls.add('pickFileWithData');
      return null;
    };
    GabbroFilePicker.androidPickDirectory = () async {
      androidCalls.add('pickDirectory');
      return null;
    };

    await GabbroFilePicker.pickPath(allowedExtensions: ['gabbro']);
    await GabbroFilePicker.savePath(fileName: 'vault.gabbro');
    await GabbroFilePicker.pickFileWithData();
    await GabbroFilePicker.pickDirectory();

    expect(androidCalls, isEmpty);
  });

  test('S5: on Linux pickDirectory routes to the portal client', () async {
    final linux = _RecordingLinuxPicker();
    GabbroFilePicker.isLinux = () => true;
    GabbroFilePicker.linuxPicker = linux;

    expect(await GabbroFilePicker.pickDirectory(), '/tmp/from-linux-folder');
    expect(linux.calls.single.$1, 'pickDirectory');
  });

  testWidgets('S5: off Linux pickDirectory asks our picker channel',
      (tester) async {
    final channel = _RecordingChannel()
      ..install(tester)
      ..reply = 'content://tree/primary%3ADownload%2FGabbroSync';
    GabbroFilePicker.isLinux = () => false;

    expect(await GabbroFilePicker.pickDirectory(),
        'content://tree/primary%3ADownload%2FGabbroSync');
    expect(channel.calls.single.method, 'pick_dir');
  });

  test('14: off Linux savePath is refused - no save dialog is reachable there',
      () {
    final linux = _RecordingLinuxPicker();
    GabbroFilePicker.isLinux = () => false;
    GabbroFilePicker.linuxPicker = linux;

    expect(
        () => GabbroFilePicker.savePath(
            fileName: 'vault.gabbro', allowedExtensions: ['gabbro']),
        throwsUnsupportedError);
    expect(linux.calls, isEmpty);
  });

}
