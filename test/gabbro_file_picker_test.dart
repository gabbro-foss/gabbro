import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}

/// Returns a fixed path (or null) from openFile.
class _PathReturningLinuxPicker extends LinuxFilePicker {
  _PathReturningLinuxPicker(this.path);
  final String? path;

  @override
  Future<String?> openFile({List<String>? allowedExtensions}) async => path;
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

  test('T7: off Linux the facade routes to the file_picker leg', () async {
    final linux = _RecordingLinuxPicker();
    var androidCalled = false;
    GabbroFilePicker.isLinux = () => false;
    GabbroFilePicker.linuxPicker = linux;
    GabbroFilePicker.androidPickPath = ({allowedExtensions}) async {
      androidCalled = true;
      return '/storage/from-android.gabbro';
    };

    final picked =
        await GabbroFilePicker.pickPath(allowedExtensions: ['gabbro']);

    expect(picked, '/storage/from-android.gabbro');
    expect(androidCalled, isTrue);
    expect(linux.calls, isEmpty);
  });
}
