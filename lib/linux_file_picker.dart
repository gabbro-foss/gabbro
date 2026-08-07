import 'package:dbus/dbus.dart';

/// Native file dialogs on Linux, spoken directly to the XDG Desktop Portal
/// (`org.freedesktop.portal.FileChooser`) over the DBus session bus — the
/// same conversation `file_picker` holds today, without the plugin.
///
/// Callers wrap invocations in `runPicker` (see `safe_file_picker.dart`),
/// which turns any thrown error (no bus, no portal) into
/// `FilePickerUnavailable`.
class LinuxFilePicker {
  LinuxFilePicker({DBusClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? DBusClient.session;

  final DBusClient Function() _clientFactory;
  int _tokenCounter = 0;

  /// Shows the open-file dialog. Returns the picked path, or null if the
  /// user cancelled. [allowedExtensions] become a glob filter (`*.ext`).
  Future<String?> openFile({List<String>? allowedExtensions}) =>
      _request('OpenFile', _options(allowedExtensions));

  /// Shows the save-as dialog, suggesting [fileName]. Returns the chosen
  /// path, or null if the user cancelled.
  Future<String?> saveFile(
      {String? fileName, List<String>? allowedExtensions}) {
    final options = _options(allowedExtensions);
    if (fileName != null) {
      options['current_name'] = DBusString(fileName);
    }
    return _request('SaveFile', options);
  }

  Map<String, DBusValue> _options(List<String>? allowedExtensions) {
    final options = <String, DBusValue>{
      'multiple': const DBusBoolean(false),
    };
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
