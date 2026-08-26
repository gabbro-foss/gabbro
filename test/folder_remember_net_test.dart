// Net for step 3 (remember export/import folders, read-only view in Sync
// settings). Pins today's picker -> field -> action wiring on the export and
// import screens, the Android export folder memory, and the absence of folder
// rows in Sync settings, all green before any change.
//
// N6 (vault list opens the export screen with the remembered URI) has a single
// code path: one PopupMenuButton, one `_openExportScreen`; nothing to pin.
// N8 (today's strings in all 37 locales) is pinned by l10n_test's key-set check.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/linux_file_picker.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/sync_settings_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/text_scale.dart';

import 'test_helpers.dart';

/// Stands in for the portal: records what the screen asked for, answers with
/// a fixed path.
class _FakeLinuxPicker extends LinuxFilePicker {
  _FakeLinuxPicker({this.answer});
  final String? answer;
  String? savedName;
  List<String>? openFilter;
  List<String>? saveFilter;
  int opens = 0;
  int saves = 0;

  @override
  Future<String?> openFile({List<String>? allowedExtensions}) async {
    opens++;
    openFilter = allowedExtensions;
    return answer;
  }

  @override
  Future<String?> saveFile(
      {String? fileName, List<String>? allowedExtensions}) async {
    saves++;
    savedName = fileName;
    saveFilter = allowedExtensions;
    return answer;
  }
}

_FakeLinuxPicker _installLinuxPicker({String? answer}) {
  final fake = _FakeLinuxPicker(answer: answer);
  final wasLinux = GabbroFilePicker.isLinux;
  final wasPicker = GabbroFilePicker.linuxPicker;
  GabbroFilePicker.isLinux = () => true;
  GabbroFilePicker.linuxPicker = fake;
  addTearDown(() {
    GabbroFilePicker.isLinux = wasLinux;
    GabbroFilePicker.linuxPicker = wasPicker;
  });
  return fake;
}

Finder _browse() => find.byIcon(Icons.folder_open);

