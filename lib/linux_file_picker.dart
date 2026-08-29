import 'dart:convert';

import 'package:dbus/dbus.dart';

/// XDG Desktop Portal FileChooser over the DBus session bus. Wrap calls in
/// `runPicker`, which turns a missing bus or portal into
/// `FilePickerUnavailable`.
class LinuxFilePicker {
  LinuxFilePicker({DBusClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? DBusClient.session;

  final DBusClient Function() _clientFactory;
  int _tokenCounter = 0;

  /// Shows the open-file dialog. Returns the picked path, or null if the
  /// user cancelled. [allowedExtensions] become a glob filter (`*.ext`);
  /// [currentFolder] is where the dialog opens (a remembered folder).
  Future<String?> openFile(
          {List<String>? allowedExtensions, String? currentFolder}) =>
      _request('OpenFile', _options(allowedExtensions, currentFolder));

  /// Shows the save-as dialog, suggesting [fileName], opening in
  /// [currentFolder] when given. Returns the chosen path, or null if the user
  /// cancelled.
  Future<String?> saveFile(
      {String? fileName,
      List<String>? allowedExtensions,
      String? currentFolder}) {
    final options = _options(allowedExtensions, currentFolder);
    if (fileName != null) {
      options['current_name'] = DBusString(fileName);
    }
    return _request('SaveFile', options);
  }

  /// Shows the folder dialog (`OpenFile` with `directory`). Returns the
  /// picked folder path, or null if the user cancelled.
  Future<String?> pickDirectory() => _request('OpenFile', {
        'multiple': const DBusBoolean(false),
        'directory': const DBusBoolean(true),
      });

  Map<String, DBusValue> _options(
      List<String>? allowedExtensions, String? currentFolder) {
    final options = <String, DBusValue>{
      'multiple': const DBusBoolean(false),
    };
    // The portal takes the folder as a NUL-terminated byte string; a portal
    // too old to know the option ignores it.
    if (currentFolder != null && currentFolder.isNotEmpty) {
      options['current_folder'] =
          DBusArray.byte([...utf8.encode(currentFolder), 0]);
    }
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      options['filters'] = DBusArray(DBusSignature('(sa(us))'), [
        for (final ext in allowedExtensions)
          DBusStruct([
            DBusString('*.$ext'),
            DBusArray(DBusSignature('(us)'), [
              DBusStruct([const DBusUint32(0), DBusString('*.$ext')]),
            ]),
          ]),
      ]);
    }
    return options;
  }

  Future<String?> _request(
      String method, Map<String, DBusValue> options) async {
    final client = _clientFactory();
    try {
      final token = 'gabbro_${_tokenCounter++}';
      options['handle_token'] = DBusString(token);

      // Probe the bus before subscribing: the subscription's connect is
      // fire-and-forget inside the dbus package, so on a dead bus its error
      // is uncatchable. ping fails catchably instead.
      await client.ping();

      // Subscribe before calling: the Response signal arrives on the request
      // object, whose path ends with our token.
      final responses = DBusSignalStream(
        client,
        interface: 'org.freedesktop.portal.Request',
        name: 'Response',
        signature: DBusSignature('ua{sv}'),
      );
      final response = responses
          .firstWhere((s) => s.path.value.endsWith('/$token'));

      // A dead bus fails both the subscription and the call below with the
      // same error; without this the subscription's copy is an unhandled
      // async error.
      response.ignore();

      await client.callMethod(
        destination: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
        interface: 'org.freedesktop.portal.FileChooser',
        name: method,
        values: [
          const DBusString(''), // parent window
          const DBusString(''), // title: the portal supplies its own
          DBusDict.stringVariant(options),
        ],
        replySignature: DBusSignature('o'),
      );

      final signal = await response;
      final code = (signal.values[0] as DBusUint32).value;
      if (code != 0) return null; // 1 = cancelled, 2 = other
      final results = (signal.values[1] as DBusDict).children.map(
            (k, v) => MapEntry(
              (k as DBusString).value,
              (v as DBusVariant).value,
            ),
          );
      final uris = (results['uris'] as DBusArray)
          .children
          .map((c) => (c as DBusString).value)
          .toList();
      if (uris.isEmpty) return null;
      return Uri.parse(uris.first).toFilePath();
    } finally {
      await client.close();
    }
  }
}
