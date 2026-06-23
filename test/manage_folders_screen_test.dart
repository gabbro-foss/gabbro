import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/manage_folders_screen.dart';

Widget _buildScreen({
  List<String> folders = const ['Work', 'Private', 'Other'],
  Future<List<String>> Function()? listFolders,
  Future<void> Function(String)? createFolder,
  Future<void> Function(String, String)? renameFolder,
  Future<void> Function(String, String?)? deleteFolder,
}) {
  return testApp(ManageFoldersScreen(
    listFolders: listFolders ?? () async => folders,
    createFolder: createFolder ?? (_) async {},
    renameFolder: renameFolder ?? (a, b) async {},
    deleteFolder: deleteFolder ?? (a, b) async {},
  ));
}

void main() {
  group('ManageFoldersScreen', () {
    testWidgets('renders app bar title', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      expect(find.text('Manage folders'), findsOneWidget);
    });

    testWidgets('renders all folders from listFolders', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('each folder row has edit and delete icon buttons', (tester) async {
      await tester.pumpWidget(_buildScreen(folders: ['Work']));
      await tester.pump();
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('tapping edit opens rename dialog with pre-filled name', (tester) async {
      await tester.pumpWidget(_buildScreen(folders: ['Work']));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Rename folder'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Work'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('rename dialog cancel closes without calling renameFolder', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        renameFolder: (a, b) async { called = true; },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      expect(find.text('Rename folder'), findsNothing);
    });

    testWidgets('tapping delete on empty folder shows confirmation dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(folders: ['Work']));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete folder'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('delete confirmation cancel closes without calling deleteFolder', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        deleteFolder: (a, b) async { called = true; },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      expect(find.text('Delete folder'), findsNothing);
    });

    testWidgets('delete confirmation delete calls deleteFolder with null reassign', (tester) async {
      String? deletedFolder;
      String? reassignTo;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        deleteFolder: (a, b) async {
          deletedFolder = a;
          reassignTo = b;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deletedFolder, 'Work');
      expect(reassignTo, isNull);
    });

    testWidgets('delete dialog shows reassign option when other folders exist', (tester) async {
      await tester.pumpWidget(_buildScreen(folders: ['Work', 'Private']));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Delete folder'), findsOneWidget);
      expect(find.text('Reassign entries to'), findsOneWidget);
      expect(find.text('Clear to "None"'), findsOneWidget);
    });

    testWidgets('delete with reassign calls deleteFolder with target folder', (tester) async {
      String? deletedFolder;
      String? reassignTo;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work', 'Private'],
        deleteFolder: (a, b) async {
          deletedFolder = a;
          reassignTo = b;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reassign entries to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deletedFolder, 'Work');
      expect(reassignTo, 'Private');
    });

    testWidgets('delete with clear calls deleteFolder with null', (tester) async {
      String? deletedFolder;
      String? reassignTo = 'sentinel';
      await tester.pumpWidget(_buildScreen(
        folders: ['Work', 'Private'],
        deleteFolder: (a, b) async {
          deletedFolder = a;
          reassignTo = b;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear to "None"'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deletedFolder, 'Work');
      expect(reassignTo, isNull);
    });

    testWidgets('shows add folder button', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping add opens dialog with empty input', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Add folder'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('add folder save calls createFolder with entered name', (tester) async {
      String? created;
      await tester.pumpWidget(_buildScreen(
        createFolder: (name) async { created = name; },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Finance');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(created, 'Finance');
    });

    testWidgets('add folder cancel does not call createFolder', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        createFolder: (name) async { called = true; },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('rename dialog save calls renameFolder with new name', (tester) async {
      String? renamedFrom;
      String? renamedTo;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        renameFolder: (a, b) async {
          renamedFrom = a;
          renamedTo = b;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Career');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(renamedFrom, 'Work');
      expect(renamedTo, 'Career');
    });

    // ── Net (pin currently-untested guards; green against current code) ──────────
    testWidgets('N1: rename with empty/whitespace name does not call renameFolder',
        (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        renameFolder: (a, b) async {
          called = true;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('N2: add with empty/whitespace name does not call createFolder',
        (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        createFolder: (_) async {
          called = true;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    // ── New behaviour (red against current code) ─────────────────────────────────
    testWidgets('R1: a failing rename shows a SnackBar and is handled (no throw)',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        folders: ['Work', 'Private'],
        renameFolder: (a, b) async =>
            throw Exception('Folder already exists: Private'),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Private');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('R2: a failing add shows a SnackBar and is handled (no throw)',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        createFolder: (_) async => throw Exception('Folder already exists: Work'),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('R3: renaming to the unchanged name does not call renameFolder',
        (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        renameFolder: (a, b) async {
          called = true;
        },
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      // Save without editing the pre-filled current name.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('R4: a failing delete shows a SnackBar and is handled (no throw)',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        folders: ['Work'],
        deleteFolder: (a, b) async => throw Exception('boom'),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}