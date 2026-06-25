// Phase 1 - Linux desktop, no hardware. R-03 P0 diagnostic.
//
// Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/vault_corruption_test.dart -d linux --profile
//
// Profile (not debug) is required for the same reason as vault_session_test.dart:
// `flutter test -d linux` builds the Rust lib in debug, where Argon2id is too slow,
// and `flutter drive --release` is rejected for non-web. See that file's header.
//
// Why this file exists: on real hardware (2026-06-11) a YubiKey vault, after its
// main AND .bak files were overwritten with `printf rubbish`, unlocked with no
// error to an EMPTY vault. That is impossible at the crypto layer — garbage cannot
// pass the AES-GCM auth tag, and there is no auto-create fallback on the load path
// (load_vault / load_vault_with_yubikey both go through SealedVault::from_bytes).
// This suite scripts the maintainer's exact sequence end-to-end through real FFI on the
// passphrase path and pins the invariant: garbage on disk -> unlock FAILS, and no
// empty session is left behind. If this stays green while the device failed, the
// device failure was environmental (a stale build, or the file `ls`/`printf`
// touched was not the path the app reads) — not a Gabbro code bug. The YubiKey
// crypto gate is pinned separately by the pure-Rust
// `garbaged_yubikey_vault_does_not_open` test (no hardware needed there either).

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

  test('garbaging BOTH main and .bak makes unlock fail — never an empty vault',
      () async {
    // the maintainer's exact sequence: init passphrase vault -> create entry -> edit it ->
    // lock -> overwrite both files with garbage -> attempt unlock.
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: 'first-pass',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;

    // Edit it (mirrors create_entry_screen._buildUpdated: keep id/createdAt,
    // blank updatedAt for the bridge to stamp, change one field).
    final current = (getEntry(id: id) as VaultEntryData_Login).field0;
    await updateEntry(
      entry: VaultEntryData_Login(LoginEntryData(
        id: current.id,
        createdAt: current.createdAt,
        updatedAt: '',
        folder: current.folder,
        title: current.title,
        url: current.url,
        username: current.username,
        password: 'second-pass',
        notes: current.notes,
        customFields: current.customFields,
        previousPassword: current.previousPassword,
      )),
      expiryDays: null,
    );

    lockVault();

    // Path instrumentation: the file the app reads/writes IS vaultPath, and the
    // .bak sits beside it. On the device, confirm the file you garbage is THIS
    // path (registry path == on-disk file) — a mismatch there is the leading
    // suspect for the empty-vault report.
    final bakPath = '$vaultPath.bak';
    expect(File(vaultPath).existsSync(), isTrue,
        reason: 'the vault the app unlocks must be exactly this path');
    expect(File(bakPath).existsSync(), isTrue,
        reason: 'create + edit (>=2 saves) must have left a .bak beside it');

    // the maintainer's `printf rubbish` into both files.
    File(vaultPath).writeAsBytesSync(utf8.encode('rubbish'));
    File(bakPath).writeAsBytesSync(utf8.encode('rubbish too'));

    // The invariant the device appeared to violate: unlock must FAIL.
    await expectLater(
      unlockVault(passphrase: passphrase, path: vaultPath),
      throwsA(anything),
      reason: 'garbage bytes cannot decrypt — unlock must fail, not succeed empty',
    );

    // And no empty-but-valid session may be left behind: reads still fail.
    expect(() => getEntry(id: id), throwsA(anything),
        reason: 'a failed unlock must leave the vault locked, not open and empty');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('garbaging only the main file (with a good .bak) also fails unlock',
      () async {
    // The .bak being intact must not let a garbaged main file open — restore is
    // an explicit, separate user action, never an automatic fallback on unlock.
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: 'first-pass',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;
    // A second save guarantees a .bak holding a real, openable previous state.
    final current = (getEntry(id: id) as VaultEntryData_Login).field0;
    await updateEntry(
      entry: VaultEntryData_Login(LoginEntryData(
        id: current.id,
        createdAt: current.createdAt,
        updatedAt: '',
        folder: current.folder,
        title: current.title,
        url: current.url,
        username: current.username,
        password: 'second-pass',
        notes: current.notes,
        customFields: current.customFields,
        previousPassword: current.previousPassword,
      )),
      expiryDays: null,
    );
    lockVault();

    File(vaultPath).writeAsBytesSync(utf8.encode('rubbish'));

    await expectLater(
      unlockVault(passphrase: passphrase, path: vaultPath),
      throwsA(anything),
      reason: 'a good .bak must not auto-rescue a garbaged main file on unlock',
    );
    expect(() => getEntry(id: id), throwsA(anything),
        reason: 'unlock must remain failed until the user explicitly restores');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('P1 acceptance: restore after corrupt-main returns the LAST edit, '
      'not the save before it', () async {
    // Reproduces the 2026-06-11 hardware failure: edit an entry twice, garbage
    // the main file, restore from .bak. Pre-P1 the .bak trailed by one save, so
    // the restored vault was missing the second edit. With ".bak == last
    // verified save", the second edit must be present after restore + unlock.
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: 'first-pass',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;

    LoginEntryData edited(String newPassword) {
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

    // First edit, then a SECOND edit — the one the old rotation lost on restore.
    await updateEntry(entry: VaultEntryData_Login(edited('second-pass')), expiryDays: null);
    await updateEntry(entry: VaultEntryData_Login(edited('third-pass')), expiryDays: null);
    lockVault();

    // Garbage only the main file; the .bak holds the last verified save.
    File(vaultPath).writeAsBytesSync(utf8.encode('rubbish'));
    await expectLater(
        unlockVault(passphrase: passphrase, path: vaultPath), throwsA(anything),
        reason: 'precondition: the garbaged main file must not open');

    // Explicit restore, then unlock — the second edit must be there.
    await restoreVaultBackup(path: vaultPath);
    await unlockVault(passphrase: passphrase, path: vaultPath);
    final reopened = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(reopened.password, 'third-pass',
        reason: 'restore must return the LAST verified save, including the 2nd edit');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restore from an external backup file replaces a corrupt vault, which '
      'then unlocks with its entries', () async {
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final login = await createLoginEntry(
      folder: '',
      title: 'Example',
      url: 'https://example.com',
      username: 'alice',
      password: 'p4ss',
      notes: null,
      customFields: const [],
    );
    final id = (await createEntry(entry: VaultEntryData_Login(login))).id;
    lockVault();

    // The user's own off-device 3-2-1 backup of this vault.
    final backupPath = '${tmp.path}/my_backup.gabbro';
    File(backupPath).writeAsBytesSync(File(vaultPath).readAsBytesSync());

    // Both on-device files are garbaged (State B, unrecoverable on device).
    File(vaultPath).writeAsBytesSync(utf8.encode('rubbish'));
    File('$vaultPath.bak').writeAsBytesSync(utf8.encode('rubbish too'));
    await expectLater(
        unlockVault(passphrase: passphrase, path: vaultPath), throwsA(anything),
        reason: 'precondition: the corrupt vault must not open');

    // Restore from the picked backup file, then unlock — entries are back.
    await restoreVaultFromFile(path: vaultPath, source: backupPath);
    await unlockVault(passphrase: passphrase, path: vaultPath);
    final reopened = (getEntry(id: id) as VaultEntryData_Login).field0;
    expect(reopened.username, 'alice',
        reason: 'entries must be present after restoring from the backup file');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restore from a file that is not a vault is refused, leaving the corrupt '
      'vault untouched', () async {
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    lockVault();
    File(vaultPath).writeAsBytesSync(utf8.encode('rubbish'));
    final notAVault = '${tmp.path}/not_a_vault.gabbro';
    File(notAVault).writeAsBytesSync(utf8.encode('definitely not a gabbro vault'));

    await expectLater(
        restoreVaultFromFile(path: vaultPath, source: notAVault),
        throwsA(anything),
        reason: 'restoring from a non-vault file must be refused');
    expect(File(vaultPath).readAsStringSync(), 'rubbish',
        reason: 'a refused restore must leave the existing file untouched');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
