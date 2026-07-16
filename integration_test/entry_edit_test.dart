// Phase 1 - Linux desktop, no hardware.
//
// Run with:
//   cd rust && cargo build --release --lib && cd ..
//   dart test integration_test/ -j 1
//
// Plain `dart test` against the release cdylib, for the same reasons as
// vault_session_test.dart: real FFI needs the native lib, and release matters
// because debug Argon2id is too slow. See that file's header.
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

import 'package:test/test.dart';

import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'rust_lib_setup.dart';

void main() {
  setUpAll(() async {
    await initRustLib();
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
    );
  }

  test('edit -> updateEntry records the prior password in unified history',
      () async {
    final id = await seedLogin(password: 'first-pass');

    // Edit mode: change the password and persist through the real bridge.
    final updated = editedPassword(id, 'second-pass');
    await updateEntry(entry: VaultEntryData_Login(updated), expiryDays: null);

    // The un-injectable read path the widget tests mock past.
    final fetched = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(fetched.password, 'second-pass',
        reason: 'updateEntry should persist the new password');
    final hist = await getEntryHistory(id: id);
    expect(hist.any((h) => h.field == 'password' && h.value == 'first-pass'),
        isTrue,
        reason: 'changing the password records the prior one in meta.history');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('delete history record -> real getEntry refresh shows it gone', () async {
    final id = await seedLogin(password: 'first-pass');
    await updateEntry(
      entry: VaultEntryData_Login(editedPassword(id, 'second-pass')),
      expiryDays: null,
    );
    final before = await getEntryHistory(id: id);
    final idx = before.indexWhere((h) => h.field == 'password');
    expect(idx, isNonNegative,
        reason: 'precondition: password history exists before we delete it');

    await deleteHistory(id: id, index: idx);
    final after = await getEntryHistory(id: id);
    expect(after.any((h) => h.field == 'password'), isFalse,
        reason: 'deleting the record drops it from history');
    expect((getEntry(id: id) as VaultEntryData_Login).field0.password,
        'second-pass',
        reason: 'deleting history must not touch the current password');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restore history record -> restores the prior password', () async {
    final id = await seedLogin(password: 'first-pass');
    await updateEntry(
      entry: VaultEntryData_Login(editedPassword(id, 'second-pass')),
      expiryDays: null,
    );
    final before = await getEntryHistory(id: id);
    final idx = before.indexWhere((h) => h.field == 'password');
    expect(idx, isNonNegative, reason: 'precondition: password history exists');

    await restoreHistory(id: id, index: idx);
    final fresh = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(fresh.password, 'first-pass',
        reason: 'restore sets the field back to the recorded value');
    final after = await getEntryHistory(id: id);
    expect(after.any((h) => h.field == 'password'), isFalse,
        reason: 'restore consumes the record');
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
    final hist = await getEntryHistory(id: id);
    expect(hist.any((h) => h.field == 'password'), isTrue,
        reason: 'password history must persist through encryption + disk');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
