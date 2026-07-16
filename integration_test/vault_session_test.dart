// Phase 1 - Linux desktop, no hardware.
//
// Run with:
//   cd rust && cargo build --release --lib && cd ..
//   dart test integration_test/ -j 1
//
// Plain `dart test`: no Flutter, no window, no GL. The suite loads the compiled
// Rust cdylib directly (see rust_lib_setup.dart), so every bridge call goes
// through real FFI -> crypto -> disk. That is the whole point: `flutter test`
// (host VM) cannot load the native lib, so the direct bridge calls inside the
// screens (e.g. getEntry at entry_detail_screen.dart:355) are unreachable there.
// Nothing here touches the UI, so nothing here needs a window - see ADR on the
// drive-harness removal in ARCHITECTURE.md.
//
// Scope is the passphrase-only vault path (initVault / unlockVault), which needs
// no YubiKey. Multi-key/YubiKey unlock, autofillUnlockMain (Android) and native
// FilePicker flows are deliberately out of scope here: they are covered by the Rust
// suites (yubikey_session_tests / yubikey_mgmt_tests / autofill_tests), the Kotlin
// unit tests, the Flutter widget tests, and the hardware matrix.

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

  test('passphrase vault: init -> createEntry -> getEntry round-trips through real FFI',
      () async {
    // Real production Argon2id runs twice here (initVault + the createEntry save);
    // hence the raised per-test timeout and the release-built cdylib (see file header).
    // initVault seals a new passphrase-only vault and unlocks it into session.
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    expect(File(vaultPath).existsSync(), isTrue,
        reason: 'real Argon2id + encryption should have written the .gabbro file');

    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: 's3cret',
      notes: null,
      customFields: const [],
    );
    final summary = await createEntry(entry: VaultEntryData_Login(login));

    // The un-injectable read path the widget tests mock past.
    final fetched = getEntry(id: summary.id);
    expect(fetched, isA<VaultEntryData_Login>());
    final got = (fetched as VaultEntryData_Login).field0;
    expect(got.title, 'Example');
    expect(got.username, 'alice');
    expect(got.password, 's3cret');
    expect(got.url, 'https://example.com');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('lock -> unlock with passphrase restores the persisted entry', () async {
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Persisted',
      url: 'https://persist.example',
      username: 'bob',
      password: 'p4ss',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;

    // Drop the in-memory session entirely; the entry now lives only on disk.
    lockVault();
    expect(() => getEntry(id: id), throwsA(anything),
        reason: 'reads must fail once the session is locked');

    // Re-derive the key from the passphrase and re-open the same file.
    await unlockVault(passphrase: passphrase, path: vaultPath);
    final reopened = getEntry(id: id);
    expect(reopened, isA<VaultEntryData_Login>());
    expect((reopened as VaultEntryData_Login).field0.username, 'bob');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('changePassphrase re-seals; vault re-opens under the new passphrase only',
      () async {
    // Proves the Flutter FFI marshals changePassphrase's two byte-vector
    // arguments and that the real re-seal round-trips on a device. The vault-level
    // backward-compat of this path (from frozen v6/v7 bytes, multi-key) is the
    // Rust gate's job; this is purely the bridge round-trip.
    final newPassphrase = utf8.encode('an entirely different passphrase');
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Rotated',
      url: 'https://rotate.example',
      username: 'carol',
      password: 'p4ss',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;

    await changePassphrase(
      oldPassphrase: passphrase,
      newPassphrase: newPassphrase,
    );

    // Drop the session and prove the file now opens only under the new passphrase.
    lockVault();
    await expectLater(unlockVault(passphrase: passphrase, path: vaultPath),
        throwsA(anything),
        reason: 'the old passphrase must be rejected after the change');

    await unlockVault(passphrase: newPassphrase, path: vaultPath);
    final reopened = getEntry(id: id);
    expect((reopened as VaultEntryData_Login).field0.username, 'carol',
        reason: 'the entry must survive the re-seal under the new passphrase');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
