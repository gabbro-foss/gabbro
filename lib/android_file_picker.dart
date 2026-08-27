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
  Future<String?> openFile(
          {List<String>? allowedExtensions, String? initialLocation}) async =>
      (await openFileWithLocation(
              allowedExtensions: allowedExtensions,
              initialLocation: initialLocation))
          ?.path;

  /// [openFile] plus the picked file's own location (a `content://` document
  /// URI), which a later dialog can be opened at via [initialLocation]: how
  /// the import screen remembers its folder on Android.
  Future<({String path, String location})?> openFileWithLocation(
      {List<String>? allowedExtensions, String? initialLocation}) async {
    final picked = await channel.invokeMapMethod<String, Object?>('pick_file', {
      'extensions': allowedExtensions,
      'initial_uri': initialLocation,
    });
    if (picked == null) return null;
    return (
      path: picked['path'] as String,
      location: picked['uri'] as String? ?? '',
    );
  }

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
