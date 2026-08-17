// Real-FFI reproduction of the S15 hardware failure: re-importing the same
// CSV must import nothing, including after the vault has been locked and
// re-unlocked (the auto-lock round trip the app hits between two imports).
//
// Run: dart test integration_test/import_reimport_test.dart -j 1
// Needs the release cdylib (see rust_lib_setup.dart).

import 'dart:io';

import 'package:test/test.dart';

import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'rust_lib_setup.dart';

const _passphrase = '0123456789a';
const _config = CsvImportConfigData(
  titleCol: 'name',
  urlCol: 'url',
  usernameCol: 'username',
  passwordCol: 'password',
  notesCol: 'notes',
);

void main() {
  late Directory tempDir;
  late String vaultPath;
  late String csv;

  setUpAll(() async {
    await initRustLib();
    csv = File('test_data/passwords_valid.csv').readAsStringSync();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gabbro_reimport_');
    vaultPath = '${tempDir.path}/scratch.gabbro';
    File('test_data/migration_vaults/v11.gabbro').copySync(vaultPath);
  });

  tearDown(() {
    try {
      lockVault();
    } catch (_) {}
    tempDir.deleteSync(recursive: true);
  });

  test('re-import in the same session imports nothing', () async {
    await unlockVault(passphrase: _passphrase.codeUnits, path: vaultPath);
    final first = await importFromCsv(input: csv, config: _config);
    expect(first.imported.toInt(), 3);
    final second = await importFromCsv(input: csv, config: _config);
    expect(second.skipped.length, 3);
    expect(second.imported.toInt(), 0);
  });

  test('re-import after lock -> unlock imports nothing', () async {
    await unlockVault(passphrase: _passphrase.codeUnits, path: vaultPath);
    final first = await importFromCsv(input: csv, config: _config);
    expect(first.imported.toInt(), 3);
    lockVault();
    await unlockVault(passphrase: _passphrase.codeUnits, path: vaultPath);
    final second = await importFromCsv(input: csv, config: _config);
    expect(second.skipped.length, 3);
    expect(second.imported.toInt(), 0);
  });
}
