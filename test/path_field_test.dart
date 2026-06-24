import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/widgets/path_field.dart';

// The English copy shown when the native dialog can't be reached (e.g. the XDG
// portal / DBus session bus is missing under a bubblewrap sandbox).
const _pickerUnavailableText =
    'File dialog unavailable here. Type or paste the path instead.';

void main() {
  group('PathField', () {
    testWidgets('displays hint text when no path selected', (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
              mode: PathFieldMode.open,
              hint: 'Select a file',
              onPathSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Select a file'), findsOneWidget);
    });

    testWidgets('displays selected path', (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
              mode: PathFieldMode.open,
              hint: 'Select a file',
              initialPath: '/home/user/export.gabbro',
              onPathSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('/home/user/export.gabbro'), findsOneWidget);
    });

    testWidgets('shows folder icon button', (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
              mode: PathFieldMode.open,
              hint: 'Select a file',
              onPathSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    // A11y: the browse (folder) button must carry a semantic label so screen
    // readers announce it, not a bare "button".
    testWidgets('browse button meets labelled-tap-target guideline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.open,
            hint: 'Select a file',
            onPathSelected: (_) {},
          ),
        )),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // The user must be able to type or paste a path directly, not only pick it
    // via the native dialog - the dialog can be unavailable under a Wayland
    // bubblewrap sandbox, and typing is the escape hatch.
    testWidgets('typing a path propagates it via onPathSelected',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.save,
            hint: 'Path',
            onPathSelected: (p) => captured = p,
          ),
        )),
      );
      await tester.enterText(
          find.byType(TextFormField), '/home/user/myvault.gabbro');
      await tester.pump();
      expect(captured, '/home/user/myvault.gabbro');
    });

    // Onboarding drives the path from the alias field (type "Work" -> the path
    // preview becomes work_gabbro.gabbro). That arrives as an external
    // initialPath change and must be reflected without recreating the widget.
    testWidgets('reflects an external initialPath change (alias-driven preview)',
        (tester) async {
      String path = '/data/gabbro.gabbro';
      await tester.pumpWidget(
        testApp(StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Column(children: [
                PathField(
                  mode: PathFieldMode.save,
                  hint: 'Path',
                  initialPath: path,
                  onPathSelected: (_) {},
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => path = '/data/work_gabbro.gabbro'),
                  child: const Text('rename'),
                ),
              ]),
            );
          },
        )),
      );
      expect(find.text('/data/gabbro.gabbro'), findsOneWidget);
      await tester.tap(find.text('rename'));
      await tester.pump();
      expect(find.text('/data/work_gabbro.gabbro'), findsOneWidget);
      expect(find.text('/data/gabbro.gabbro'), findsNothing);
    });

    // The folder-icon picker must not crash the app when the native dialog is
    // unreachable (sandbox with no DBus portal). It shows a SnackBar pointing the
    // user at the editable field instead.
    testWidgets('save mode: a throwing picker shows a SnackBar, never rethrows',
        (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.save,
            hint: 'Path',
            onPathSelected: (_) {},
            savePicker: () async => throw const SocketException('no bus'),
          ),
        )),
      );
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();
      expect(find.text(_pickerUnavailableText), findsOneWidget);
    });

    testWidgets('open mode: a throwing picker shows a SnackBar, never rethrows',
        (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.open,
            hint: 'Path',
            onPathSelected: (_) {},
            openPicker: () async => throw const SocketException('no bus'),
          ),
        )),
      );
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();
      expect(find.text(_pickerUnavailableText), findsOneWidget);
    });

    testWidgets('a throwing picker leaves the field text and callback untouched',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.open,
            hint: 'Path',
            initialPath: '/existing.gabbro',
            onPathSelected: (p) => captured = p,
            openPicker: () async => throw const SocketException('no bus'),
          ),
        )),
      );
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();
      expect(captured, isNull, reason: 'no bogus path on picker failure');
      expect(find.text('/existing.gabbro'), findsOneWidget);
    });

    testWidgets('a picker that returns a path still propagates and updates field',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.save,
            hint: 'Path',
            onPathSelected: (p) => captured = p,
            savePicker: () async => '/picked/out.gabbro',
          ),
        )),
      );
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();
      expect(captured, '/picked/out.gabbro');
      expect(find.text('/picked/out.gabbro'), findsOneWidget);
      expect(find.text(_pickerUnavailableText), findsNothing);
    });

    testWidgets('a cancelled picker (null) shows no SnackBar and no callback',
        (tester) async {
      String? captured;
      var called = false;
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.save,
            hint: 'Path',
            onPathSelected: (p) {
              called = true;
              captured = p;
            },
            savePicker: () async => null,
          ),
        )),
      );
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();
      expect(called, isFalse);
      expect(captured, isNull);
      expect(find.text(_pickerUnavailableText), findsNothing);
    });

    testWidgets('readOnly: true stays a non-editable display with no picker',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        testApp(Scaffold(
          body: PathField(
            mode: PathFieldMode.open,
            hint: 'Path',
            readOnly: true,
            initialPath: '/home/user/locked.gabbro',
            onPathSelected: (p) => captured = p,
          ),
        )),
      );
      expect(find.byIcon(Icons.folder_open), findsNothing);
      await tester.enterText(find.byType(TextFormField), '/typed.gabbro');
      await tester.pump();
      expect(captured, isNull,
          reason: 'a read-only display field must not accept typed input');
    });
  });
}