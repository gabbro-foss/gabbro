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
