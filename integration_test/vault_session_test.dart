// Phase 1 - Linux desktop, no hardware.
//
// Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/vault_session_test.dart -d linux --profile
//
// Profile (not debug) is required: `flutter test -d linux` builds the Rust lib
// in debug, where Argon2id is so slow that init+create blow the 30s timeout;
// `flutter drive --release` is rejected for non-web, so --profile is the path.
// RustLib.init() then loads the actual compiled Rust library and every bridge
// call goes through real FFI -> crypto -> disk. That is the whole point: plain
// `flutter test` (host VM) cannot load the native lib, so the direct bridge calls
// inside the screens (e.g. getEntry at entry_detail_screen.dart:355) are
// unreachable there.
//
// Scope is the passphrase-only vault path (initVault / unlockVault), which needs
// no YubiKey. Multi-key/YubiKey unlock, autofillUnlockMain (Android), and native
// FilePicker flows are gated to later phases - see ARCHITECTURE.md Current Focus.

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

  testWidgets('passphrase vault: init -> createEntry -> getEntry round-trips through real FFI',
      (_) async {
    // Real production Argon2id runs twice here (initVault + the createEntry save);
    // hence the raised per-test timeout and the profile-mode run (see file header).
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

  testWidgets('lock -> unlock with passphrase restores the persisted entry', (_) async {
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

  testWidgets('changePassphrase re-seals; vault re-opens under the new passphrase only',
      (_) async {
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
