import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';

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
const Map<String, String> _knownTapTargetTooSmall = <String, String>{};

// Screens/dialogs with a KNOWN unfixed unlabelled tappable node. Same rules.
const Map<String, String> _knownUnlabelled = <String, String>{};

// Screens/dialogs with a KNOWN unfixed text-contrast failure, each skipped (not
// silently passing) with a reason. Remove the entry once fixed. textContrast
// guideline demands >= 4.5:1 for normal text; a real failure here is a
// readability defect, a framework artifact (text over an image/scrim) is not.
const Map<String, String> _knownLowContrast = <String, String>{};

// Render modes the contrast sweep covers. Normal dark is where dimmed text
// first failed; both high-contrast variants must stay readable because a
// low-vision user can be in either light or dark.
const Map<String, ({ThemeChoice theme, bool highContrast})> _contrastModes = {
  'dark': (theme: ThemeChoice.dark, highContrast: false),
  'high-contrast light': (theme: ThemeChoice.light, highContrast: true),
  'high-contrast dark': (theme: ThemeChoice.dark, highContrast: true),
};

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

  // Sliders must keep the increase/decrease actions a screen reader uses to
  // adjust them — a Semantics/MergeSemantics label wrapper must not strip them
  // (hardware found the text-size slider unadjustable under TalkBack).
  testWidgets('the text-size slider stays screen-reader adjustable', (
    tester,
  ) async {
    final handle = await _pump(
      tester,
      appShell(screens['appearance']!(), textScale: 1.0),
    );
    final data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.increase) &&
          data.hasAction(SemanticsAction.decrease),
      isTrue,
      reason: 'the text-size slider lost its adjust actions',
    );
    handle.dispose();
  });

  // Guard on the contrast guard: low-contrast text must FAIL and clear-contrast
  // text must PASS textContrastGuideline, or a green sweep proves nothing. Same
  // async-matcher rule as above — a failure is proven by catching TestFailure.
  testWidgets('the net flags low-contrast text', (tester) async {
    final handle = await _pump(
      tester,
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            // ~1.1:1 on white — well under the 4.5:1 the guideline demands.
            child: Text('barely visible', style: TextStyle(color: Color(0xFFEDEDED))),
          ),
        ),
      ),
    );
    expect(
      await failsGuideline(tester, meetsGuideline(textContrastGuideline)),
      isTrue,
      reason: 'light-grey text on white must fail the contrast guideline',
    );
    handle.dispose();
  });

  testWidgets('the net passes clear-contrast text', (tester) async {
    final handle = await _pump(
      tester,
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Text('clearly visible', style: TextStyle(color: Colors.black)),
          ),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  // The "setting does nothing" half: flipping the theme / high-contrast setting
  // must actually change the ThemeData the screens are built under. Capture the
  // live theme from a BuildContext inside the app shell (initialScreen renders
  // beneath GabbroApp's MaterialApp, so Theme.of resolves the applied theme).
  Future<ThemeData> themeUnder(
    WidgetTester tester, {
    required ThemeChoice theme,
    required bool highContrast,
  }) async {
    late ThemeData captured;
    tester.view.physicalSize = phone.physical;
    tester.view.devicePixelRatio = phone.dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      KeyedSubtree(
        // Unique key per settings combo: without it Flutter reuses GabbroApp's
        // State across the two pumps in one test, initState never re-seeds
        // _settings, and the second render keeps the first settings.
        key: ValueKey('$theme-$highContrast'),
        child: appShell(
          Builder(
            builder: (ctx) {
              captured = Theme.of(ctx);
              return const SizedBox();
            },
          ),
          textScale: 1.0,
          theme: theme,
          highContrast: highContrast,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return captured;
  }

  testWidgets('theme choice reaches the rendered app', (tester) async {
    final light = await themeUnder(
      tester,
      theme: ThemeChoice.light,
      highContrast: false,
    );
    final dark = await themeUnder(
      tester,
      theme: ThemeChoice.dark,
      highContrast: false,
    );
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark, reason: 'the dark setting did nothing');
  });

  testWidgets('high-contrast reaches the rendered app', (tester) async {
    final normal = await themeUnder(
      tester,
      theme: ThemeChoice.dark,
      highContrast: false,
    );
    final hc = await themeUnder(
      tester,
      theme: ThemeChoice.dark,
      highContrast: true,
    );
    expect(
      hc.colorScheme.primary,
      isNot(normal.colorScheme.primary),
      reason: 'the high-contrast setting did nothing',
    );
  });

  // Plumbing: the high-contrast setting must actually reach the alphabet bar
  // in the vault list. The bar's dim absent-letters / ellipsis are excluded
  // from semantics, so the contrast sweep can't see them — this asserts the
  // setting flows through the screen to the widget that acts on it.
  testWidgets('high-contrast setting reaches the vault-list alphabet bar', (
    tester,
  ) async {
    final handle = await _pump(
      tester,
      appShell(
        screens['vault_list']!(),
        textScale: 1.0,
        theme: ThemeChoice.dark,
        highContrast: true,
      ),
    );
    final bar = tester.widget<AlphabetIndexBar>(find.byType(AlphabetIndexBar));
    expect(bar.highContrast, isTrue);
    handle.dispose();
  });

  // --- Text contrast: every screen readable in dark + both high-contrasts --
  for (final mode in _contrastModes.entries) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key}: text contrast (${mode.key})',
        (tester) async {
          final handle = await _pump(
            tester,
            appShell(
              entry.value(),
              textScale: 1.0,
              theme: mode.value.theme,
              highContrast: mode.value.highContrast,
            ),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
        skip: _knownLowContrast.containsKey(entry.key) ||
            tabletOnly.containsKey(entry.key),
      );
    }

    for (final entry in dialogs.entries) {
      testWidgets(
        '${entry.key}: text contrast (${mode.key})',
        (tester) async {
          final handle = await _pump(
            tester,
            appShell(
              _dialogOpener(entry.value),
              textScale: 1.0,
              theme: mode.value.theme,
              highContrast: mode.value.highContrast,
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pump(const Duration(milliseconds: 300));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
        skip: _knownLowContrast.containsKey(entry.key),
      );
    }
  }

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
