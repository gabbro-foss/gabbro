import 'dart:io';
import 'dart:typed_data';

import 'android_file_picker.dart';
import 'linux_file_picker.dart';

/// A file the user picked to attach: its name and (eagerly-loaded) bytes.
typedef PickedFile = ({String name, Uint8List? bytes});

/// A picked file and the folder to remember for it (see `pickPathWithFolder`).
typedef PickedPath = ({String path, String folder});

/// The one file-dialog entry point for all screens.
///
/// Linux talks straight to the XDG portal ([LinuxFilePicker]); Android to our
/// own picker channel ([AndroidFilePicker]). No plugin is involved. All fields
/// are test seams.
class GabbroFilePicker {
  GabbroFilePicker._();

  static bool Function() isLinux = () => Platform.isLinux;
  static LinuxFilePicker linuxPicker = LinuxFilePicker();
  static AndroidFilePicker androidPicker = AndroidFilePicker();

  static Future<String?> Function({List<String>? allowedExtensions})
      androidPickPath = _androidPickPath;

  /// Open-file dialog; returns the picked path or null on cancel.
  static Future<String?> pickPath({List<String>? allowedExtensions}) =>
      isLinux()
          ? linuxPicker.openFile(allowedExtensions: allowedExtensions)
          : androidPickPath(allowedExtensions: allowedExtensions);

  /// Open-file dialog that opens in [startFolder] and also reports the picked
  /// file's folder: the value a screen remembers so the next dialog opens
  /// there. Linux: the path's directory. Android: the location the picker
  /// reports (a document URI), the only form the system dialog can reopen at.
  static Future<PickedPath?> pickPathWithFolder(
      {List<String>? allowedExtensions, String? startFolder}) async {
    if (!isLinux()) {
      return androidPickPathWithFolder(
          allowedExtensions: allowedExtensions, startFolder: startFolder);
    }
    final path = await linuxPicker.openFile(
        allowedExtensions: allowedExtensions, currentFolder: startFolder);
    if (path == null) return null;
    return (path: path, folder: File(path).parent.path);
  }

  static Future<PickedPath?> Function(
          {List<String>? allowedExtensions, String? startFolder})
      androidPickPathWithFolder = defaultAndroidPickPathWithFolder;

  static Future<PickedPath?> defaultAndroidPickPathWithFolder(
      {List<String>? allowedExtensions, String? startFolder}) async {
    final picked = await androidPicker.openFileWithLocation(
        allowedExtensions: allowedExtensions, initialLocation: startFolder);
    if (picked == null) return null;
    return (path: picked.path, folder: picked.location);
  }

  /// Save-as dialog; returns the chosen path or null on cancel. Linux only:
  /// Android picks a folder instead and never shows one, so reaching this
  /// anywhere else is a wiring bug — it must fail loudly, not silently.
  static Future<String?> savePath(
      {String? fileName,
      List<String>? allowedExtensions,
      String? startFolder}) {
    if (!isLinux()) {
      throw UnsupportedError('Save dialogs are Linux-only');
    }
    return linuxPicker.saveFile(
        fileName: fileName,
        allowedExtensions: allowedExtensions,
        currentFolder: startFolder);
  }

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
      _androidPickFileWithData;

  /// Folder picker: a portal folder dialog on Linux (returns a path), the
  /// SAF tree picker on Android (returns a tree URI). Null on cancel.
  static Future<String?> pickDirectory() =>
      isLinux() ? linuxPicker.pickDirectory() : androidPickDirectory();

  /// Android folder leg (SAF trees); export reaches it directly.
  static Future<String?> Function() androidPickDirectory = _androidPickDirectory;

  // ── Android legs: our own picker channel ──────────────────────────────────

  static Future<String?> _androidPickPath({List<String>? allowedExtensions}) =>
      androidPicker.openFile(allowedExtensions: allowedExtensions);

  static Future<PickedFile?> _androidPickFileWithData() =>
      androidPicker.openFileWithData();

  static Future<String?> _androidPickDirectory() => androidPicker.pickDirectory();
}
