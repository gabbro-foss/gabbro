import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Scenario 6 (attachments task): the create/edit screen must show an entry's
// attachments and let the user add and remove them — otherwise an imported
// attachment stays invisible and nothing can ever be attached in-app.

NoteEntryData _noteWith(List<AttachmentMetaData> attachments) => NoteEntryData(
  id: 'note-1',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  folder: 'Personal',
  title: 'A note',
  content: 'content',
  customFields: const [],
  attachments: attachments,
);

AttachmentMetaData _att({String name = 'passport.pdf'}) => AttachmentMetaData(
  uuid: 'att-1',
  name: name,
  kind: 'application/pdf',
  size: BigInt.from(2048),
);

Widget _editScreen(
  VaultEntryData existing, {
  Future<String> Function(String, String, String, List<int>)? onAddAttachment,
  Future<void> Function(String, String)? onRemoveAttachment,
  Future<PickedFile?> Function()? pickFile,
}) => testApp(
  CreateEntryScreen(
    entryType: 'Note',
    existing: existing,
    onCreateEntry: (_) async => 'unused',
    onGetEntry: (_) => existing,
    onAddAttachment: onAddAttachment ?? (a, b, c, d) async => 'new-uuid',
    onRemoveAttachment: onRemoveAttachment ?? (a, b) async {},
    pickFile: pickFile ?? () async => null,
  ),
);

void main() {
  testWidgets('an existing attachment is listed with name and remove control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _editScreen(VaultEntryData.note(_noteWith([_att()]))),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.textContaining('passport.pdf'));
    expect(find.text('Attachments'), findsOneWidget);
    expect(find.textContaining('passport.pdf'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.byTooltip('Remove attachment'), findsOneWidget);
    expect(find.text('Add attachment'), findsOneWidget);
  });

  testWidgets('an entry without attachments still offers the add button', (
    tester,
  ) async {
    await tester.pumpWidget(_editScreen(VaultEntryData.note(_noteWith([]))));
    await tester.pumpAndSettle();

    expect(find.text('Add attachment'), findsOneWidget);
  });

  testWidgets('adding in edit mode calls the bridge and lists the new row', (
    tester,
  ) async {
    final calls = <(String, String, int)>[];
    await tester.pumpWidget(
      _editScreen(
        VaultEntryData.note(_noteWith([])),
        pickFile: () async =>
            (name: 'scan.png', bytes: Uint8List.fromList([1, 2, 3])),
        onAddAttachment: (id, name, kind, bytes) async {
          calls.add((id, name, bytes.length));
          return 'uuid-new';
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add attachment'));
    await tester.tap(find.text('Add attachment'));
    await tester.pumpAndSettle();

    expect(calls, [('note-1', 'scan.png', 3)]);
    expect(find.textContaining('scan.png'), findsOneWidget);
  });

  testWidgets('removing in edit mode confirms first, then calls the bridge', (
    tester,
  ) async {
    final removed = <(String, String)>[];
    await tester.pumpWidget(
      _editScreen(
        VaultEntryData.note(_noteWith([_att()])),
        onRemoveAttachment: (id, uuid) async => removed.add((id, uuid)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Remove attachment'));
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();

    expect(find.text('Remove "passport.pdf"?'), findsOneWidget);
    expect(removed, isEmpty, reason: 'nothing removed before confirmation');

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(removed, [('note-1', 'att-1')]);
    expect(find.textContaining('passport.pdf'), findsNothing);
  });

  testWidgets('cancelling the confirm keeps the attachment', (tester) async {
    final removed = <(String, String)>[];
    await tester.pumpWidget(
      _editScreen(
        VaultEntryData.note(_noteWith([_att()])),
        onRemoveAttachment: (id, uuid) async => removed.add((id, uuid)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Remove attachment'));
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(removed, isEmpty);
    expect(find.textContaining('passport.pdf'), findsOneWidget);
  });

  testWidgets('an attachment picked while creating persists after create', (
    tester,
  ) async {
    final added = <(String, String)>[];
    await tester.pumpWidget(
      testApp(
        CreateEntryScreen(
          entryType: 'Note',
          onCreateEntry: (_) async => 'created-id',
          onGetEntry: (_) => VaultEntryData.note(_noteWith([])),
          pickFile: () async =>
              (name: 'notes.txt', bytes: Uint8List.fromList([9, 9])),
          onAddAttachment: (id, name, kind, bytes) async {
            added.add((id, name));
            return 'uuid-x';
          },
          onRemoveAttachment: (a, b) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Created with attachment',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'content');

    await tester.ensureVisible(find.text('Add attachment'));
    await tester.tap(find.text('Add attachment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(added, isEmpty, reason: 'staged until the entry exists');

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(added, [('created-id', 'notes.txt')]);
  });
}
