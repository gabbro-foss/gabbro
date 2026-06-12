import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/widgets/path_field.dart';

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