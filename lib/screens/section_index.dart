// Pure bucketing logic for the vault-list alphabet index.
//
// Extracted from VaultListScreen so it can be unit-tested directly and so the
// script-aware rework has a single seam to evolve. The active UI locale picks
// the canonical alphabet; a title buckets under its first letter iff that
// letter is in the locale's alphabet, otherwise it collapses into '#' (which
// always sorts last).
//
// Alphabets are best-effort and unreviewed by native speakers — see
// ARCHITECTURE Current Focus. Scripts whose order can't be derived from the
// first character without a lookup table (Japanese, Chinese) get no bar.

import 'package:flutter/widgets.dart';

const String hashBucket = '#';

// Listing the alphabets as space-separated strings keeps the per-letter
// quoting from drifting; split once into the ordered canon.
final List<String> _latinLetters =
    'A B C D E F G H I J K L M N O P Q R S T U V W X Y Z'.split(' ');

final List<String> _ruLetters =
    'А Б В Г Д Е Ё Ж З И Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Ъ Ы Ь Э Ю Я'
        .split(' ');

final List<String> _ukLetters =
    'А Б В Г Ґ Д Е Є Ж З И І Ї Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Ь Ю Я'
        .split(' ');

final List<String> _bgLetters =
    'А Б В Г Д Е Ж З И Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Ъ Ь Ю Я'.split(' ');

final List<String> _kkLetters =
    'А Ә Б В Г Ғ Д Е Ё Ж З И Й К Қ Л М Н Ң О Ө П Р С Т У Ұ Ү Ф Х Һ Ц Ч Ш Щ Ъ Ы І Ь Э Ю Я'
        .split(' ');

final List<String> _greekLetters =
    'Α Β Γ Δ Ε Ζ Η Θ Ι Κ Λ Μ Ν Ξ Ο Π Ρ Σ Τ Υ Φ Χ Ψ Ω'.split(' ');

// Korean index uses the 14 basic leading consonants; the 5 double consonants
// fold to their base (ㄲ->ㄱ, ㄸ->ㄷ, ㅃ->ㅂ, ㅆ->ㅅ, ㅉ->ㅈ).
final List<String> _koreanLetters =
    'ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ'.split(' ');

// Maps a Hangul syllable's lead-consonant index (0-18) to a _koreanLetters
// index (0-13), folding doubles onto their base.
const List<int> _koreanLeadToBucket = [
  0, 0, 1, 2, 2, 3, 4, 5, 5, 6, 6, 7, 8, 8, 9, 10, 11, 12, 13,
];

// The leading-consonant bucket for a Hangul syllable code point, or null if the
// character is not a precomposed Hangul syllable (U+AC00..U+D7A3).
String? _koreanLeadJamo(int codePoint) {
  if (codePoint < 0xAC00 || codePoint > 0xD7A3) return null;
  final lead = (codePoint - 0xAC00) ~/ 588;
  return _koreanLetters[_koreanLeadToBucket[lead]];
}

// Greek text is accent-heavy and toUpperCase keeps the tonos/dialytika
// (toUpperCase('ά') == 'Ά'), so fold accented capitals to their base letter
// before the membership test.
const Map<String, String> _greekAccentFold = {
  'Ά': 'Α',
  'Έ': 'Ε',
  'Ή': 'Η',
  'Ί': 'Ι',
  'Ό': 'Ο',
  'Ύ': 'Υ',
  'Ώ': 'Ω',
  'Ϊ': 'Ι',
  'Ϋ': 'Υ',
};

List<String> _lettersFor(Locale? locale) {
  switch (locale?.languageCode) {
    case 'ru':
      return _ruLetters;
    case 'uk':
      return _ukLetters;
    case 'bg':
      return _bgLetters;
    case 'kk':
      return _kkLetters;
    case 'el':
      return _greekLetters;
    case 'ko':
      return _koreanLetters;
    default:
      return _latinLetters;
  }
}

// Scripts with no small first-character bucket set derivable without a lookup
// table (Japanese kanji, Chinese hanzi): these get no index bar, just a plain
// title-sorted list.
const Set<String> _nonIndexableLanguages = {'ja', 'zh'};

/// Whether [locale]'s script supports an alphabet index bar. False for ja/zh.
bool isIndexableLocale(Locale? locale) =>
    !_nonIndexableLanguages.contains(locale?.languageCode);

/// Ordered canonical index alphabet for [locale], with the trailing '#' bucket.
/// Feeds the index bar's slot set and the list's section headers.
List<String> canonicalAlphabet(Locale? locale) =>
    [..._lettersFor(locale), hashBucket];

/// The section header a [title] belongs under, for the given UI [locale].
String sectionBucket(String title, [Locale? locale]) {
  if (title.isEmpty) return hashBucket;
  // Korean buckets by decomposing the syllable, not by uppercase-and-match.
  if (locale?.languageCode == 'ko') {
    return _koreanLeadJamo(title.codeUnitAt(0)) ?? hashBucket;
  }
  var up = title[0].toUpperCase();
  up = _greekAccentFold[up] ?? up;
  return _lettersFor(locale).contains(up) ? up : hashBucket;
}

/// Sort rank for a [title]'s bucket: lettered buckets (0) sort before '#' (1).
int sectionSortRank(String title, [Locale? locale]) =>
    sectionBucket(title, locale) == hashBucket ? 1 : 0;
