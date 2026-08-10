import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/linux_url_opener.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/widgets/url_link.dart';

// The refusal message is the only thing a user gets when a stored link will not
// open. It has to survive the worst case the app supports — longest
// translation, largest text, narrowest phone, together — or the one explanation
// available is unreadable.

/// Never opens anything, so every attempt ends in the refusal message.
class _NeverOpens extends LinuxUrlOpener {
  _NeverOpens() : super(runProcess: _never);

  static Future<ProcessResult> _never(String _, List<String> _) async =>
      ProcessResult(0, 1, '', '');
}

/// Shows the refusal message at [locale] and [scale], returning the layout
/// exception if any. Any exception counts: narrowing to FlutterError would
/// silently drop whatever else layout throws and report a false green.
///
/// A SnackBar alone is not enough to judge by: it sits in an overlay and clips
/// its content instead of overflowing, so it throws nothing however long the
/// message gets. [_messageIsReachable] is what actually catches that.
Future<Object?> _overflowFor(
  WidgetTester tester,
  Locale locale,
  double scale,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'teardown must be clean');

  tester.platformDispatcher.textScaleFactorTestValue = scale;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openUrlAndReport(context, 'ssh://example.com'),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return tester.takeException();
}

/// Whether the user can actually get to the whole message.
///
/// At 8x no message this long fits a phone screen — the wrapped text is taller
/// than the display — so "fits inside the screen" is unachievable and the wrong
/// thing to ask. What matters is that it can be scrolled to, which is what a
/// dialog gives (ADR-016) and a SnackBar does not: a SnackBar clips, leaving
/// the rest unreachable by any gesture.
bool _messageIsReachable(WidgetTester tester, Finder message) {
  if (message.evaluate().isEmpty) return false;
  return find
      .ancestor(of: message, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty;
}

void main() {
  /// A 360dp-wide phone surface, restored after the test.
  void phoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() {
    GabbroUrlOpener.isLinux = () => true;
    GabbroUrlOpener.linuxOpener = _NeverOpens();
  });

  tearDown(GabbroUrlOpener.reset);

  testWidgets('7e-1: it fits a 360dp phone in English at normal text',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    expect(await _overflowFor(tester, const Locale('en'), 1.0), isNull);
  });

  testWidgets('7e-2: no overflow in any locale at 8x on a 360dp phone',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final failed = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final exception = await _overflowFor(tester, locale, 8.0);
      final message = find.text(
        lookupAppLocalizations(locale).onlyWebLinks,
      );
      if (exception != null ||
          message.evaluate().isEmpty ||
          !_messageIsReachable(tester, message)) {
        failed.add(locale.toLanguageTag());
      }
    }
    expect(failed, isEmpty, reason: 'locales unreadable at 8x: $failed');
  });

  testWidgets('7e-3: at 8x the message can still be scrolled to',
      (tester) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    expect(await _overflowFor(tester, const Locale('en'), 8.0), isNull);

    final message = find.text('Only web links can be opened');
    expect(message, findsOneWidget);
    expect(_messageIsReachable(tester, message), isTrue,
        reason: 'the message cannot be scrolled to: '
            '${tester.getRect(message)}');
  });
}
