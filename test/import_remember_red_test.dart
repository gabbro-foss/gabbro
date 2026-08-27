// Red for step 3, import screen (R6-R8): a Remember box; a pick remembers the
// file's folder; the next dialog opens there; unticking forgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/linux_file_picker.dart';
import 'package:gabbro/screens/import_screen.dart';

import 'test_helpers.dart';

/// Records the start folder the dialog was asked to open in.
class _FakeLinuxPicker extends LinuxFilePicker {
  _FakeLinuxPicker(this.answer);
  final String? answer;
  String? openedIn;

  @override
  Future<String?> openFile(
      {List<String>? allowedExtensions, String? currentFolder}) async {
    openedIn = currentFolder;
    return answer;
  }
}

_FakeLinuxPicker _install(String? answer) {
  final fake = _FakeLinuxPicker(answer);
  final wasLinux = GabbroFilePicker.isLinux;
  final wasPicker = GabbroFilePicker.linuxPicker;
  final wasAndroid = GabbroFilePicker.androidPickPathWithFolder;
  GabbroFilePicker.isLinux = () => true;
  GabbroFilePicker.linuxPicker = fake;
  addTearDown(() {
    GabbroFilePicker.isLinux = wasLinux;
    GabbroFilePicker.linuxPicker = wasPicker;
    GabbroFilePicker.androidPickPathWithFolder = wasAndroid;
  });
  return fake;
}

Finder _remember() => find.widgetWithText(CheckboxListTile, 'Remember');
bool _ticked(WidgetTester t) =>
    t.widget<CheckboxListTile>(_remember()).value == true;

void main() {
  testWidgets('R6 the box is ticked by default and carries its note',
      (tester) async {
    await tester.pumpWidget(testApp(ImportScreen(isAndroid: false)));
    await tester.pumpAndSettle();
    expect(_ticked(tester), isTrue);
    expect(find.textContaining('Next time'), findsOneWidget);
  });

  testWidgets('R6 Linux: a pick remembers the file\'s folder once',
      (tester) async {
    _install('/home/user/Exports/x.json');
    final saved = <String>[];
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: false,
      onSaveImportFolder: (f) async => saved.add(f),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(saved, ['/home/user/Exports']);
    expect(find.text('/home/user/Exports/x.json'), findsOneWidget);
  });

  testWidgets('R6 Android: a pick remembers the location the picker reports',
      (tester) async {
    _install(null);
    GabbroFilePicker.isLinux = () => false;
    GabbroFilePicker.androidPickPathWithFolder =
        ({allowedExtensions, startFolder}) async => (
              path: '/cache/picker/1/x.json',
              folder: 'content://docs/document/primary%3ADownload%2Fx.json',
            );
    final saved = <String>[];
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: true,
      onSaveImportFolder: (f) async => saved.add(f),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(saved, ['content://docs/document/primary%3ADownload%2Fx.json']);
  });

  testWidgets('R6 typing a path remembers nothing', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: false,
      onSaveImportFolder: (f) async => saved.add(f),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '/tmp/x.gabbro');
    await tester.pump();
    expect(saved, isEmpty);
  });

  testWidgets('R7 Linux: the dialog opens in the remembered folder, on every '
      'type', (tester) async {
    final fake = _install(null);
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: false,
      initialImportFolder: '/home/user/Exports',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(fake.openedIn, '/home/user/Exports');

    await tester.tap(find.byType(DropdownButton<ImportType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enpass').last);
    await tester.pumpAndSettle();
    fake.openedIn = null;
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(fake.openedIn, '/home/user/Exports');
  });

  testWidgets('R7 Android: the picker is launched at the remembered location',
      (tester) async {
    _install(null);
    GabbroFilePicker.isLinux = () => false;
    String? launchedAt;
    GabbroFilePicker.androidPickPathWithFolder =
        ({allowedExtensions, startFolder}) async {
      launchedAt = startFolder;
      return null;
    };
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: true,
      initialImportFolder: 'content://docs/document/primary%3ADownload%2Fold.json',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(launchedAt, 'content://docs/document/primary%3ADownload%2Fold.json');
  });

  testWidgets('R8 unticking forgets: setting cleared, next dialog opens at the '
      'system default, a pick saves nothing', (tester) async {
    final fake = _install('/home/user/Elsewhere/y.json');
    final saved = <String>[];
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: false,
      initialImportFolder: '/home/user/Exports',
      onSaveImportFolder: (f) async => saved.add(f),
    )));
    await tester.pumpAndSettle();
    await tester.tap(_remember());
    await tester.pumpAndSettle();
    expect(_ticked(tester), isFalse);
    expect(saved, ['']);
    saved.clear();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(fake.openedIn, isNull);
    expect(saved, isEmpty);
    expect(find.text('/home/user/Elsewhere/y.json'), findsOneWidget);
  });

  testWidgets('R8 re-ticking with a file chosen remembers its folder',
      (tester) async {
    _install('/home/user/Elsewhere/y.json');
    final saved = <String>[];
    await tester.pumpWidget(testApp(ImportScreen(
      isAndroid: false,
      onSaveImportFolder: (f) async => saved.add(f),
    )));
    await tester.pumpAndSettle();
    await tester.tap(_remember());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    saved.clear();
    await tester.tap(_remember());
    await tester.pumpAndSettle();
    expect(saved, ['/home/user/Elsewhere']);
  });
}
