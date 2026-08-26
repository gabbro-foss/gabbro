import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/linux_file_picker.dart';

// ── Fake XDG portal ───────────────────────────────────────────────────────────
//
// A real org.freedesktop.portal.FileChooser stand-in served on a private bus:
// records what the client asked for, then emits the portal's Response signal
// from the request object, exactly as the desktop portal does. This proves the
// wire protocol without any window.

/// The Request object the portal hands back; emits the Response signal.
class _FakeRequest extends DBusObject {
  _FakeRequest(super.path);
}

class _FakePortal extends DBusObject {
  _FakePortal({required this.response, required this.uris})
      : super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  /// Portal response code: 0 = picked, 1 = cancelled.
  final int response;
  final List<String> uris;

  String? lastMethod;
  Map<String, DBusValue>? lastOptions;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.freedesktop.portal.FileChooser') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    lastMethod = call.name;
    final options = (call.values[2] as DBusDict).children.map(
          (k, v) => MapEntry(
            (k as DBusString).value,
            (v as DBusVariant).value,
          ),
        );
    lastOptions = options;

    final token = (options['handle_token'] as DBusString).value;
    final sender = call.sender!.substring(1).replaceAll('.', '_');
    final requestPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$sender/$token');
    final request = _FakeRequest(requestPath);
    await client!.registerObject(request);

    // Emit Response after the method returns, as the real portal does. The
    // small delay lets the caller's signal subscription land first.
    Future<void>.delayed(const Duration(milliseconds: 100), () async {
      await request.emitSignal(
        'org.freedesktop.portal.Request',
        'Response',
        [
          DBusUint32(response),
          DBusDict.stringVariant({
            'uris': DBusArray.string(uris),
          }),
        ],
      );
    });

    return DBusMethodSuccessResponse([requestPath]);
  }
}

