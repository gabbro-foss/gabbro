import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_catalog.dart';

// Sweeps the shared screen catalog: Tab reaches a control on every screen,
// Escape dismisses every dialog. Blind spot: reachable is not trap-free, and
// this reads the focus tree, not hardware.

// Screens with NO keyboard-focusable control, each skipped (not silently
// passing) with a reason. A screen here is display-only by design; remove the
// entry if it gains an interactive control.
const Map<String, String> _knownNoFocusable = <String, String>{
  'gabbro_logo': 'display-only logo, no interactive control',
  'password_breakdown_sheet': 'display-only character breakdown, nothing tappable',
  'alphabet_index_bar':
      'pointer/semantics-only jump shortcut (GestureDetector, not focusable); '
          'entries stay keyboard-reachable via the list. Belongs to the '
          'deferred arrows-in-lists sub-task.',
  'keyboard_shortcuts':
      'read-only reference; its only control is the AppBar back button, which '
          'exists when the screen is pushed in-app but not in this standalone '
          'catalog render (no route to pop).',
};

// Dialogs that do NOT dismiss on Escape, each skipped with a reason. Empty:
// every catalog dialog takes Escape. The two barrierDismissible:false review
// dialogs (sync_review, import_failures) wire Escape explicitly to a safe
// cancel - see keyboard_shortcuts_test.dart for the result assertions.
const Map<String, String> _knownEscNotHandled = <String, String>{};

const _maxTabs = 40;

/// Put the tester on the phone surface, pump [app] at natural text scale, settle.
Future<void> pumpScreen(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = phone.physical;
  tester.view.devicePixelRatio = phone.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Press Tab up to [_maxTabs] times; return the first real (non-scope) focusable
/// control focus lands on, or null if traversal never reaches one.
Future<FocusNode?> tabToControl(WidgetTester tester) async {
  for (var i = 0; i < _maxTabs; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f is! FocusScopeNode && f.canRequestFocus) return f;
  }
  return null;
}

/// Modal dialogs and bottom sheets both insert a [ModalBarrier]; its count is a
/// surface-agnostic "is a modal on top" signal.
int barrierCount() => find.byType(ModalBarrier).evaluate().length;

/// The dialog opener the overflow probe / a11y net use: a button that runs the
/// catalog's `show*` function against a context under the app's Navigator.
Widget dialogOpener(Future<void> Function(BuildContext) dialog) => Builder(
  builder: (ctx) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => dialog(ctx),
        child: const Text('open'),
      ),
    ),
  ),
);

/// Open a catalog dialog, press Escape, and report whether it closed.
Future<bool> openThenEscape(
  WidgetTester tester,
  Future<void> Function(BuildContext) dialog,
) async {
  await pumpScreen(tester, appShell(dialogOpener(dialog), textScale: 1.0));
  final before = barrierCount();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(
    barrierCount(),
    greaterThan(before),
    reason: 'the dialog never opened, so the Escape check proves nothing',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  return barrierCount() == before;
}

void main() {
  // A display-only screen must report NO reachable control, and a screen with a
  // button must report one - otherwise the sweep below proves nothing.
  testWidgets('traversal net finds no control on a display-only screen', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('nothing to focus'))),
      ),
    );
    expect(await tabToControl(tester), isNull);
  });

  testWidgets('traversal net reaches a control on a screen with a button', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () {}, child: const Text('go')),
          ),
        ),
      ),
    );
    expect(await tabToControl(tester), isNotNull);
  });

  // An Esc-dismissible dialog must report closed; a dialog that swallows Escape
  // must report still-open.
  testWidgets('escape guard sees a dismissible dialog close', (tester) async {
    final dismissed = await openThenEscape(
      tester,
      (ctx) => showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(content: Text('dismissible')),
      ),
    );
    expect(dismissed, isTrue);
  });

  testWidgets('escape guard sees an escape-swallowing dialog stay open', (
    tester,
  ) async {
    final dismissed = await openThenEscape(
      tester,
      (ctx) => showDialog<void>(
        context: ctx,
        // Swallow Escape at the focused node so it never reaches the route's
        // pop. autofocus puts primary focus INSIDE this Focus, so the override
        // actually applies (a child Shortcuts would sit below the route's focus
        // scope and never see the key).
        builder: (_) => Focus(
          autofocus: true,
          onKeyEvent: (_, event) =>
              event.logicalKey == LogicalKeyboardKey.escape
              ? KeyEventResult.handled
              : KeyEventResult.ignored,
          child: const AlertDialog(content: Text('sticky')),
        ),
      ),
    );
    expect(dismissed, isFalse);
  });

  testWidgets('Enter and Space activate a focused button', (tester) async {
    var count = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              focusNode: node,
              onPressed: () => count++,
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(count, 1, reason: 'Enter did not activate the focused button');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(count, 2, reason: 'Space did not activate the focused button');
  });

  for (final entry in screens.entries) {
    testWidgets(
      '${entry.key}: Tab reaches a focusable control',
      (tester) async {
        await pumpScreen(tester, appShell(entry.value(), textScale: 1.0));
        expect(
          await tabToControl(tester),
          isNotNull,
          reason: 'Tab never reached a focusable control on ${entry.key}',
        );
      },
      skip: _knownNoFocusable.containsKey(entry.key) ||
          tabletOnly.containsKey(entry.key),
    );
  }

  for (final entry in dialogs.entries) {
    testWidgets(
      '${entry.key}: Escape dismisses the dialog',
      (tester) async {
        expect(
          await openThenEscape(tester, entry.value),
          isTrue,
          reason: 'Escape did not dismiss ${entry.key}',
        );
      },
      skip: _knownEscNotHandled.containsKey(entry.key),
    );
  }
}
