import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'screen_catalog.dart';

// Phase 1 (canon-TDD, red first): global Esc + physical-key shortcuts. Sits on
// top of the green net in esc_baseline_test.dart.

bool searchFocused(WidgetTester t) => t
    .widgetList<EditableText>(find.byType(EditableText))
    .any((w) => w.focusNode.hasFocus);

Future<void> ctrlF(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyF);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

void setPhone(WidgetTester t) {
  t.view.physicalSize = phone.physical;
  t.view.devicePixelRatio = phone.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  // Physical-key matching: a hand-built event avoids the flutter_test key
  // simulator (which hangs when physical/logical are deliberately mismatched).
  testWidgets('Ctrl shortcuts match the physical key, so non-Latin layouts work',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));

    // Physical L position, but the layout emits a Cyrillic letter.
    const ev = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyL,
      logicalKey: LogicalKeyboardKey(0x430),
      timeStamp: Duration.zero,
    );
    expect(ev.logicalKey == LogicalKeyboardKey.keyL, isFalse,
        reason: 'sanity: a logical match would miss this non-Latin event');
    expect(isCtrlShortcut(ev, PhysicalKeyboardKey.keyL), isTrue,
        reason: 'Ctrl + physical-L must match regardless of the emitted letter');
  });

  testWidgets('Esc blurs the focused search field', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
    await tester.pump(const Duration(milliseconds: 300));

    await ctrlF(tester);
    expect(searchFocused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(searchFocused(tester), isFalse, reason: 'Esc must blur the search field');
  });

  testWidgets('Esc closes the sync-setup dialog (barrierDismissible:false)',
      (tester) async {
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<SyncCredentials>(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => SyncPassphraseDialog(
                  filePath: '/tmp/incoming.gabbro',
                  sourceRecords: const <YubikeyRecordData>[],
                  onGetYubikeyHmac: (records, pin, transport) async =>
                      throw UnimplementedError(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SyncPassphraseDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SyncPassphraseDialog), findsNothing,
        reason: 'Esc must close the sync-setup dialog');
  });

  testWidgets('Esc blurs a focused field on a sub-screen, 2nd Esc goes back',
      (tester) async {
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('EDIT')),
                    body: const TextField(autofocus: true),
                  ),
                ),
              ),
              child: const Text('push'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(searchFocused(tester), isTrue, reason: 'the sub-screen field autofocuses');

    // 1st Esc blurs the field but stays on the screen (D4: unfocus first).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(searchFocused(tester), isFalse, reason: '1st Esc blurs the field');
    expect(find.text('EDIT'), findsOneWidget, reason: 'still on the sub-screen');

    // 2nd Esc goes back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('EDIT'), findsNothing, reason: '2nd Esc pops the screen');
  });

  testWidgets('Esc closes a dialog even when its text field is focused',
      (tester) async {
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => const AlertDialog(
                  content: TextField(autofocus: true),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(searchFocused(tester), isTrue, reason: 'the dialog field autofocuses');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'Esc closes the dialog, not merely blur the field inside it');
  });

  // NET (green before the region-Esc change, must stay green): Esc still GOES
  // BACK from a pushed screen when a non-text control holds focus. The region
  // cycle needs Esc to drop focus out of a region instead of popping — that
  // must not leak onto other screens, where a focused button means "pop", not
  // "blur".
  testWidgets('Esc pops a pushed sub-screen when a non-text control is focused',
      (tester) async {
    final buttonFocus = FocusNode();
    addTearDown(buttonFocus.dispose);
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('SECOND')),
                    body: Center(
                      child: ElevatedButton(
                        focusNode: buttonFocus,
                        autofocus: true,
                        onPressed: () {},
                        child: const Text('a button'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('push'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(buttonFocus.hasFocus, isTrue, reason: 'the sub-screen button autofocuses');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('SECOND'), findsNothing,
        reason: 'a focused non-text control must not turn Esc into a blur');
  });

  // NET: the same guard for a dialog — Esc closes it whole, even when a button
  // inside it holds focus.
  testWidgets('Esc closes a dialog when a non-text control inside it is focused',
      (tester) async {
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => AlertDialog(
                  content: const Text('body'),
                  actions: [
                    ElevatedButton(
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'Esc closes the dialog, not merely blur the button inside it');
  });

  testWidgets('Esc pops a pushed sub-screen when nothing is focused',
      (tester) async {
    await tester.pumpWidget(appShell(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  // A realistic sub-screen: AppBar with a back arrow (focusable),
                  // so primaryFocus isn't null and Esc has a path to bubble.
                  builder: (_) => Scaffold(appBar: AppBar(title: const Text('SECOND'))),
                ),
              ),
              child: const Text('push'),
            ),
          ),
        ),
      ),
      textScale: 1.0,
    ));
    await tester.pump();
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('SECOND'), findsNothing,
        reason: 'Esc must pop the pushed screen (back)');
    expect(find.text('push'), findsOneWidget);
  });
}