void main() {
  group('N1 export, Linux', () {
    testWidgets('the save picker gets the default name; its path lands in the '
        'field and is the path Export writes', (tester) async {
      final fake = _installLinuxPicker(answer: '/home/user/Sync/example.gabbro');
      String? exported;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        vaultAlias: 'example',
        onExport: (p) async => exported = p,
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(_browse());
      await tester.pumpAndSettle();
      expect(fake.saves, 1);
      expect(fake.savedName, 'example.gabbro');
      expect(fake.saveFilter, ['gabbro']);
      expect(find.text('/home/user/Sync/example.gabbro'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(exported, '/home/user/Sync/example.gabbro');
    });

    testWidgets('a cancelled save picker leaves the field empty and Export '
        'disarmed', (tester) async {
      _installLinuxPicker(answer: null);
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: false,
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(_browse());
      await tester.pumpAndSettle();
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Export'));
      expect(btn.onPressed, isNull);
    });
  });

  group('N2 export, Android .gabbro folder memory', () {
    const tree = 'content://docs/tree/primary%3ADownload%2FGabbroSync';

    testWidgets('a remembered folder arrives armed: no picker, Export writes '
        'into it', (tester) async {
      String? wroteTo;
      var picks = 0;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        initialExportFolderUri: tree,
        onHasGrant: (_) async => true,
        onPickExportDir: () async {
          picks++;
          return null;
        },
        onExport: (_) async {},
        onExportJson: (_) async {},
        onBuildExportBytes: (_) async => ExportArtifact(
            vaultBytes: Uint8List.fromList([1, 2, 3]), sha256Line: 'AA  x\n'),
        onWriteExport: (t, _, _, _, _) async => wroteTo = t,
      )));
      await tester.pumpAndSettle();
      expect(find.text('primary:Download/GabbroSync'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(picks, 0);
      expect(wroteTo, tree);
    });

    testWidgets('a revoked grant forgets the folder: label gone, Export '
        'disarmed', (tester) async {
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        initialExportFolderUri: tree,
        onHasGrant: (_) async => false,
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('primary:Download/GabbroSync'), findsNothing);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Export'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('a pick shows the folder name and saves the URI exactly once',
        (tester) async {
      final saved = <String>[];
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        onPickExportDir: () async =>
            (treeUri: tree, displayName: 'GabbroSync'),
        onSaveExportFolderUri: (u) async => saved.add(u),
        onExport: (_) async {},
        onExportJson: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(find.text('GabbroSync'), findsOneWidget);
      expect(saved, [tree]);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Export'));
      expect(btn.onPressed, isNotNull);
    });
  });

  group('N3 export, Android JSON', () {
    testWidgets('keeps its raw folder picker and never touches the remembered '
        '.gabbro folder', (tester) async {
      var saved = 0;
      var treePicks = 0;
      String? exported;
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        vaultAlias: 'example',
        initialExportFolderUri: 'content://docs/tree/primary%3AOld',
        onHasGrant: (_) async => true,
        onSaveExportFolderUri: (_) async => saved++,
        onPickExportDir: () async {
          treePicks++;
          return null;
        },
        onPickDirectory: () async => '/storage/emulated/0/Download',
        onExport: (_) async {},
        onExportJson: (p) async => exported = p,
      )));
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(exported, '/storage/emulated/0/Download/example.json');
      expect(saved, 0);
      expect(treePicks, 0);
    });
  });

  group('N4 import, browse', () {
    testWidgets('the open picker gets the type filter; its path lands in the '
        'one field', (tester) async {
      final fake = _installLinuxPicker(answer: '/home/user/Downloads/x.json');
      await tester.pumpWidget(testApp(ImportScreen(isAndroid: false)));
      await tester.pumpAndSettle();
      final dd = find.byType(DropdownButton<ImportType>);
      await tester.tap(dd);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enpass').last);
      await tester.pumpAndSettle();
      await tester.tap(_browse());
      await tester.pumpAndSettle();
      expect(fake.opens, 1);
      expect(fake.openFilter, ['json']);
      expect(find.text('/home/user/Downloads/x.json'), findsOneWidget);
    });

    testWidgets('a cancelled open picker leaves the field empty',
        (tester) async {
      _installLinuxPicker(answer: null);
      await tester.pumpWidget(testApp(ImportScreen(isAndroid: false)));
      await tester.pumpAndSettle();
      await tester.tap(_browse());
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller
              ?.text,
          isEmpty);
    });
  });

  group('N5 sync settings', () {
    testWidgets('shows no export or import folder today', (tester) async {
      await tester.pumpWidget(testApp(SyncSettingsScreen(
        settings: const AppSettings(syncFolder: '/home/user/Sync'),
        onUpdate: (_) {},
        onPickFolder: () async => null,
        isAndroid: false,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Export'), findsNothing);
      expect(find.textContaining('Import'), findsNothing);
      // The one folder on screen is the sync folder.
      expect(find.text('/home/user/Sync'), findsOneWidget);
    });
  });

  group('N7 export at large text', () {
    Future<Object?> overflowFor(
        WidgetTester tester, Locale locale, double scale, bool android) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExportScreen(
          isAndroid: android,
          isKeyProtected: true,
          initialExportFolderUri:
              android ? 'content://docs/tree/primary%3ADownload%2FGabbroSync' : '',
          onHasGrant: (_) async => true,
          onExport: (_) async {},
          onExportJson: (_) async {},
        ),
      ));
      await tester.pumpAndSettle();
      return tester.takeException();
    }

    void surface(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final android in [false, true]) {
      final tag = android ? 'Android' : 'Linux';
      testWidgets('$tag: no overflow in any locale at 2x on a 360dp phone',
          (tester) async {
        surface(tester, const Size(360, 800));
        final failed = <String>[];
        for (final locale in AppLocalizations.supportedLocales) {
          if (await overflowFor(tester, locale, kPhoneMaxScale, android) !=
              null) {
            failed.add(locale.toLanguageTag());
          }
        }
        expect(failed, isEmpty, reason: 'overflowing at 2x: $failed');
      });

      testWidgets('$tag: no overflow in any locale at 3x on a 600dp tablet',
          (tester) async {
        surface(tester, const Size(600, 960));
        final failed = <String>[];
        for (final locale in AppLocalizations.supportedLocales) {
          if (await overflowFor(tester, locale, kTabletMaxScale, android) !=
              null) {
            failed.add(locale.toLanguageTag());
          }
        }
        expect(failed, isEmpty, reason: 'overflowing at 3x: $failed');
      });
    }
  });
}
