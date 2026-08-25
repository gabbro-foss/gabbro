import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/passkey_hint_banner.dart';
import 'test_helpers.dart';

// Edge-to-edge (2026-08-25): with a system bar inset, the vault list's
// snackbar, FAB and last row must stay out of the bar's band, and the Linux
// passkey banner must still show above it. The Scaffold strips the inset from
// body and snackbar whenever bottomNavigationBar != null (scaffold.dart), so
// the slot must be empty when the banner is hidden.

const _w = 360.0;
const _h = 800.0;
const _inset = 48.0;
final _band = Rect.fromLTWH(0, _h - _inset, _w, _inset);

List<EntrySummaryData> _entries() => [
  for (var i = 0; i < 40; i++)
    EntrySummaryData(
      id: 'e$i',
      entryType: 'Login',
      title: 'Entry $i',
      folder: '',
      searchBlob: 'entry $i',
    ),
];

Future<void> _pump(WidgetTester tester, {bool isAndroid = true}) async {
  tester.view.physicalSize = const Size(_w, _h);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(bottom: _inset);
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(
    testApp(
      VaultListScreen(
        vaultPath: '/tmp/example_gabbro.gabbro',
        listEntries: _entries,
        yubikeyRecords: const [],
        isAndroid: isAndroid,
        passkeyHintDismissed: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _rectOf(WidgetTester tester, Finder f) => tester.getRect(f.first);

void main() {
  setUp(() => passkeyProviderFailure.value = null);
  tearDown(() => passkeyProviderFailure.value = null);

  testWidgets('a snackbar sits above the bar', (tester) async {
    await _pump(tester);
    final ctx = tester.element(find.byType(VaultListScreen));
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('hi')));
    await tester.pumpAndSettle();

    // The snackbar paints down to the edge on purpose; its text must not.
    final r = _rectOf(
      tester,
      find.descendant(of: find.byType(SnackBar), matching: find.text('hi')),
    );
    expect(r.overlaps(_band), isFalse, reason: 'snackbar bottom ${r.bottom}');
  });

  testWidgets('the FAB sits above the bar', (tester) async {
    await _pump(tester);
    final r = _rectOf(tester, find.byType(FloatingActionButton));
    expect(r.overlaps(_band), isFalse, reason: 'fab bottom ${r.bottom}');
  });

  testWidgets('the last entry row ends above the bar', (tester) async {
    await _pump(tester);
    // The entry list is the vertical scrollable (chip rows scroll sideways).
    for (final e in find.byType(Scrollable).evaluate()) {
      final s = (e as StatefulElement).state as ScrollableState;
      if (s.position.axis == Axis.vertical) {
        s.position.jumpTo(s.position.maxScrollExtent);
      }
    }
    await tester.pumpAndSettle();

    final r = _rectOf(tester, find.text('Entry 39'));
    expect(r.overlaps(_band), isFalse, reason: 'last row bottom ${r.bottom}');
  });

  testWidgets('Linux: the passkey banner shows above the bar', (tester) async {
    passkeyProviderFailure.value = PasskeyFailureReason.moduleMissing;
    await _pump(tester, isAndroid: false);

    expect(find.byType(PasskeyHintBanner), findsOneWidget);
    // The banner paints down to the screen edge on purpose; its content
    // (text and buttons) is what must stay above the bar.
    final r = _rectOf(
      tester,
      find.descendant(
        of: find.byType(PasskeyHintBanner),
        matching: find.byType(Text),
      ),
    );
    expect(r.overlaps(_band), isFalse, reason: 'banner text bottom ${r.bottom}');
  });

  testWidgets('Linux: the banner appears when the failure arrives later', (
    tester,
  ) async {
    // The slot is empty until a failure is reported; the screen must rebuild
    // on the notifier, or the banner never shows.
    await _pump(tester, isAndroid: false);
    expect(find.byType(PasskeyHintBanner), findsNothing);
    passkeyProviderFailure.value = PasskeyFailureReason.moduleMissing;
    await tester.pumpAndSettle();
    expect(find.byType(PasskeyHintBanner), findsOneWidget);
  });
}