/// Spins up a private bus + fake portal; returns a client factory for
/// [LinuxFilePicker] plus the fake for assertions and a teardown.
Future<
    ({
      _FakePortal portal,
      DBusClient Function() clientFactory,
      Future<void> Function() close,
    })> _startFakePortal({int response = 0, List<String> uris = const []}) async {
  final server = DBusServer();
  final tmp = await Directory.systemTemp.createTemp('gabbro_dbus_test');
  final address = await server.listenAddress(
      DBusAddress.unix(path: '${tmp.path}/bus.sock'));

  final portalClient = DBusClient(address);
  final portal = _FakePortal(response: response, uris: uris);
  await portalClient.requestName('org.freedesktop.portal.Desktop');
  await portalClient.registerObject(portal);

  final pickerClients = <DBusClient>[];
  DBusClient clientFactory() {
    final c = DBusClient(address);
    pickerClients.add(c);
    return c;
  }

  Future<void> close() async {
    for (final c in pickerClients) {
      await c.close();
    }
    await portalClient.close();
    await server.close();
    await tmp.delete(recursive: true);
  }

  return (portal: portal, clientFactory: clientFactory, close: close);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test(
      'T1: openFile sends OpenFile with a glob filter and single-select, '
      'returns the picked path', () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///tmp/picked.gabbro'],
    );
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.openFile(allowedExtensions: ['gabbro']);

    expect(path, '/tmp/picked.gabbro');
    expect(fake.portal.lastMethod, 'OpenFile');

    final options = fake.portal.lastOptions!;
    expect((options['multiple'] as DBusBoolean).value, isFalse);

    final filters = (options['filters'] as DBusArray).children;
    expect(filters, hasLength(1));
    final filter = filters.single as DBusStruct;
    final patterns = (filter.children[1] as DBusArray).children;
    final pattern = patterns.single as DBusStruct;
    expect((pattern.children[0] as DBusUint32).value, 0,
        reason: '0 = glob pattern, per the portal spec');
    expect((pattern.children[1] as DBusString).value, '*.gabbro');
  });

  test('T2: openFile returns null when the user cancels', () async {
    final fake = await _startFakePortal(response: 1);
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.openFile(allowedExtensions: ['gabbro']);

    expect(path, isNull);
  });

  test(
      'T3: saveFile sends SaveFile with the suggested filename and filter, '
      'returns the path', () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///tmp/out/vault.gabbro'],
    );
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.saveFile(
      fileName: 'vault.gabbro',
      allowedExtensions: ['gabbro'],
    );

    expect(path, '/tmp/out/vault.gabbro');
    expect(fake.portal.lastMethod, 'SaveFile');

    final options = fake.portal.lastOptions!;
    expect((options['current_name'] as DBusString).value, 'vault.gabbro');
    final filters = (options['filters'] as DBusArray).children;
    expect(filters, hasLength(1));
  });

  test('T4: saveFile returns null when the user cancels', () async {
    final fake = await _startFakePortal(response: 1);
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.saveFile(fileName: 'vault.gabbro');

    expect(path, isNull);
  });

  test('T5: an unreachable bus throws (runPicker turns this into the SnackBar)',
      () async {
    final picker = LinuxFilePicker(
      clientFactory: () => DBusClient(
        DBusAddress.unix(path: '/nonexistent/gabbro-no-such-bus.sock'),
      ),
    );

    await expectLater(
      picker.openFile(allowedExtensions: ['gabbro']),
      throwsA(isA<Exception>()),
    );
  });

  test('T6: file:// replies with spaces and accents decode to correct paths',
      () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///tmp/My%20Vault/caf%C3%A9.gabbro'],
    );
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.openFile(allowedExtensions: ['gabbro']);

    expect(path, '/tmp/My Vault/café.gabbro');
  });

  // ── S5: folder picker (sync folder; later export/import folders) ──────────

  test('T7: pickDirectory sends OpenFile with directory=true, returns the path',
      () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///home/user/GabbroSync'],
    );
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    final path = await picker.pickDirectory();

    expect(path, '/home/user/GabbroSync');
    expect(fake.portal.lastMethod, 'OpenFile');
    expect(fake.portal.lastOptions!['directory'], const DBusBoolean(true));
    expect(fake.portal.lastOptions!['multiple'], const DBusBoolean(false));
    expect(fake.portal.lastOptions!.containsKey('filters'), isFalse,
        reason: 'a folder dialog has no file filter');
  });

  test('T8: pickDirectory returns null when the user cancels', () async {
    final fake = await _startFakePortal(response: 1);
    addTearDown(fake.close);

    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    expect(await picker.pickDirectory(), isNull);
  });
  _rememberedFolderTests();
}

// ── Step 3: remembered folders ────────────────────────────────────────────────

/// The portal takes `current_folder` as a NUL-terminated byte string.
List<int> _folderBytes(Map<String, DBusValue> options) =>
    (options['current_folder'] as DBusArray).children.map((c) => (c as DBusByte).value).toList();


void _rememberedFolderTests() {
  test('T9: openFile with a start folder sends current_folder, NUL-terminated',
      () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///home/user/Sync/x.json'],
    );
    addTearDown(fake.close);
    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    await picker.openFile(
        allowedExtensions: ['json'], currentFolder: '/home/user/Sync');
    expect(_folderBytes(fake.portal.lastOptions!),
        [...'/home/user/Sync'.codeUnits, 0]);
  });

  test('T10: saveFile with a start folder sends current_folder, NUL-terminated',
      () async {
    final fake = await _startFakePortal(
      response: 0,
      uris: ['file:///home/user/Sync/vault.gabbro'],
    );
    addTearDown(fake.close);
    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    await picker.saveFile(fileName: 'vault.gabbro', currentFolder: '/home/user/Sync');
    final options = fake.portal.lastOptions!;
    expect((options['current_name'] as DBusString).value, 'vault.gabbro');
    expect(_folderBytes(options), [...'/home/user/Sync'.codeUnits, 0]);
  });

  test('T11: no start folder sends no current_folder', () async {
    final fake = await _startFakePortal(response: 1);
    addTearDown(fake.close);
    final picker = LinuxFilePicker(clientFactory: fake.clientFactory);
    await picker.openFile();
    expect(fake.portal.lastOptions!.containsKey('current_folder'), isFalse);
    await picker.saveFile(fileName: 'a');
    expect(fake.portal.lastOptions!.containsKey('current_folder'), isFalse);
  });
}
