// Phase 1 - Linux desktop, no hardware.
//
// Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/entry_edit_test.dart -d linux --profile
//
// Profile (not debug) is required for the same reason as vault_session_test.dart:
// `flutter test -d linux` builds the Rust lib in debug, where Argon2id is too slow,
// and `flutter drive --release` is rejected for non-web. See that file's header.
//
// These tests cover the un-injectable real-bridge calls embedded in the edit/detail
// screens that `flutter test` widget tests mock past:
//   - create_entry_screen.dart `_defaultGetEntry` / `_defaultCreate` / `updateEntry`,
//   - entry_detail_screen.dart:355 (getEntry refresh after clearing history),
//   - entry_detail_screen.dart:374 (getEntry refresh after reverting password).
// The widget glue around these is already covered by `flutter test` with mocked
// callbacks; the value here is the real FFI -> crypto -> disk path for the edit,
// password-history, and revert flows. Passphrase-only (no YubiKey).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  late Directory tmp;
  late String vaultPath;
  final passphrase = utf8.encode('correct horse battery staple');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gabbro_it_');
    vaultPath = '${tmp.path}/test.gabbro';
  });

  tearDown(() async {
    lockVault(); // drop session state regardless of test outcome
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Seeds a passphrase vault with one Login entry and returns its id.
  Future<String> seedLogin({String password = 'first-pass'}) async {
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: password,
      notes: null,
      customFields: const [],
    );
    return (await createEntry(entry: VaultEntryData_Login(login))).id;
  }

  // Rebuilds a Login entry payload from a fetched one, overriding the password.
  // Mirrors create_entry_screen._buildUpdated: keep id/createdAt, blank
  // updatedAt (the bridge stamps it), change the one field, hand the whole
  // entry back to updateEntry. Constructed directly, not via createLoginEntry,
  // because the latter mints a fresh UUID and would not target the same entry.
  LoginEntryData editedPassword(String id, String newPassword) {
    final current = (getEntry(id: id) as VaultEntryData_Login).field0;
    return LoginEntryData(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: '',
      folder: current.folder,
      title: current.title,
      url: current.url,
      username: current.username,
      password: newPassword,
      notes: current.notes,
      customFields: current.customFields,
      previousPassword: current.previousPassword,
    );
  }

  test('edit -> updateEntry records previous_password; real getEntry reads it back',
      () async {
    final id = await seedLogin(password: 'first-pass');

    // Edit mode: change the password and persist through the real bridge.
    final updated = editedPassword(id, 'second-pass');
    await updateEntry(entry: VaultEntryData_Login(updated), expiryDays: null);

    // The un-injectable read path the widget tests mock past.
    final fetched = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(fetched.password, 'second-pass',
        reason: 'updateEntry should persist the new password');
    expect(fetched.previousPassword, isNotNull,
        reason: 'changing the password auto-records the prior one as history');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('clear history -> real getEntry refresh shows no previous_password '
      '(entry_detail_screen.dart:355)', () async {
    final id = await seedLogin(password: 'first-pass');
    await updateEntry(
      entry: VaultEntryData_Login(editedPassword(id, 'second-pass')),
      expiryDays: null,
    );
    expect((getEntry(id: id) as VaultEntryData_Login).field0.previousPassword,
        isNotNull,
        reason: 'precondition: history exists before we clear it');

    // The injectable callback the screen calls, then the un-injectable getEntry
    // refresh it does at :355 to rebuild the detail view.
    await sessionClearPasswordHistory(id: id);
    final fresh = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(fresh.previousPassword, isNull,
        reason: 'clearing history drops previous_password');
    expect(fresh.password, 'second-pass',
        reason: 'clearing history must not touch the current password');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('revert password -> real getEntry refresh restores the prior password '
      '(entry_detail_screen.dart:374)', () async {
    final id = await seedLogin(password: 'first-pass');
    await updateEntry(
      entry: VaultEntryData_Login(editedPassword(id, 'second-pass')),
      expiryDays: null,
    );

    // Injectable revert callback, then the un-injectable getEntry refresh at :374.
    await sessionRevertPassword(id: id);
    final fresh = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(fresh.password, 'first-pass',
        reason: 'revert swaps the current password back to the prior one');
    expect(fresh.previousPassword, isNull,
        reason: 'revert consumes the history entry');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('recorded history survives a real lock -> unlock disk round-trip',
      () async {
    final id = await seedLogin(password: 'first-pass');
    await updateEntry(
      entry: VaultEntryData_Login(editedPassword(id, 'second-pass')),
      expiryDays: null,
    );

    // Drop the in-memory session, then re-derive the key from disk.
    lockVault();
    await unlockVault(passphrase: passphrase, path: vaultPath);

    final reopened = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(reopened.password, 'second-pass');
    expect(reopened.previousPassword, isNotNull,
        reason: 'password history must persist through encryption + disk');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
