// The _Fallback{Material,Cupertino}LocalizationsDelegate classes wrap Flutter's
// global localizations so that UI locales the globals DON'T cover (e.g. Yoruba
// `yo`) fall back to English instead of crashing. The classes are private, but the
// public `gabbroLocalizationsDelegates` list exposes them, so we exercise both
// branches of `load` directly without mounting an app.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final materialDelegate = gabbroLocalizationsDelegates
      .whereType<LocalizationsDelegate<MaterialLocalizations>>()
      .single;
  final cupertinoDelegate = gabbroLocalizationsDelegates
      .whereType<LocalizationsDelegate<CupertinoLocalizations>>()
      .single;

  // `yo` (Yoruba) is one of Gabbro's UI locales that Flutter's global
  // localizations do not cover - the whole reason these delegates exist.
  const unsupported = Locale('yo');
  const supported = Locale('fr');

  group('fallback material localizations', () {
    test('isSupported is true for every locale', () {
      expect(materialDelegate.isSupported(unsupported), isTrue);
      expect(materialDelegate.isSupported(supported), isTrue);
    });

    test('supported locale loads that locale (if branch)', () async {
      expect(GlobalMaterialLocalizations.delegate.isSupported(supported), isTrue);
      expect(await materialDelegate.load(supported), isA<MaterialLocalizations>());
    });

    test('unsupported locale falls back to English (else branch)', () async {
      expect(GlobalMaterialLocalizations.delegate.isSupported(unsupported), isFalse,
          reason: 'premise: yo is not covered by the global material delegate');
      final en = await materialDelegate.load(const Locale('en'));
      final fallback = await materialDelegate.load(unsupported);
      expect(fallback.cancelButtonLabel, en.cancelButtonLabel,
          reason: 'an unsupported locale must yield the English strings');
    });

    test('shouldReload is false', () {
      expect(materialDelegate.shouldReload(materialDelegate), isFalse);
    });
  });

  group('fallback cupertino localizations', () {
    test('isSupported is true for every locale', () {
      expect(cupertinoDelegate.isSupported(unsupported), isTrue);
      expect(cupertinoDelegate.isSupported(supported), isTrue);
    });

    test('supported locale loads that locale (if branch)', () async {
      expect(GlobalCupertinoLocalizations.delegate.isSupported(supported), isTrue);
      expect(await cupertinoDelegate.load(supported), isA<CupertinoLocalizations>());
    });

    test('unsupported locale falls back to English (else branch)', () async {
      expect(GlobalCupertinoLocalizations.delegate.isSupported(unsupported), isFalse,
          reason: 'premise: yo is not covered by the global cupertino delegate');
      final en = await cupertinoDelegate.load(const Locale('en'));
      final fallback = await cupertinoDelegate.load(unsupported);
      expect(fallback.copyButtonLabel, en.copyButtonLabel,
          reason: 'an unsupported locale must yield the English strings');
    });

    test('shouldReload is false', () {
      expect(cupertinoDelegate.shouldReload(cupertinoDelegate), isFalse);
    });
  });
}
