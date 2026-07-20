import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_catalog.dart';

// Accessibility net (item 6). Sweeps every catalog screen and dialog and asserts
// two Flutter accessibility guidelines on a phone at natural text scale:
//   - androidTapTargetGuideline: every tappable control is >= 48x48dp (hittable).
//   - labeledTapTargetGuideline: every tappable node has a name a screen reader
//     can read (no bare icon-only button).
// These matchers were already used ad hoc on ~18 screens; the net makes them
// systematic across the shared catalog so a new screen cannot slip through.
//
// Blind spot: this checks the semantics TREE, not real assistive-tech output —
// a label can be present but wrong. Hardware VoiceOver/TalkBack still matters.

// Screens/dialogs with a KNOWN unfixed control smaller than 48dp, each skipped
// (not silently passing) with a reason. Remove the entry once fixed.
const Map<String, String> _knownTapTargetTooSmall = <String, String>{
  'vault_list': '"All folders" folder-filter chip renders 344x24 — 24dp high, needs 48',
  'generator': '"English" wordlist-language selector renders 296x24 — 24dp high',
  'generator_widget': 'same selector as generator (shared GeneratorWidget)',
};

// Screens/dialogs with a KNOWN unfixed unlabelled tappable node. Same rules.
const Map<String, String> _knownUnlabelled = <String, String>{};

/// Set the phone surface + a semantics handle, pump [app] at natural text scale,
/// and settle. Caller disposes the returned handle.
Future<SemanticsHandle> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = phone.physical;
  tester.view.devicePixelRatio = phone.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 300));
  return handle;
}

/// Wrap a dialog opener the same way the overflow probe does, tap it, settle.
Widget _dialogOpener(Future<void> Function(BuildContext) dialog) => Builder(
  builder: (ctx) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => dialog(ctx),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  // Guard on the guard: a too-small tappable control must FAIL the size
  // guideline, and an unlabelled one must FAIL the label guideline. Otherwise a
  // green sweep proves nothing.
  // meetsGuideline is an async matcher, so a bad widget is proven by catching
  // the TestFailure it throws — `isNot(meetsGuideline(...))` would never resolve.
  Future<bool> failsGuideline(WidgetTester tester, Matcher guideline) async {
    try {
      await expectLater(tester, guideline);
      return false;
    } on TestFailure {
      return true;
    }
  }

  testWidgets('the net flags a too-small tap target', (tester) async {
    final handle = await _pump(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InkWell(
              onTap: () {},
              child: const SizedBox(width: 24, height: 24),
            ),
          ),
        ),
      ),
    );
    expect(
      await failsGuideline(tester, meetsGuideline(androidTapTargetGuideline)),
      isTrue,
      reason: 'a 24dp tap target must fail the size guideline',
    );
    handle.dispose();
  });

  testWidgets('the net flags an unlabelled tap target', (tester) async {
    final handle = await _pump(
      tester,
      MaterialApp(
        home: Scaffold(
          // An icon-only button with no tooltip / semantic label.
          body: Center(
            child: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          ),
        ),
      ),
    );
    expect(
      await failsGuideline(tester, meetsGuideline(labeledTapTargetGuideline)),
      isTrue,
      reason: 'an icon-only button with no label must fail the label guideline',
    );
    handle.dispose();
  });

  // --- Tap-target size: every control is >= 48dp ---------------------------
  for (final entry in screens.entries) {
    testWidgets(
      '${entry.key}: tap targets >= 48dp',
      (tester) async {
        final handle = await _pump(
          tester,
          appShell(entry.value(), textScale: 1.0),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      },
      skip: _knownTapTargetTooSmall.containsKey(entry.key) ||
          tabletOnly.containsKey(entry.key),
    );
  }

  for (final entry in dialogs.entries) {
    testWidgets(
      '${entry.key}: tap targets >= 48dp',
      (tester) async {
        final handle = await _pump(
          tester,
          appShell(_dialogOpener(entry.value), textScale: 1.0),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      },
      skip: _knownTapTargetTooSmall.containsKey(entry.key),
    );
  }

  // --- Screen-reader labels: every tappable node is named ------------------
  for (final entry in screens.entries) {
    testWidgets(
      '${entry.key}: tap targets labelled',
      (tester) async {
        final handle = await _pump(
          tester,
          appShell(entry.value(), textScale: 1.0),
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
      skip: _knownUnlabelled.containsKey(entry.key) ||
          tabletOnly.containsKey(entry.key),
    );
  }

  for (final entry in dialogs.entries) {
    testWidgets(
      '${entry.key}: tap targets labelled',
      (tester) async {
        final handle = await _pump(
          tester,
          appShell(_dialogOpener(entry.value), textScale: 1.0),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
      skip: _knownUnlabelled.containsKey(entry.key),
    );
  }
}
