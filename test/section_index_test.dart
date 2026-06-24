import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/section_index.dart';

const _en = Locale('en');
const _ru = Locale('ru');
const _uk = Locale('uk');
const _bg = Locale('bg');
const _kk = Locale('kk');
const _el = Locale('el');
const _ko = Locale('ko');
const _ja = Locale('ja');
const _zh = Locale('zh');

// Pins the CURRENT (Latin-only) bucketing behaviour at the extracted seam,
// before the script-aware rework. Non-Latin scripts collapse into '#' today.

void main() {
  group('sectionBucket', () {
    test('Latin title -> uppercase first letter', () {
      expect(sectionBucket('Quartz'), 'Q');
    });

    test('lowercase Latin -> uppercase header', () {
      expect(sectionBucket('quartz'), 'Q');
    });

    test('empty title -> #', () {
      expect(sectionBucket(''), '#');
    });

    test('digit-first -> #', () {
      expect(sectionBucket('7-Zip'), '#');
    });

    test('Greek title -> # today', () {
      expect(sectionBucket('Άλφα'), '#');
    });

    test('Cyrillic title -> # today', () {
      expect(sectionBucket('Борис'), '#');
    });

    test('Korean title -> # today', () {
      expect(sectionBucket('김치'), '#');
    });
  });

  group('sectionSortRank', () {
    test('Latin ranks before #', () {
      expect(sectionSortRank('Quartz'), 0);
      expect(sectionSortRank('7'), 1);
      expect(sectionSortRank(''), 1);
      expect(sectionSortRank('Άλφα'), 1);
    });
  });

  // ── Cycle 1: Cyrillic ──────────────────────────────────────────────────────

  group('sectionBucket - Cyrillic', () {
    test('Latin preserved with explicit locale', () {
      expect(sectionBucket('Quartz', _en), 'Q');
    });

    test('ru buckets Cyrillic first letter (upper + lower)', () {
      expect(sectionBucket('Борис', _ru), 'Б');
      expect(sectionBucket('борис', _ru), 'Б');
    });

    test('ru keeps Ё', () {
      expect(sectionBucket('Ёлка', _ru), 'Ё');
    });

    test('uk-specific letter Ґ', () {
      expect(sectionBucket('Ґава', _uk), 'Ґ');
    });

    test('uk rejects non-Ukrainian Ё', () {
      expect(sectionBucket('Ёж', _uk), '#');
    });

    test('bg rejects Ё but accepts Б', () {
      expect(sectionBucket('Ёлка', _bg), '#');
      expect(sectionBucket('Борис', _bg), 'Б');
    });

    test('kk-specific letter Ә', () {
      expect(sectionBucket('Әке', _kk), 'Ә');
    });

    test('cross-script falls to #', () {
      expect(sectionBucket('Apple', _ru), '#');
      expect(sectionBucket('Борис', _en), '#');
    });
  });

  group('sectionSortRank - locale', () {
    test('on-script ranks 0, off-script ranks 1', () {
      expect(sectionSortRank('Борис', _ru), 0);
      expect(sectionSortRank('Apple', _ru), 1);
    });
  });

  // ── Cycle 2: Greek (accent-folding) ────────────────────────────────────────

  group('sectionBucket - Greek', () {
    test('accented capital folds to base', () {
      expect(sectionBucket('Άλφα', _el), 'Α');
    });

    test('lowercase accented folds and uppercases', () {
      expect(sectionBucket('αβγ', _el), 'Α');
    });

    test('Ό -> Ο and Ή -> Η', () {
      expect(sectionBucket('Όμικρον', _el), 'Ο');
      expect(sectionBucket('Ήλιος', _el), 'Η');
    });

    test('dialytika folds (Ϊ -> Ι)', () {
      expect(sectionBucket('Ϊδιο', _el), 'Ι');
    });

    test('Latin off-script in el -> #', () {
      expect(sectionBucket('Apple', _el), '#');
    });

    test('Greek in a Latin locale -> # (regression)', () {
      expect(sectionBucket('Άλφα', _en), '#');
    });
  });

  // ── Cycle 3: Korean (jamo decomposition) ───────────────────────────────────

  group('sectionBucket - Korean', () {
    test('syllable buckets under its leading consonant', () {
      expect(sectionBucket('김치', _ko), 'ㄱ');
      expect(sectionBucket('나비', _ko), 'ㄴ');
      expect(sectionBucket('하늘', _ko), 'ㅎ');
    });

    test('double consonant folds to its base (ㅃ -> ㅂ)', () {
      expect(sectionBucket('빠른', _ko), 'ㅂ');
    });

    test('Latin off-script in ko -> #', () {
      expect(sectionBucket('Apple', _ko), '#');
    });

    test('Korean in a Latin locale -> # (regression)', () {
      expect(sectionBucket('김치', _en), '#');
    });
  });

  // ── Cycle 4: CJK no-bar locales ─────────────────────────────────────────────

  group('isIndexableLocale', () {
    test('ja and zh have no index bar', () {
      expect(isIndexableLocale(_ja), isFalse);
      expect(isIndexableLocale(_zh), isFalse);
    });

    test('Latin, Greek, Cyrillic, Korean are indexable', () {
      expect(isIndexableLocale(_en), isTrue);
      expect(isIndexableLocale(_el), isTrue);
      expect(isIndexableLocale(_ru), isTrue);
      expect(isIndexableLocale(_ko), isTrue);
    });

    test('null locale is indexable (defaults to Latin)', () {
      expect(isIndexableLocale(null), isTrue);
    });
  });

  group('canonicalAlphabet', () {
    test('ko is 14 jamo + #, length 15', () {
      final a = canonicalAlphabet(_ko);
      expect(a.first, 'ㄱ');
      expect(a.last, '#');
      expect(a.length, 15);
      expect(a, contains('ㅎ'));
    });

    test('el starts Α Β Γ, ends #, length 25', () {
      final a = canonicalAlphabet(_el);
      expect(a.first, 'Α');
      expect(a[1], 'Β');
      expect(a[2], 'Γ');
      expect(a.last, '#');
      expect(a.length, 25);
    });

    test('ru starts А Б, ends #, length 34', () {
      final a = canonicalAlphabet(_ru);
      expect(a.first, 'А');
      expect(a[1], 'Б');
      expect(a.last, '#');
      expect(a.length, 34);
    });

    test('uk has Ґ Є І Ї, excludes ru-only letters', () {
      final a = canonicalAlphabet(_uk);
      expect(a, containsAll(<String>['Ґ', 'Є', 'І', 'Ї']));
      expect(a, isNot(contains('Ё')));
      expect(a, isNot(contains('Ъ')));
      expect(a, isNot(contains('Ы')));
      expect(a, isNot(contains('Э')));
    });

    test('bg length 31; kk has specials, length 43', () {
      expect(canonicalAlphabet(_bg).length, 31);
      final kk = canonicalAlphabet(_kk);
      expect(kk, containsAll(<String>['Ә', 'Қ', 'Ң', 'Ө']));
      expect(kk.length, 43);
    });

    test('default/Latin is A-Z + #, length 27', () {
      final a = canonicalAlphabet(_en);
      expect(a.first, 'A');
      expect(a.last, '#');
      expect(a.length, 27);
      expect(a, isNot(contains('Б')));
    });

    test('null locale defaults to Latin', () {
      expect(canonicalAlphabet(null).length, 27);
    });
  });
}
