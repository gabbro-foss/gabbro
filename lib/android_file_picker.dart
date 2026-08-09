import 'package:flutter/services.dart';

/// Native file dialogs on Android, spoken to our own Kotlin handler
/// (`GabbroUnlockHostActivity`) instead of the `file_picker` plugin.
///
/// Android hands an app a `content://` reference, not a path. The Kotlin side
/// copies the chosen file into the app cache and returns that path, so every
/// caller keeps working with plain paths.
///
/// Callers wrap invocations in `runPicker` (see `safe_file_picker.dart`),
/// which turns any thrown error into `FilePickerUnavailable`.
class AndroidFilePicker {
  static const channel = MethodChannel('app.gabbro.gabbro/picker');

  /// Shows the open-file dialog. Returns a readable path to a cache copy of
  /// the picked file, or null if the user cancelled. [allowedExtensions]
  /// filters the dialog where Android knows the file type; extensions it does
  /// not recognise (`.gabbro`) show every file rather than nothing.
  Future<String?> openFile({List<String>? allowedExtensions}) =>
      channel.invokeMethod<String>('pick_file', {
        'extensions': allowedExtensions,
      });

  /// Open-file dialog that also returns the file's bytes (entry attachments).
  /// Null if the user cancelled.
  Future<({String name, Uint8List? bytes})?> openFileWithData() async {
    final picked =
        await channel.invokeMapMethod<String, Object?>('pick_file_bytes');
    if (picked == null) return null;
    return (
      name: picked['name'] as String,
      bytes: picked['bytes'] as Uint8List?,
    );
  }

  /// Folder picker. Returns a path the app can write into, or null if the
  /// user cancelled.
  Future<String?> pickDirectory() =>
      channel.invokeMethod<String>('pick_dir');
}
