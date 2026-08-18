import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Scenario 7 (attachments task): the detail screen must list an entry's
// attachments and save one to disk on demand — without this an imported
// attachment is visible in name only and can never be recovered as a file.

NoteEntryData _noteWith(List<AttachmentMetaData> attachments) => NoteEntryData(
  id: 'note-1',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  folder: '',
  title: 'A note',
  content: 'content',
  customFields: const [],
  attachments: attachments,
);

AttachmentMetaData _att() => AttachmentMetaData(
  uuid: 'att-1',
  name: 'passport.pdf',
  kind: 'application/pdf',
  size: BigInt.from(2),
);

Widget _buildScreen(
  VaultEntryData entry, {
  Future<Uint8List> Function(String id, String uuid)? onExtractAttachment,
}) => testApp(
  EntryDetailScreen(
    entry: entry,
    isAndroid: false,
    onDeleteEntry: (_) async {},
    clipboardClearTimeout: ClipboardClearTimeout.sixtySeconds,
    onLaunchUrl: (_) async => UrlOpenResult.opened,
    exportFilePicker: (_) async => null,
    onFetchHistory: (_) async => const [],
    onExtractAttachment:
        onExtractAttachment ?? (a, b) async => Uint8List.fromList([0]),
  ),
);

void main() {
  testWidgets('attachments are listed with name, size and a save control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.note(_noteWith([_att()]))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachments'), findsOneWidget);
    expect(find.textContaining('passport.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('no attachments, no section', (tester) async {
    await tester.pumpWidget(_buildScreen(VaultEntryData.note(_noteWith([]))));
    await tester.pumpAndSettle();

    expect(find.text('Attachments'), findsNothing);
  });

  testWidgets('saving an attachment writes the extracted bytes', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('gabbro_att_extract');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final calls = <(String, String)>[];

    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.note(_noteWith([_att()])),
        onExtractAttachment: (id, uuid) async {
          calls.add((id, uuid));
          return Uint8List.fromList([104, 105]);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.download_outlined));
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    final dest = '${tmp.path}/passport.pdf';
    await tester.enterText(find.byType(TextField), dest);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export'),
    );
    await tester.runAsync(() async {
      confirm.onPressed!();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(calls, [('note-1', 'att-1')]);
    expect(File(dest).readAsBytesSync(), [104, 105]);
  });
}
