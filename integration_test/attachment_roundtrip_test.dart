// Phase 1 - Linux desktop, no hardware.
//
// Run with:
//   cd rust && cargo build --release --lib && cd ..
//   dart test integration_test/ -j 1
//
// Scenario 10 (attachments task): the attachment bridge calls the widget tests
// mock past — addAttachment / extractAttachment / removeAttachment and the
// metadata in getEntry — through the real FFI -> crypto -> disk path.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    tmp = await Directory.systemTemp.createTemp('gabbro_it_att_');
    vaultPath = '${tmp.path}/test.gabbro';
  });

  tearDown(() async {
    lockVault();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('add -> lock -> unlock -> extract round-trips the exact bytes',
      () async {
    await initVault(passphrase: passphrase, path: vaultPath, alias: 'IT');
    final summary = await createEntry(
      entry: VaultEntryData.note(
        NoteEntryData(
          id: '',
          createdAt: '',
          updatedAt: '',
          folder: '',
          title: 'With attachment',
          content: 'c',
          customFields: const [],
          attachments: const [],
        ),
      ),
    );

    final bytes = Uint8List.fromList(
      List<int>.generate(4096, (i) => (i * 31 + 7) & 0xff),
    );
    final uuid = await addAttachment(
      entryId: summary.id,
      name: 'scan.png',
      kind: 'image/png',
      data: bytes,
    );

    lockVault();
    await unlockVault(passphrase: passphrase, path: vaultPath);

    final note = (getEntry(id: summary.id) as VaultEntryData_Note).field0;
    expect(note.attachments, hasLength(1));
    expect(note.attachments.single.uuid, uuid);
    expect(note.attachments.single.name, 'scan.png');
    expect(note.attachments.single.size.toInt(), bytes.length);

    final extracted = await extractAttachment(
      entryId: summary.id,
      uuid: uuid,
    );
    expect(extracted, bytes, reason: 'bytes intact through FFI + disk');

    await removeAttachment(entryId: summary.id, uuid: uuid);
    lockVault();
    await unlockVault(passphrase: passphrase, path: vaultPath);
    expect(
      (getEntry(id: summary.id) as VaultEntryData_Note).field0.attachments,
      isEmpty,
      reason: 'removal persisted to disk',
    );
  });
}
