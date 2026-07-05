import 'package:flutter/material.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/password_generator.dart';
import 'package:gabbro/src/rust/api/passphrase_generator.dart';
import 'package:gabbro/src/rust/api/types.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

// ---------------------------------------------------------------------------
// Default generator functions — call Rust via FFI in production.
// ---------------------------------------------------------------------------

String _defaultGeneratePassword(PasswordConfig config) =>
    generatePassword(config: config);

Future<String> _defaultGeneratePassphrase(PassphraseConfig config) =>
    generatePassphrase(config: config);

Future<double> _defaultPassphraseEntropyBits(
  int wordCount,
  Language language,
) => passphraseEntropyBits(wordCount: wordCount, language: language);

double _defaultEntropyBits(int poolSize, int length) =>
    entropyBits(poolSize: poolSize, length: length);

String _languageLabel(Language lang, AppLocalizations l) => switch (lang) {
  Language.english => l.langEnglish,
  Language.french => l.langFrench,
  Language.german => l.langGerman,
  Language.spanish => l.langSpanish,
  Language.italian => l.langItalian,
  Language.swedish => l.langSwedish,
  Language.danish => l.langDanish,
  Language.norwegian => l.langNorwegianBokmal,
  Language.finnish => l.langFinnish,
  Language.slovenian => l.langSlovenian,
  Language.polish => l.langPolish,
  Language.russian => l.langRussian,
  Language.hungarian => l.langHungarian,
  Language.czech => l.langCzech,
  Language.greek => l.langGreek,
  Language.portuguese => l.langPortuguesePt,
  Language.estonian => l.langEstonian,
  Language.slovak => l.langSlovak,
  Language.bulgarian => l.langBulgarian,
  Language.ukrainian => l.langUkrainian,
  Language.japanese => l.langJapanese,
  Language.korean => l.langKorean,
  Language.chineseSimplified => l.langChineseSimplified,
  Language.chineseTraditional => l.langChineseTraditional,
  Language.dutch => l.langDutch,
  Language.croatian => l.langCroatian,
  Language.lithuanian => l.langLithuanian,
  Language.latvian => l.langLatvian,
  Language.kazakh => l.langKazakh,
};

/// Maps a [LanguageChoice] (app UI locale) to a [Language] (passphrase wordlist
/// / character pool). Returns null when no wordlist exists for that language.
/// For [LanguageChoice.system] the caller should resolve via the device locale.
Language? _languageChoiceToLanguage(LanguageChoice choice) => switch (choice) {
  LanguageChoice.en => Language.english,
  LanguageChoice.fr => Language.french,
  LanguageChoice.de => Language.german,
  LanguageChoice.es => Language.spanish,
  LanguageChoice.it => Language.italian,
  LanguageChoice.sv => Language.swedish,
  LanguageChoice.da => Language.danish,
  LanguageChoice.nb || LanguageChoice.nn => Language.norwegian,
  LanguageChoice.fi => Language.finnish,
  LanguageChoice.sl => Language.slovenian,
  LanguageChoice.pl => Language.polish,
  LanguageChoice.ru => Language.russian,
  LanguageChoice.hu => Language.hungarian,
  LanguageChoice.cs => Language.czech,
  LanguageChoice.el => Language.greek,
  LanguageChoice.ptPt || LanguageChoice.ptBr => Language.portuguese,
  LanguageChoice.et => Language.estonian,
  LanguageChoice.sk => Language.slovak,
  LanguageChoice.bg => Language.bulgarian,
  LanguageChoice.uk => Language.ukrainian,
  LanguageChoice.ja => Language.japanese,
  LanguageChoice.ko => Language.korean,
  LanguageChoice.zhCn => Language.chineseSimplified,
  LanguageChoice.zhTw => Language.chineseTraditional,
  LanguageChoice.hr => Language.croatian,
  LanguageChoice.lt => Language.lithuanian,
  LanguageChoice.lv => Language.latvian,
  LanguageChoice.kk => Language.kazakh,
  LanguageChoice.nl => Language.dutch,
  _ => null, // no wordlist for this LanguageChoice
};

/// Returns false for languages that have a classic character pool but no
/// passphrase wordlist — the generator shows a "no wordlist" info message.
bool _hasPassphraseWordlist(Language lang) => true;

