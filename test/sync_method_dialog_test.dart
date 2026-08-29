import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/widgets/gabbro_dialog.dart';
import 'package:gabbro/widgets/sync_method_dialog.dart';

// A merge cannot be undone, so the value each choice returns and the
// "this may not be your vault" warning must survive any rewording. Pushed
// through showGabbroDialog as production does, or the pinned tree is one the
// user never sees.

/// Opens the chooser and hands whatever it pops to [onResult]. [warning] is the
/// passphrase-only flag production computes as `!isKeyProtected`.
Future<void> openChooser(
  WidgetTester tester, {
  required bool warning,
  void Function(bool?)? onResult,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    showGabbroDialog<bool>(
      context: navigator.currentContext!,
      builder: (_) => SyncMethodDialog(showsPassphraseWarning: warning),
    ).then((v) => onResult?.call(v)),
  );
  await tester.pumpAndSettle();
}

/// Vertical position of [label] on screen, for order assertions.
double topOf(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label)).dy;

const mergeLabel = 'Merge automatically';
const reviewLabel = 'Review all changes';
const cancelLabel = 'Cancel';
const warningText = 'Same passphrase does not prove same vault.';
const explainer =
    'Merge automatically takes the other device\'s value wherever the two '
    'differ. A review starts from those same answers.';
const mergeAnnounced =
    'Merge automatically. Takes the other device\'s value wherever the two '
    'differ.';
const reviewAnnounced =
    'Review all changes. Starts from those same answers, and you can change '
    'any of them.';

void main() {
  group('N1-N3 each choice returns what the caller acts on', () {
    // vault_list_screen reads these three values directly: true takes the
    // no-questions merge, false opens the review, null merges nothing at all.
    testWidgets('N1 Merge automatically applies the whole sync', (tester) async {
      bool? result;
      var called = false;
      await openChooser(
        tester,
        warning: true,
        onResult: (v) {
          result = v;
          called = true;
        },
      );
      await tester.tap(find.text(mergeLabel));
      await tester.pumpAndSettle();
      expect(called, isTrue, reason: 'the dialog must close');
      expect(result, isTrue);
    });

    testWidgets('N2 Review all changes opens the one-by-one review', (
      tester,
    ) async {
      bool? result;
      var called = false;
      await openChooser(
        tester,
        warning: true,
        onResult: (v) {
          result = v;
          called = true;
        },
      );
      await tester.tap(find.text(reviewLabel));
      await tester.pumpAndSettle();
      expect(called, isTrue, reason: 'the dialog must close');
      expect(result, isFalse);
    });

    testWidgets('N3 Cancel leaves the vault untouched', (tester) async {
      bool? result = true;
      var called = false;
      await openChooser(
        tester,
        warning: true,
        onResult: (v) {
          result = v;
          called = true;
        },
      );
      await tester.tap(find.text(cancelLabel));
      await tester.pumpAndSettle();
      expect(called, isTrue, reason: 'the dialog must close');
      expect(
        result,
        isNull,
        reason: 'null is the caller\'s "merge nothing" signal',
      );
    });
  });

  group('N4 the same-passphrase warning is source-dependent', () {
    // A passphrase-only file that opens proves only that the passphrases match,
    // so the user is warned it may be a different vault. A key-protected file
    // that is not this vault fails to decrypt outright, so the warning would be
    // noise. This branch has had no test at all until now.
    testWidgets('shown for a passphrase-only source', (tester) async {
      await openChooser(tester, warning: true);
      expect(find.text(warningText), findsOneWidget);
    });

    testWidgets('absent for a key-protected source', (tester) async {
      await openChooser(tester, warning: false);
      expect(find.text(warningText), findsNothing);
      // The choices themselves must still all be there.
      for (final label in const [mergeLabel, reviewLabel, cancelLabel]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
    });
  });

  group('R1-R3 the chooser explains what Merge automatically does', () {
    // "Merge automatically" named an action without saying what it did, so it
    // went unused. The explanation has to reach a screen-reader user too: on
    // Linux only a widget's NAME is read and a paragraph is never announced when
    // the dialog opens, so the same words also ride on the buttons themselves.
    testWidgets('R1 the explainer is shown, passphrase-only source', (
      tester,
    ) async {
      await openChooser(tester, warning: true);
      expect(find.text(explainer), findsOneWidget);
    });

    testWidgets('R1 the explainer is shown, key-protected source', (
      tester,
    ) async {
      await openChooser(tester, warning: false);
      expect(find.text(explainer), findsOneWidget);
    });

    testWidgets('R2 each choice announces its own meaning', (tester) async {
      final handle = tester.ensureSemantics();
      await openChooser(tester, warning: true);
      expect(find.bySemanticsLabel(mergeAnnounced), findsOneWidget);
      expect(find.bySemanticsLabel(reviewAnnounced), findsOneWidget);
      handle.dispose();
    });

    testWidgets('R2 both choices are still exposed as buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await openChooser(tester, warning: true);
      for (final name in [mergeAnnounced, reviewAnnounced]) {
        final node = tester.getSemantics(find.bySemanticsLabel(name));
        expect(
          node.flagsCollection.isButton,
          isTrue,
          reason: '"$name" must still announce as a button',
        );
      }
      handle.dispose();
    });

    testWidgets('R3 every choice is reachable by keyboard', (tester) async {
      await openChooser(tester, warning: true);
      final reached = <String>{};
      // Walk the whole traversal ring; the dialog has few focusables, so a full
      // lap is cheap and does not depend on where focus happens to start.
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        // Ask which subtree holds focus, not whether a button sits under some
        // Focus: `Focus.maybeOf` on a button's element returns the enclosing
        // scope, which is true of every button at once and proves nothing.
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused == null) continue;
        for (final label in const [mergeLabel, reviewLabel, cancelLabel]) {
          final inFocusedSubtree = find.descendant(
            of: find.byWidget(focused.widget),
            matching: find.text(label),
          );
          if (inFocusedSubtree.evaluate().isNotEmpty) reached.add(label);
        }
      }
      expect(
        reached,
        containsAll(const [mergeLabel, reviewLabel, cancelLabel]),
        reason: 'a keyboard user must be able to reach all three choices',
      );
    });
  });

  group('N5 the choices keep their order', () {
    // The order is what makes the dialog predictable: the button under your
    // thumb must not change meaning between one sync and the next.
    testWidgets('merge, then review, then cancel', (tester) async {
      await openChooser(tester, warning: true);
      expect(topOf(tester, mergeLabel), lessThan(topOf(tester, reviewLabel)));
      expect(topOf(tester, reviewLabel), lessThan(topOf(tester, cancelLabel)));
    });

    testWidgets('same order without the warning', (tester) async {
      await openChooser(tester, warning: false);
      expect(topOf(tester, mergeLabel), lessThan(topOf(tester, reviewLabel)));
      expect(topOf(tester, reviewLabel), lessThan(topOf(tester, cancelLabel)));
    });
  });
}
