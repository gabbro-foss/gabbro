import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/autotype_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/autotype_picker.dart';

import 'test_helpers.dart';

EntrySummaryData _login(String id, String title, String blob) => EntrySummaryData(
      id: id,
      entryType: 'Login',
      title: title,
      folder: '',
      searchBlob: blob,
    );

final _logins = [
  _login('a', 'Alpha Bank', 'alpha bank alpha.example.com'),
  _login('b', 'Beta Mail', 'beta mail beta.example.com'),
  _login('c', 'Gamma Shop', 'gamma shop gamma.example.com'),
];

// Captures the last onSelect call.
class _Captured {
  String? id;
  AutotypeSequenceKind? kind;
  int cancels = 0;
}

Future<_Captured> _pump(WidgetTester tester,
    {List<EntrySummaryData>? logins}) async {
  final cap = _Captured();
  await tester.pumpWidget(testApp(AutotypePicker(
    logins: logins ?? _logins,
    onSelect: (id, kind) {
      cap.id = id;
      cap.kind = kind;
    },
    onCancel: () => cap.cancels++,
  )));
  await tester.pumpAndSettle();
  return cap;
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

// Fire the search field's onSubmitted (Enter).
Future<void> _enter(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  group('AutotypePicker - functional', () {
    testWidgets('renders a row per login, in order', (tester) async {
      await _pump(tester);
      final a = tester.getTopLeft(find.text('Alpha Bank')).dy;
      final b = tester.getTopLeft(find.text('Beta Mail')).dy;
      final c = tester.getTopLeft(find.text('Gamma Shop')).dy;
      expect(a < b && b < c, isTrue);
    });

    testWidgets('typing filters the list by searchBlob', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'beta');
      await tester.pumpAndSettle();
      expect(find.text('Beta Mail'), findsOneWidget);
      expect(find.text('Alpha Bank'), findsNothing);
      expect(find.text('Gamma Shop'), findsNothing);
    });

    testWidgets('tapping a row selects it with full', (tester) async {
      final cap = await _pump(tester);
      await tester.tap(find.text('Beta Mail'));
      await tester.pumpAndSettle();
      expect(cap.id, 'b');
      expect(cap.kind, AutotypeSequenceKind.full);
    });

    testWidgets('username-only button selects usernameOnly', (tester) async {
      final cap = await _pump(tester);
      await tester.tap(find.byIcon(Icons.person_outline).first);
      await tester.pumpAndSettle();
      expect(cap.id, 'a');
      expect(cap.kind, AutotypeSequenceKind.usernameOnly);
    });

    testWidgets('password-only button selects passwordOnly', (tester) async {
      final cap = await _pump(tester);
      await tester.tap(find.byIcon(Icons.password).first);
      await tester.pumpAndSettle();
      expect(cap.id, 'a');
      expect(cap.kind, AutotypeSequenceKind.passwordOnly);
    });

    testWidgets('no matches shows the empty state and selects nothing',
        (tester) async {
      final cap = await _pump(tester);
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('autotype-empty')), findsOneWidget);
      await _enter(tester);
      expect(cap.id, isNull);
    });
  });

  group('AutotypePicker - keyboard', () {
    testWidgets('Enter selects the first row with full by default',
        (tester) async {
      final cap = await _pump(tester);
      await _enter(tester);
      expect(cap.id, 'a');
      expect(cap.kind, AutotypeSequenceKind.full);
    });

    testWidgets('ArrowDown then Enter selects the second row', (tester) async {
      final cap = await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await _enter(tester);
      expect(cap.id, 'b');
    });

    testWidgets('Ctrl+J then Enter selects the second row', (tester) async {
      final cap = await _pump(tester);
      await _ctrl(tester, LogicalKeyboardKey.keyJ);
      await _enter(tester);
      expect(cap.id, 'b');
    });

    testWidgets('ArrowUp / Ctrl+K move the highlight up', (tester) async {
      final cap = await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // -> row c
      await _ctrl(tester, LogicalKeyboardKey.keyK); // -> row b
      await _enter(tester);
      expect(cap.id, 'b');
    });

    testWidgets('Ctrl+U / Ctrl+P emit the variants for the highlighted row',
        (tester) async {
      var cap = await _pump(tester);
      await _ctrl(tester, LogicalKeyboardKey.keyU);
      expect(cap.id, 'a');
      expect(cap.kind, AutotypeSequenceKind.usernameOnly);

      cap = await _pump(tester);
      await _ctrl(tester, LogicalKeyboardKey.keyP);
      expect(cap.kind, AutotypeSequenceKind.passwordOnly);
    });

    testWidgets('Esc cancels', (tester) async {
      final cap = await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cap.cancels, 1);
    });
  });

  group('AutotypePicker - accessibility', () {
    testWidgets('has the keyboard-hint footer', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('autotype-hint-footer')), findsOneWidget);
    });

    testWidgets('action buttons carry tooltips', (tester) async {
      await _pump(tester);
      final user = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.person_outline).first,
        matching: find.byType(IconButton),
      ));
      final pass = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.password).first,
        matching: find.byType(IconButton),
      ));
      expect(user.tooltip, isNotNull);
      expect(pass.tooltip, isNotNull);
    });

    testWidgets('action icons scale up at large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester);
      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.person_outline).first,
        matching: find.byType(IconButton),
      ));
      expect(button.iconSize, isNotNull);
      expect(button.iconSize, greaterThan(24));
    });
  });
}
