import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/sync_method_dialog.dart';

// The sync-method chooser is the last thing between a user and a merge they
// cannot undo, so every choice - including backing out - has to stay reachable
// in the worst case the app supports: longest translation, largest text,
// narrowest phone, together.

/// Tears the previous tree down first so a pending overflow is not blamed on
/// this locale. Pushed through `showDialog` as production does: a dialog in
/// a page body gets different constraints.
Future<Object?> _overflowFor(
  WidgetTester tester,
  Locale locale,
  double scale,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'teardown must be clean');

  final navigator = GlobalKey<NavigatorState>();
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      navigatorKey: navigator,
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    showDialog<bool>(
      context: navigator.currentContext!,
      builder: (_) =>
          const SyncMethodDialog(showsPassphraseWarning: true),
    ),
  );
  await tester.pumpAndSettle();
  // Any exception counts. Narrowing this to FlutterError would silently drop
  // whatever else layout throws and report a false green.
  return tester.takeException();
}

void main() {
  /// A 360dp-wide phone surface, restored after the test.
  void phoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the chooser fits a 360dp phone in English at normal text',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    expect(await _overflowFor(tester, const Locale('en'), 1.0), isNull);
    expect(find.text('Merge automatically'), findsOneWidget);
    expect(find.text('Review all changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('no overflow in any locale at 2x on a 360dp phone',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final failed = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      if (await _overflowFor(tester, locale, kPhoneMaxScale) != null) {
        failed.add(locale.toLanguageTag());
      }
    }
    expect(failed, isEmpty, reason: 'locales overflowing at 2x: $failed');
  });

  // Cancel lives in the AlertDialog's `actions`, which never scroll: at large
  // text it can be pushed off the bottom of a 360dp phone, leaving a user at
  // the largest text size no visible way out of the chooser. Every choice must
  // be reachable at every supported text scale.
  testWidgets('all three choices are tappable at 2x on a 360dp phone',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final l = lookupAppLocalizations(const Locale('en'));
    for (final label in [
      l.syncMergeAutomatically,
      l.syncReviewAllChanges,
      l.cancel,
    ]) {
      final navigator = GlobalKey<NavigatorState>();
      tester.platformDispatcher.textScaleFactorTestValue = kPhoneMaxScale;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: gabbroLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      var popped = false;
      unawaited(
        showDialog<bool>(
          context: navigator.currentContext!,
          builder: (_) =>
              const SyncMethodDialog(showsPassphraseWarning: true),
        ).then((_) => popped = true),
      );
      await tester.pumpAndSettle();

      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      // A wrapped label can extend below the screen, putting its centre (what
      // tester.tap aims at) off the bottom while the control itself is
      // perfectly reachable. Tap a point inside its visible part, as a finger
      // would - that is the real question: can the user hit this choice?
      final rect = tester.getRect(target);
      final y = (rect.top < 0 ? 0.0 : rect.top) + 20;
      expect(
        y,
        lessThan(800),
        reason: '"$label" must have a visible part on a 360x800 phone',
      );
      await tester.tapAt(Offset(rect.center.dx, y));
      await tester.pumpAndSettle();
      expect(popped, isTrue, reason: '"$label" must be tappable at 2x');
    }
  });
}
