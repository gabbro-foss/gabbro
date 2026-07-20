import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';

import 'screen_catalog.dart';

// ADR-016 Phase 2 headless overflow probe. Renders each catalog screen at the
// device's MAX text scale on a phone and a tablet surface and asserts no
// RenderFlex / layout overflow (an overflow reports a FlutterError ->
// takeException()). The screens/dialogs themselves live in screen_catalog.dart,
// shared with the accessibility net.
//
// Blind spot: a child clipped inside a FIXED width/height throws nothing, so
// this probe cannot see it. Both defects found in the l10n/a11y sweep so far
// (recovery-history actions, sync_review chip values) were of exactly that kind
// and came from hardware use, not from here.

Widget _app(Widget screen) => appShell(screen);

// --- Longer-language (padded) axis (ADR-016 item 3) -----------------------
// A layout overflows on rendered width, and width does not care which language
// produced it: "le renard..." and "the fox..." stress the same box. So instead
// of rendering all 37 real locales, render each screen ONCE under a synthetic
// locale whose every ARB label is ~2x its English length. One pass catches what
// any real language could; it may over-report (the safe direction). See
// ARCHITECTURE.md Current Focus.

// The real English strings, read from the template ARB so the padded axis tracks
// every new UI string automatically. `@key` metadata and `@@locale` are skipped.
final Map<String, String> _enArb = () {
  final raw =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (!k.startsWith('@') && v is String) out[k] = v;
  });
  return out;
}();

// ~2x the English length. A Latin pad under-models CJK glyph width (wider per
// character), so doubling with a space is a generous, not tight, margin.
String _pad(String v) => '$v $v';

// Every AppLocalizations member returns String and is abstract, so one
// noSuchMethod handler pads all ~600 of them. The member name is recovered from
// the invocation symbol (no dart:mirrors) and mapped back to its English value.
class _PaddedLocalizations implements AppLocalizations {
  static final _symbolName = RegExp(r'Symbol\("([^"]+)"\)');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final match = _symbolName.firstMatch(invocation.memberName.toString());
    final base = match == null ? null : _enArb[match.group(1)];
    return _pad(base ?? 'padded');
  }
}

class _PaddingDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _PaddingDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_PaddedLocalizations());
  @override
  bool shouldReload(_PaddingDelegate old) => false;
}

// The real delegate list with only AppLocalizations.delegate swapped for the
// padding one, so the fallback Material/Cupertino delegates are kept verbatim
// (no drift from production). Locale stays the default (en, supported), so the
// padded strings reach dialogs — which are root routes an in-body
// Localizations.override could not touch.
final List<LocalizationsDelegate<dynamic>> _paddedDelegates = [
  const _PaddingDelegate(),
  ...gabbroLocalizationsDelegates.where((d) => d != AppLocalizations.delegate),
];

Widget _paddedApp(Widget screen) =>
    appShell(screen, localizationsDelegates: _paddedDelegates);

// Screens with a KNOWN unfixed large-text layout issue, skipped (not silently
// passing); remove the entry once fixed so the probe re-arms on it.
const Map<String, String> _knownOverflow = <String, String>{};

// Entries that overflow only under the padded (longer-language) axis, each with
// a reason. Empty means every screen and dialog survives a ~2x-length locale.
const Map<String, String> _paddedKnownOverflow = <String, String>{};

/// Render [screen] on [surface] at max text scale and return whatever layout
/// exception it threw, or null. Shared by the screen sweep and the self-test
/// below so both exercise the identical path.
Future<Object?> _probe(
  WidgetTester tester,
  Widget screen,
  Surface surface, {
  Widget Function(Widget) app = _app,
}) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(app(screen));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.takeException();
}

/// Open [dialog] on [surface] at max text scale and return any layout exception.
Future<Object?> _probeDialog(
  WidgetTester tester,
  Future<void> Function(BuildContext) dialog,
  Surface surface, {
  Widget Function(Widget) app = _app,
}) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    app(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => dialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.takeException();
}

// A Row far wider than any surface: guaranteed to overflow.
Widget _deliberateOverflow() => const Scaffold(
  body: Row(
    children: [SizedBox(width: 10000, height: 10, child: Placeholder())],
  ),
);

