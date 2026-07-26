import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Wraps [home] in a MaterialApp configured with the app's localizations.
/// Use this in place of a bare MaterialApp in widget tests.
Widget testApp(Widget home, {ThemeData? theme}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme,
  home: home,
);

/// Finds every reveal-eye (show/hide) [IconButton] on screen — those whose icon
/// is `Icons.visibility` or `Icons.visibility_off` — regardless of the current
/// obscured/revealed state. Used by the ADR-016 large-text scaling tests to
/// assert each toggle's `iconSize` grows with the text.
Finder revealEyeButtons() => find.byWidgetPredicate(
  (w) =>
      w is IconButton &&
      w.icon is Icon &&
      ((w.icon as Icon).icon == Icons.visibility ||
          (w.icon as Icon).icon == Icons.visibility_off),
);

/// Every semantics node currently in the tree, root first. Reached by climbing
/// to the root from a node inside the app rather than through the binding's
/// semantics owner, which is deprecated. Requires `tester.ensureSemantics()`.
List<SemanticsNode> allSemanticsNodes(WidgetTester t) {
  var root = t.getSemantics(find.byType(MaterialApp));
  while (root.parent != null) {
    root = root.parent!;
  }
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return out;
}

/// The label of every node currently marked as a live region — what a screen
/// reader announces on its own, without the user moving to it.
List<String> liveRegionLabels(WidgetTester t) => allSemanticsNodes(t)
    .map((n) => n.getSemanticsData())
    .where((d) => d.flagsCollection.isLiveRegion)
    .map((d) => d.label)
    .toList();

/// Installs a mock for the `Clipboard` platform channel and returns a growing
/// list of every text written via `Clipboard.setData` — a copy writes the
/// secret, the auto-clear writes an empty string. Used by the clipboard-clear
/// pins across entry-detail, the generator, and the shared mixin.
List<String> recordClipboardWrites(WidgetTester tester) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add((call.arguments as Map)['text'] as String? ?? '');
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return writes;
}
