// Red for step 3, export screen (R2-R4): a Remember box on both platforms,
// a remembered Linux folder pre-filling the path, a pick saving the folder.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

Finder _remember() => find.widgetWithText(CheckboxListTile, 'Remember');
bool _ticked(WidgetTester t) =>
    t.widget<CheckboxListTile>(_remember()).value == true;
FilledButton _exportBtn(WidgetTester t) =>
    t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'));

void main() {
  group('R2 the Remember box', () {
    testWidgets('Linux: ticked by default; a remembered folder pre-fills '
        '<folder>/<name> and arms Export', (tester) async {
      String? exported;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        initialExportFolder: '/home/user/GabbroSync',
        onExport: (p) async => exported = p,
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(_ticked(tester), isTrue);
      expect(find.text('/home/user/GabbroSync/example.gabbro'), findsOneWidget);
      expect(_exportBtn(tester).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(exported, '/home/user/GabbroSync/example.gabbro');
    });

    testWidgets('Linux: the pre-filled name follows the date toggle and the '
        'format', (tester) async {
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        initialExportFolder: '/home/user/GabbroSync',
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      expect(find.text('/home/user/GabbroSync/example.json'), findsOneWidget);
    });

    testWidgets('Linux: nothing remembered: ticked, field empty, Export '
        'disarmed', (tester) async {
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(_ticked(tester), isTrue);
      expect(_exportBtn(tester).onPressed, isNull);
    });

    testWidgets('Android: the box is there, ticked, next to the folder',
        (tester) async {
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        initialExportFolder: 'content://docs/tree/primary%3ADownload%2FGabbroSync',
        onHasGrant: (_) async => true,
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(_ticked(tester), isTrue);
      expect(find.text('primary:Download/GabbroSync'), findsOneWidget);
    });

    testWidgets('the box carries a note saying what it does', (tester) async {
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Next time'), findsOneWidget);
    });
  });

  group('R3 a pick saves the folder once', () {
    testWidgets('Linux: the saved path\'s folder is remembered', (tester) async {
      final saved = <String>[];
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        onSaveExportFolder: (f) async => saved.add(f),
        onExport: (_) async {},
        onExportJson: (_) async {},
        savePicker: () async => '/home/user/Other/example.gabbro',
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(saved, ['/home/user/Other']);
    });

    testWidgets('Linux: with Remember unticked a pick saves nothing',
        (tester) async {
      final saved = <String>[];
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        onSaveExportFolder: (f) async => saved.add(f),
        onExport: (_) async {},
        onExportJson: (_) async {},
        savePicker: () async => '/home/user/Other/example.gabbro',
      )));
      await tester.pumpAndSettle();
      await tester.tap(_remember());
      await tester.pumpAndSettle();
      expect(saved, [''], reason: 'unticking forgets (R4)');
      saved.clear();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('/home/user/Other/example.gabbro'), findsOneWidget);
    });

    testWidgets('Android: a pick saves the tree URI once; unticked saves '
        'nothing', (tester) async {
      const tree = 'content://docs/tree/primary%3ADownload%2FGabbroSync';
      final saved = <String>[];
      Widget screen() => testApp(ExportScreen(
            isAndroid: true,
            onPickExportDir: () async => (treeUri: tree, displayName: 'GabbroSync'),
            onSaveExportFolder: (f) async => saved.add(f),
            onExport: (_) async {},
            onExportJson: (_) async {},
          ));
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(saved, [tree]);

      saved.clear();
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(_remember());
      await tester.pumpAndSettle();
      expect(saved, [''], reason: 'unticking forgets (R4)');
      saved.clear();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('GabbroSync'), findsOneWidget, reason: 'still usable');
    });
  });

  group('R4 unticking forgets', () {
    testWidgets('Linux: the folder is cleared; the current path still exports',
        (tester) async {
      final saved = <String>[];
      String? exported;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        initialExportFolder: '/home/user/GabbroSync',
        onSaveExportFolder: (f) async => saved.add(f),
        onExport: (p) async => exported = p,
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(_remember());
      await tester.pumpAndSettle();
      expect(_ticked(tester), isFalse);
      expect(saved, ['']);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(exported, '/home/user/GabbroSync/example.gabbro');
    });

    testWidgets('Android: the folder is cleared but stays usable this time',
        (tester) async {
      const tree = 'content://docs/tree/primary%3ADownload%2FGabbroSync';
      final saved = <String>[];
      String? wroteTo;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        initialExportFolder: tree,
        onHasGrant: (_) async => true,
        onSaveExportFolder: (f) async => saved.add(f),
        onBuildExportBytes: (_) async => ExportArtifact(
            vaultBytes: Uint8List.fromList([1]), sha256Line: 'AA  x\n'),
        onWriteExport: (t, _, _, _, _) async => wroteTo = t,
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(_remember());
      await tester.pumpAndSettle();
      expect(saved, ['']);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(wroteTo, tree);
    });
  });
}
