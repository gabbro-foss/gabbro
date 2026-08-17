// Real-FFI replay of the whole S15 hardware sequence (matrix rows 4-8):
// generic CSV, same CSV again, mixed CSV, Google PM, same Google PM again,
// with a lock -> unlock round trip before every import (the auto-lock the
// app hits between steps). Counts must match the matrix expectations.
//
// Run: dart test integration_test/import_hw_sequence_test.dart -j 1

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
  test('hardware matrix rows 4-8 counts', () async {
    await initRustLib();
    final tempDir = Directory.systemTemp.createTempSync('gabbro_hwseq_');
    addTearDown(() {
      try {
        lockVault();
      } catch (_) {}
      tempDir.deleteSync(recursive: true);
    });
    final vaultPath = '${tempDir.path}/scratch.gabbro';
    File('test_data/migration_vaults/v11.gabbro').copySync(vaultPath);

    final generic = File('test_data/passwords_valid.csv').readAsStringSync();
    final mixed =
        '${generic}Newrow,https://new.example.org,newuser,n3wp4ss,,no\n';
    final google =
        File('test_data/google_valid.csv').readAsBytesSync().toList();

    Future<void> relock() async {
      lockVault();
      await unlockVault(passphrase: _passphrase.codeUnits, path: vaultPath);
    }

    await unlockVault(passphrase: _passphrase.codeUnits, path: vaultPath);

    final r4 = await importFromCsv(input: generic, config: _config);
    expect(r4.imported.toInt(), 3, reason: 'row 4');

    await relock();
    final r5 = await importFromCsv(input: generic, config: _config);
    expect(r5.imported.toInt(), 0, reason: 'row 5');
    expect(r5.skipped.length, 3, reason: 'row 5 skipped');

    await relock();
    final r6 = await importFromCsv(input: mixed, config: _config);
    expect(r6.imported.toInt(), 1, reason: 'row 6');
    expect(r6.skipped.length, 3, reason: 'row 6 skipped');

    await relock();
    final r7 = await importFromGooglePm(data: google);
    expect(r7.imported.toInt(), 8, reason: 'row 7');

    await relock();
    final r8 = await importFromGooglePm(data: google);
    expect(r8.imported.toInt(), 0, reason: 'row 8');
    expect(r8.skipped.length, 8, reason: 'row 8 skipped');
  });
}