/// CJK scripts (Han, Hangul, kana) have no concept of letter case, so the
/// passphrase "capitalise words" option is meaningless for them — the Rust
/// side's `to_uppercase()` is a no-op. The toggle is disabled and forced off
/// for these languages.
bool _isCjkLanguage(Language lang) =>
    lang == Language.japanese ||
    lang == Language.korean ||
    lang == Language.chineseSimplified ||
    lang == Language.chineseTraditional;

/// Resolves the device locale language code to a [Language] when the app
/// setting is [LanguageChoice.system].
Language? _systemLocaleToLanguage(Locale locale) {
  final tag = locale.languageCode;
  return switch (tag) {
    'en' => Language.english,
    'fr' => Language.french,
    'de' => Language.german,
    'es' => Language.spanish,
    'it' => Language.italian,
    'sv' => Language.swedish,
    'da' => Language.danish,
    'nb' || 'nn' || 'no' => Language.norwegian,
    'fi' => Language.finnish,
    'sl' => Language.slovenian,
    'pl' => Language.polish,
    'ru' => Language.russian,
    'hu' => Language.hungarian,
    'cs' => Language.czech,
    'el' => Language.greek,
    'pt' => Language.portuguese,
    'et' => Language.estonian,
    'sk' => Language.slovak,
    'bg' => Language.bulgarian,
    'uk' => Language.ukrainian,
    'ja' => Language.japanese,
    'ko' => Language.korean,
    'zh' => Language.chineseSimplified,
    'nl' => Language.dutch,
    'hr' => Language.croatian,
    'lt' => Language.lithuanian,
    'lv' => Language.latvian,
    'kk' => Language.kazakh,
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// GeneratorWidget
//
// Reusable password / passphrase generator.
// - Standalone: wrap in GeneratorScreen (no onUsePassword).
// - Inline in CreateEntryScreen: pass onUsePassword callback.
// ---------------------------------------------------------------------------

enum _GeneratorMode { classic, passphrase }

class GeneratorWidget extends StatefulWidget {
  /// If non-null, a "Use this password" button is shown that calls this
  /// callback with the currently generated value.
  final void Function(String value)? onUsePassword;

  /// How long before the copied value is wiped from the clipboard. Defaults to
  /// 60 seconds. Threaded to the shared [ClipboardClearMixin].
  final ClipboardClearTimeout clipboardClearTimeout;

  // Injectable for testing — defaults call Rust FFI.
  final String Function(PasswordConfig config) generatePasswordFn;
  final Future<String> Function(PassphraseConfig config) generatePassphraseFn;
  final Future<double> Function(int wordCount, Language language)
  passphraseEntropyBitsFn;
  final double Function(int poolSize, int length) entropyBitsFn;

  const GeneratorWidget({
    super.key,
    this.onUsePassword,
    this.clipboardClearTimeout = ClipboardClearTimeout.sixtySeconds,
    this.generatePasswordFn = _defaultGeneratePassword,
    this.generatePassphraseFn = _defaultGeneratePassphrase,
    this.passphraseEntropyBitsFn = _defaultPassphraseEntropyBits,
    this.entropyBitsFn = _defaultEntropyBits,
  });

  @override
  State<GeneratorWidget> createState() => _GeneratorWidgetState();
}

class _GeneratorWidgetState extends State<GeneratorWidget>
    with ClipboardClearMixin<GeneratorWidget> {
  // ── Mode ─────────────────────────────────────────────────────────────────
  _GeneratorMode _mode = _GeneratorMode.classic;

  // ── Generated value ───────────────────────────────────────────────────────
  String _generated = '';
  bool _obscured = true;
  double _entropyBits = 0;

  // ── Classic config ────────────────────────────────────────────────────────
  double _length = 32;
  bool _useUppercase = true;
  bool _useLowercase = true;
  bool _useDigits = true;
  bool _useSymbols = false;
  bool _excludeAmbiguous = false;

  // ── Passphrase config ─────────────────────────────────────────────────────
  double _wordCount = 5;
  String _separator = '-';
  bool _capitalise = false;
  bool _appendNumber = false;
  Language _language = Language.english;
  bool _showLangFallback = false;

  // ── Clipboard ─────────────────────────────────────────────────────────────
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = GabbroApp.maybeOf(context);
    if (appState == null) return; // test environment without GabbroApp
    final choice = appState.settings.language;
    final Language? resolved;
    if (choice == LanguageChoice.system) {
      resolved = _systemLocaleToLanguage(Localizations.localeOf(context));
    } else {
      resolved = _languageChoiceToLanguage(choice);
    }
    final newLanguage = resolved ?? Language.english;
    final newFallback =
        resolved == null || !_hasPassphraseWordlist(newLanguage);
    if (newLanguage != _language || newFallback != _showLangFallback) {
      setState(() {
        _language = newLanguage;
        _showLangFallback = newFallback;
      });
      _generate(); // regenerate immediately with the resolved script/wordlist
    }
  }

  // ── Generation ────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    if (_mode == _GeneratorMode.classic) {
      _generateClassic();
    } else {
      await _generatePassphrase();
    }
  }

  void _generateClassic() {
    final config = PasswordConfig(
      length: _length.round(),
      useUppercase: _useUppercase,
      useLowercase: _useLowercase,
      useDigits: _useDigits,
      useSymbols: _useSymbols,
      excludeAmbiguous: _excludeAmbiguous,
      language: _language,
    );
    try {
      final pwd = widget.generatePasswordFn(config);
      final poolSize = _poolSize();
      setState(() {
        _generated = pwd;
        _entropyBits = poolSize > 0
            ? widget.entropyBitsFn(poolSize, _length.round())
            : 0;
      });
    } catch (e) {
      setState(() {
        _generated = '';
        _entropyBits = 0;
      });
    }
  }

  Future<void> _generatePassphrase() async {
    // Fall back to English wordlist for languages that have a classic pool but
    // no passphrase wordlist (CJK). The message already tells the user this.
    final passphraseLanguage = _hasPassphraseWordlist(_language)
        ? _language
        : Language.english;
    final config = PassphraseConfig(
      wordCount: _wordCount.round(),
      separator: _separator,
      // Caseless CJK scripts cannot be capitalised — Rust's to_uppercase() is
      // a no-op there, but send false so the config matches the disabled UI.
      capitalise: _isCjkLanguage(passphraseLanguage) ? false : _capitalise,
      appendNumber: _appendNumber,
      language: passphraseLanguage,
    );
    try {
      final phrase = await widget.generatePassphraseFn(config);
      final bits = await widget.passphraseEntropyBitsFn(
        _wordCount.round(),
        passphraseLanguage,
      );
      if (mounted) {
        setState(() {
          _generated = phrase;
          _entropyBits = bits;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generated = '';
          _entropyBits = 0;
        });
      }
    }
  }

  int _poolSize() {
    int size = 0;
    switch (_language) {
      // Combined pools: one pool regardless of uppercase/lowercase selection.
      case Language.korean:
        if (_useUppercase || _useLowercase) size += 2350;
      case Language.chineseSimplified || Language.chineseTraditional:
        if (_useUppercase || _useLowercase) size += 3755;
      // Japanese: Katakana (uppercase) + Hiragana (lowercase), 46 each.
      case Language.japanese:
        if (_useUppercase) size += 46;
        if (_useLowercase) size += 46;
      default:
        if (_useUppercase) {
          size += switch (_language) {
            Language.greek => 24,
            Language.russian || Language.ukrainian => 33,
            Language.bulgarian => 30,
            _ => _excludeAmbiguous ? 24 : 26,
          };
        }
        if (_useLowercase) {
          size += switch (_language) {
            Language.greek => 24,
            Language.russian || Language.ukrainian => 33,
            Language.bulgarian => 30,
            _ => _excludeAmbiguous ? 23 : 26,
          };
        }
    }
    if (_useDigits) size += _excludeAmbiguous ? 8 : 10;
    if (_useSymbols) size += 26; // "!@#$%^&*()-_=+[]{}|;:,.<>?"
    return size;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  Future<void> _copy() async {
    if (_generated.isEmpty) return;
    await copyThenClear(_generated, widget.clipboardClearTimeout);
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16 + MediaQuery.of(context).padding.left,
        16,
        16 + MediaQuery.of(context).padding.right,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode toggle
          SegmentedRow<_GeneratorMode>(
            values: _GeneratorMode.values,
            selected: _mode,
            label: (m) => m == _GeneratorMode.classic
                ? l.generatorModeClassic
                : l.generatorModePassphrase,
            onSelected: (m) {
              setState(() => _mode = m);
              _generate();
            },
          ),
          const SizedBox(height: 20),

          // Generated value card
          _buildValueCard(colorScheme, l),
          const SizedBox(height: 8),

          // Entropy display
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              key: const Key('entropy_display'),
              _entropyBits > 0
                  ? l.entropyBitsDisplay(_entropyBits.toStringAsFixed(1))
                  : l.selectAtLeastOneCharSet,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Language picker — shared: drives passphrase wordlist and classic
          // character pool (Greek / Cyrillic scripts replace Latin pool).
          SectionHeader(label: l.languageHeader),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Language>(
                key: const Key('language_selector'),
                value: _language,
                isExpanded: true,
                itemHeight:
                    null, // menu items grow to wrapped height at large text
                // Collapsed selection ellipsizes instead of hard-clipping (ADR-016).
                selectedItemBuilder: (context) =>
                    (Language.values.toList()..sort(
                          (a, b) => _languageLabel(
                            a,
                            l,
                          ).compareTo(_languageLabel(b, l)),
                        ))
                        .map(
                          (lang) => Text(
                            _languageLabel(lang, l),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                        .toList(),
                items:
                    (Language.values.toList()..sort(
                          (a, b) => _languageLabel(
                            a,
                            l,
                          ).compareTo(_languageLabel(b, l)),
                        ))
                        .map(
                          (lang) => DropdownMenuItem<Language>(
                            value: lang,
                            child: Text(_languageLabel(lang, l)),
                          ),
                        )
                        .toList(),
                onChanged: (lang) {
                  if (lang == null) return;
                  setState(() {
                    _language = lang;
                    _showLangFallback = !_hasPassphraseWordlist(lang);
                  });
                  _generate();
                },
              ),
            ),
          ),
          if (_showLangFallback) ...[
            const SizedBox(height: 6),
            Text(
              l.passphraseNoWordlist,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Mode-specific controls
          if (_mode == _GeneratorMode.classic) ..._classicControls(l),
          if (_mode == _GeneratorMode.passphrase) ..._passphraseControls(l),
          const SizedBox(height: 24),

          // Minimum length info — only meaningful for classic (character-based)
          // passwords; passphrases are word-based, so the note is hidden there.
          if (_mode == _GeneratorMode.classic)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.passwordMinLengthNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          // Generate button
          FilledButton.icon(
            key: const Key('generate_button'),
            onPressed: _generate,
            icon: const Icon(Icons.refresh),
            label: Text(l.generate),
          ),

          // Use this password button (only when callback provided)
          if (widget.onUsePassword != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('use_password_button'),
              onPressed: _generated.isNotEmpty
                  ? () => widget.onUsePassword!(_generated)
                  : null,
              child: Text(l.useThisPassword),
            ),
          ],
        ],
      ),
    );
  }

  void _showBreakdown() => showModalBottomSheet<void>(
    context: context,
    builder: (_) => PasswordBreakdownSheet(password: _generated),
  );

  Widget _buildValueCard(ColorScheme colorScheme, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onLongPress: (_obscured || _generated.isEmpty)
                  ? null
                  : _showBreakdown,
              child: Text(
                key: const Key('generated_value'),
                _generated.isEmpty
                    ? '—'
                    : (_obscured
                          ? '•' * _generated.length.clamp(0, 32)
                          : _generated),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: _obscured ? 2 : 0.5,
                ),
                maxLines: _obscured ? 1 : null,
                overflow: _obscured
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
              ),
            ),
          ),
          // Breakdown — only when revealed + non-empty (matches the long-press).
          if (!_obscured && _generated.isNotEmpty)
            IconButton(
              key: const Key('breakdown_button'),
              icon: const Icon(Icons.analytics_outlined),
              tooltip: l.passwordBreakdownTitle,
              onPressed: _showBreakdown,
            ),
          // Visibility toggle
          IconButton(
            key: const Key('visibility_toggle'),
            iconSize: scaledIconSize(context),
            icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
            tooltip: _obscured ? l.tooltipShow : l.tooltipHide,
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
          // Copy button
          IconButton(
            key: const Key('copy_button'),
            icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
            tooltip: _copied ? l.tooltipCopied : l.tooltipCopy,
            onPressed: _copy,
          ),
        ],
      ),
    );
  }

  // ── Classic controls ──────────────────────────────────────────────────────

  List<Widget> _classicControls(AppLocalizations l) => [
    Row(
      children: [
        Expanded(child: Text(l.lengthLabel, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('${_length.round()}'),
      ],
    ),
    Slider(
      key: const Key('length_slider'),
      value: _length,
      min: 12,
      max: 256,
      divisions: 244,
      label: _length.round().toString(),
      onChanged: (v) {
        setState(() => _length = v);
        _generateClassic();
      },
    ),
    const SizedBox(height: 8),
    SectionHeader(label: l.charSetsHeader),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _toggleChip(
          key: const Key('toggle_uppercase'),
          label: 'A–Z',
          value: _useUppercase,
          onChanged: (v) {
            setState(() => _useUppercase = v);
            _generateClassic();
          },
        ),
        _toggleChip(
          key: const Key('toggle_lowercase'),
          label: 'a–z',
          value: _useLowercase,
          onChanged: (v) {
            setState(() => _useLowercase = v);
            _generateClassic();
          },
        ),
        _toggleChip(
          key: const Key('toggle_digits'),
          label: '0–9',
          value: _useDigits,
          onChanged: (v) {
            setState(() => _useDigits = v);
            _generateClassic();
          },
        ),
        _toggleChip(
          key: const Key('toggle_symbols'),
          label: '!@#…',
          value: _useSymbols,
          onChanged: (v) {
            setState(() => _useSymbols = v);
            _generateClassic();
          },
        ),
      ],
    ),
    const SizedBox(height: 12),
    _switchRow(
      key: const Key('toggle_exclude_ambiguous'),
      label: l.excludeAmbiguousChars,
      value: _excludeAmbiguous,
      onChanged: (v) {
        setState(() => _excludeAmbiguous = v);
        _generateClassic();
      },
    ),
  ];

  // ── Passphrase controls ───────────────────────────────────────────────────

  List<Widget> _passphraseControls(AppLocalizations l) => [
    Row(
      children: [
        Expanded(child: Text(l.wordsLabel, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('${_wordCount.round()}'),
      ],
    ),
    Slider(
      key: const Key('word_count_slider'),
      value: _wordCount,
      min: 4,
      max: 20,
      divisions: 16,
      label: _wordCount.round().toString(),
      onChanged: (v) {
        setState(() => _wordCount = v);
        _generatePassphrase();
      },
    ),
    const SizedBox(height: 8),
    TextFormField(
      initialValue: _separator,
      decoration: InputDecoration(
        labelText: l.separatorLabel,
        border: const OutlineInputBorder(),
      ),
      maxLength: 3,
      onChanged: (v) {
        setState(() => _separator = v);
        _generatePassphrase();
      },
    ),
    const SizedBox(height: 8),
    _switchRow(
      key: const Key('toggle_capitalise'),
      // Caseless CJK scripts have no capitalisation: show off + disabled,
      // regardless of the stored preference.
      label: l.capitaliseWords,
      value: _isCjkLanguage(_language) ? false : _capitalise,
      onChanged: _isCjkLanguage(_language)
          ? null
          : (v) {
              setState(() => _capitalise = v);
              _generatePassphrase();
            },
    ),
    _switchRow(
      key: const Key('toggle_append_number'),
      label: l.appendDigit,
      value: _appendNumber,
      onChanged: (v) {
        setState(() => _appendNumber = v);
        _generatePassphrase();
      },
    ),
  ];

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _toggleChip({
    required Key key,
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: value
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        foregroundColor: value ? colorScheme.onPrimary : colorScheme.onSurface,
      ),
      onPressed: () => onChanged(!value),
      child: Text(label),
    );
  }

  Widget _switchRow({
    required Key key,
    required String label,
    required bool value,
    required void Function(bool)? onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label)),
        Switch(key: key, value: value, onChanged: onChanged),
      ],
    );
  }
}
