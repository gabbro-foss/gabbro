import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/widgets/path_field.dart';

void main() {
  group('PathField', () {
    testWidgets('displays hint text when no path selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
        MaterialApp(
          home: Scaffold(
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
        MaterialApp(
          home: Scaffold(
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
  });
}