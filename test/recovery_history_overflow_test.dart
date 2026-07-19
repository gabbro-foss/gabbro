import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/screens/recovery_history_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';

// The recovery-history row put its Revert / Delete / eye controls in the
// ListTile `trailing` slot. `trailing` is intrinsically sized, so at larger
// text the controls ran off the right edge and could not be tapped: the user
// could no longer restore or discard a value sync had replaced. Visible in 24
// of 34 locales at 2.0x on a 360dp phone -- en, ja, ko, zh*, da, et, hr, sl and
// sr* have short enough words to fit, which is why it went unseen.

HistoryRecordData _rec(String field, String value) => HistoryRecordData(
  field: field,
  value: value,
  savedAt: '2026-01-01T00:00:00Z',
);

/// A 360dp-wide phone surface, restored after the test.
void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _screen(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: gabbroLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: RecoveryHistoryScreen(
    records: [_rec('password', 'hunter2'), _rec('url', 'old.example.com')],
    onRestore: (_) async {},
    onDelete: (_) async {},
  ),
);

/// Pumps the screen at [locale] and [scale] and returns the overflow error, if
/// any. Tears the previous tree down first: without that, an overflow from the
/// prior locale is still pending and gets blamed on this one -- which produced
/// a false report of `en` failing when it passes standalone.
Future<Object?> _overflowFor(
  WidgetTester tester,
  Locale locale,
  double scale,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'teardown must leave no pending exception',
  );

  tester.platformDispatcher.textScaleFactorTestValue = scale;
  await tester.pumpWidget(_screen(locale));
  await tester.pumpAndSettle();
  // Any exception counts. Narrowing this to FlutterError would silently drop
  // whatever else layout throws and report a false green.
  return tester.takeException();
}

void main() {
  testWidgets('no overflow in English at normal text on a 360dp phone', (
    tester,
  ) async {
    _phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _overflowFor(tester, const Locale('en'), 1.0), isNull);
  });

  testWidgets('no overflow in any locale at 2.0x on a 360dp phone', (
    tester,
  ) async {
    _phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final failed = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final err = await _overflowFor(tester, locale, 2.0);
      if (err != null) failed.add(locale.toLanguageTag());
    }
    expect(failed, isEmpty, reason: 'locales overflowing at 2.0x: $failed');
  });

  testWidgets('Revert and Delete stay hittable at 2.0x on a 360dp phone', (
    tester,
  ) async {
    _phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    var restored = false;
    var deleted = false;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Two rows: Revert removes the row it acted on, so Delete needs its own.
        home: RecoveryHistoryScreen(
          records: [_rec('url', 'old.example.com'), _rec('content', 'note')],
          onRestore: (_) async => restored = true,
          onDelete: (_) async => deleted = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // warnIfMissed: a control pushed off the edge reports a hit outside its own
    // bounds -- the tap "succeeds" while a real finger would miss it.
    await tester.tap(find.text('Revert').first, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(restored, isTrue, reason: 'Revert must be reachable at 2.0x');

    await tester.tap(find.byIcon(Icons.delete_outline).first, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(deleted, isTrue, reason: 'Delete must be reachable at 2.0x');
  });
}