void main() {
  // Nothing enumerated lib/widgets/ before, so sync_review's clipped-value bug
  // sat in a file no sweep touched. This fails until every screen AND widget is
  // either in the catalog or explicitly waived with a reason.
  test('the file listing finds every screen and widget', () {
    expect(
      sourcesIn('lib/screens').length,
      screenFileCount,
      reason: 'screen count changed — add the new file to the catalog or waive '
          'it, then update screenFileCount',
    );
    expect(
      sourcesIn('lib/widgets').length,
      widgetFileCount,
      reason: 'widget count changed — add the new file to the catalog or waive '
          'it, then update widgetFileCount',
    );
  });

  test('every catalog entry named in covers really exists', () {
    // Otherwise a bare line in covers satisfies the guard below while nothing
    // is actually rendered.
    final declared = covers.keys.toSet();
    final real = {...screens.keys, ...dialogs.keys};
    expect(
      declared.difference(real),
      isEmpty,
      reason: 'covers names catalog entries that do not exist',
    );
    expect(
      real.difference(declared),
      isEmpty,
      reason: 'catalog entries missing from covers, so they cover nothing',
    );
  });

  test('every screen and widget is in the catalog or waived', () {
    final accounted = {...covers.values, ...waived.keys};
    final missing = uiSources().where((s) => !accounted.contains(s)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'not in the screen catalog and not waived:\n  ${missing.join('\n  ')}',
    );
  });

  // The guard on the guard. Every test below asserts an exception is ABSENT, so
  // if the probe ever stopped detecting overflow it would report green forever
  // and prove nothing. This pins that the mechanism still fires.
  testWidgets('the probe detects an overflow when one happens', (tester) async {
    expect(await _probe(tester, _deliberateOverflow(), phone), isNotNull);
  });

  for (final surface in const [phone, tablet]) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key} @ ${surface.name}: no overflow',
        (tester) async {
          expect(
            await _probe(tester, entry.value(), surface),
            isNull,
            reason: '${entry.key} @ ${surface.name} overflowed',
          );
        },
        skip: _knownOverflow.containsKey(entry.key) ||
            (surface == phone && tabletOnly.containsKey(entry.key)),
      );
    }

    for (final entry in dialogs.entries) {
      testWidgets(
        '${entry.key} @ ${surface.name}: no overflow',
        (tester) async {
          expect(
            await _probeDialog(tester, entry.value, surface),
            isNull,
            reason: '${entry.key} @ ${surface.name} overflowed',
          );
        },
        skip: _knownOverflow.containsKey(entry.key),
      );
    }
  }

  // --- Longer-language (padded) axis --------------------------------------
  // Guard on the guard 1: the padded delegate must actually win at MaterialApp
  // level, or every assertion below passes vacuously against real English.
  testWidgets('the padded delegate reaches the widget tree', (tester) async {
    late String seen;
    await tester.pumpWidget(
      _paddedApp(
        Builder(
          builder: (ctx) {
            seen = AppLocalizations.of(ctx).appName;
            return const SizedBox();
          },
        ),
      ),
    );
    // appName is "Gabbro" in en; the padded locale doubles it.
    expect(seen, _pad('Gabbro'));
  });

  // Guard on the guard 2: overflow detection still fires under the padded app,
  // not only under the English one.
  testWidgets('the probe detects an overflow under the padded app', (
    tester,
  ) async {
    expect(
      await _probe(tester, _deliberateOverflow(), phone, app: _paddedApp),
      isNotNull,
    );
  });

  // One pass at max text on the phone (narrowest x largest) under the padded
  // locale. Tablet-only screens are skipped as on the English phone pass.
  for (final entry in screens.entries) {
    testWidgets(
      '${entry.key} @ padded phone: no overflow',
      (tester) async {
        expect(
          await _probe(tester, entry.value(), phone, app: _paddedApp),
          isNull,
          reason: '${entry.key} overflowed under a ~2x-length locale',
        );
      },
      skip: _paddedKnownOverflow.containsKey(entry.key) ||
          tabletOnly.containsKey(entry.key),
    );
  }

  for (final entry in dialogs.entries) {
    testWidgets(
      '${entry.key} @ padded phone: no overflow',
      (tester) async {
        expect(
          await _probeDialog(tester, entry.value, phone, app: _paddedApp),
          isNull,
          reason: '${entry.key} overflowed under a ~2x-length locale',
        );
      },
      skip: _paddedKnownOverflow.containsKey(entry.key),
    );
  }
}
