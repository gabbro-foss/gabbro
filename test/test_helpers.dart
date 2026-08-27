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

/// The hint a screen reader reads for the node [finder] resolves to. Android
/// only: the Linux embedder never reads a node's hint.
String hintOf(WidgetTester t, Finder finder) =>
    t.getSemantics(finder).getSemanticsData().hint;

/// The name a screen reader reads for the node [finder] resolves to. On Linux
/// this is the only text that reaches the reader at all.
String labelOf(WidgetTester t, Finder finder) =>
    t.getSemantics(finder).getSemanticsData().label;

/// How many times [needle] appears in [haystack]. Used to catch a screen reader
/// being told the same thing twice by two different widgets.
int occurrencesOf(String haystack, String needle) => needle.isEmpty
    ? 0
    : RegExp(RegExp.escape(needle)).allMatches(haystack).length;

/// The label of every semantics node that has a name of its own AND children
/// beneath it — a "named container". This is what actually reaches Orca when
/// focus lands on a control inside it: the Linux embedder reads only names, so
/// a region is audible because it is a named ancestor, not because it is a
/// live region (which Linux ignores entirely).
List<String> namedContainerLabels(WidgetTester t) => allSemanticsNodes(t)
    .where((n) => n.childrenCount > 0)
    .map((n) => n.getSemanticsData().label)
    .where((l) => l.isNotEmpty)
    .toList();

/// The first line of every named container's label — what a screen reader is
/// given first when focus lands inside it. Two of the vault list's regions have
/// a child's own name merged onto the end of theirs (the search box's
/// placeholder, the chips row's page chevron), so an exact match would miss
/// them; the region name still comes first, which is what matters.
List<String> containerNames(WidgetTester t) =>
    namedContainerLabels(t).map((l) => l.split('\n').first).toList();

/// Every label in the semantics subtree rooted at the node [finder] resolves
/// to, in tree order. Lets a test count what a reader works through for one
/// region or one row without depending on which widget carries each name.
List<String> subtreeLabels(WidgetTester t, Finder finder) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    final label = n.getSemanticsData().label;
    if (label.isNotEmpty) out.add(label);
    n.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(t.getSemantics(finder));
  return out;
}

/// Captures every `SemanticsService.announce()` the app makes, in order — the
/// only channel that speaks on Linux for something that is an EVENT rather
/// than a place (a shortcut firing, a sheet opening). Returns a growing list.
List<String> recordAnnouncements(WidgetTester t) {
  final said = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map?;
      if (map != null && map['type'] == 'announce') {
        said.add((map['data'] as Map)['message'] as String? ?? '');
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
  );
  return said;
}

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

/// Whether the user can actually get to the whole of [message]: either its
/// rectangle fits the screen, or a scroll ancestor can reach the rest. A
/// SnackBar has neither once the text outgrows the strip - it clips, and the
/// remainder is unreachable by any gesture (see snackbar_message_reach_test).
bool messageIsReachable(WidgetTester tester, Finder message) {
  if (message.evaluate().isEmpty) return false;
  final rect = tester.getRect(message);
  final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  if (rect.top >= 0 && rect.bottom <= screen) return true;
  return find
      .ancestor(of: message, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty;
}
