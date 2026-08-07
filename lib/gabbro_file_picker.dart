import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'linux_file_picker.dart';

/// A file the user picked to attach: its name and (eagerly-loaded) bytes.
typedef PickedFile = ({String name, Uint8List? bytes});

/// The one file-dialog entry point for all screens.
///
/// Linux talks straight to the XDG portal ([LinuxFilePicker]); everything
/// else still goes through the `file_picker` package until the Android leg
/// replaces it too. All fields are test seams.
class GabbroFilePicker {
  GabbroFilePicker._();

  static bool Function() isLinux = () => Platform.isLinux;
  static LinuxFilePicker linuxPicker = LinuxFilePicker();

  static Future<String?> Function({List<String>? allowedExtensions})
      androidPickPath = _fpPickPath;
  static Future<String?> Function(
      {String? fileName,
      List<String>? allowedExtensions}) androidSavePath = _fpSavePath;

  /// Open-file dialog; returns the picked path or null on cancel.
  static Future<String?> pickPath({List<String>? allowedExtensions}) =>
      isLinux()
          ? linuxPicker.openFile(allowedExtensions: allowedExtensions)
          : androidPickPath(allowedExtensions: allowedExtensions);

  /// Save-as dialog; returns the chosen path or null on cancel.
  static Future<String?> savePath(
          {String? fileName, List<String>? allowedExtensions}) =>
      isLinux()
          ? linuxPicker.saveFile(
              fileName: fileName, allowedExtensions: allowedExtensions)
          : androidSavePath(
              fileName: fileName, allowedExtensions: allowedExtensions);

  /// Open-file dialog that also loads the file's bytes (entry attachments).
  /// Returns null on cancel.
  static Future<PickedFile?> pickFileWithData() async {
    if (!isLinux()) return androidPickFileWithData();
    final path = await linuxPicker.openFile();
    if (path == null) return null;
    final file = File(path);
    return (
      name: file.uri.pathSegments.last,
      bytes: await file.readAsBytes(),
    );
  }

  static Future<PickedFile?> Function() androidPickFileWithData =
      _fpPickFileWithData;

  /// Folder picker — reached only by Android flows (SAF trees); Linux flows
  /// use save dialogs instead.
  static Future<String?> Function() androidPickDirectory = _fpPickDirectory;

  // ── file_picker package legs (Android until its own leg lands) ─────────────

  static Future<PickedFile?> _fpPickFileWithData() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return (name: f.name, bytes: f.bytes);
  }

  static Future<String?> _fpPickPath(
      {List<String>? allowedExtensions}) async {
    final result = await FilePicker.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    return result?.files.single.path;
  }

  static Future<String?> _fpPickDirectory() => FilePicker.getDirectoryPath();

  static Future<String?> _fpSavePath(
          {String? fileName, List<String>? allowedExtensions}) =>
      FilePicker.saveFile(fileName: fileName);
}
