import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/password_generator.dart';
import 'package:gabbro/src/rust/api/passphrase_generator.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

// ---------------------------------------------------------------------------
// Default generator functions — call Rust via FFI in production.
// ---------------------------------------------------------------------------

String _defaultGeneratePassword(PasswordConfig config) =>
    generatePassword(config: config);

Future<String> _defaultGeneratePassphrase(PassphraseConfig config) =>
    generatePassphrase(config: config);

Future<double> _defaultPassphraseEntropyBits(int wordCount, Language language) =>
    passphraseEntropyBits(wordCount: wordCount, language: language);

double _defaultEntropyBits(int poolSize, int length) =>
    entropyBits(poolSize: poolSize, length: length);

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

  /// Duration after which the clipboard is cleared. Defaults to 60 seconds.
  final Duration clipboardClearDuration;

  // Injectable for testing — defaults call Rust FFI.
  final String Function(PasswordConfig config) generatePasswordFn;
  final Future<String> Function(PassphraseConfig config) generatePassphraseFn;
  final Future<double> Function(int wordCount, Language language)
      passphraseEntropyBitsFn;
  final double Function(int poolSize, int length) entropyBitsFn;

  const GeneratorWidget({
    super.key,
    this.onUsePassword,
    this.clipboardClearDuration = const Duration(seconds: 60),
    this.generatePasswordFn = _defaultGeneratePassword,
    this.generatePassphraseFn = _defaultGeneratePassphrase,
    this.passphraseEntropyBitsFn = _defaultPassphraseEntropyBits,
    this.entropyBitsFn = _defaultEntropyBits,
  });

  @override
  State<GeneratorWidget> createState() => _GeneratorWidgetState();
}

class _GeneratorWidgetState extends State<GeneratorWidget> {
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

  // ── Clipboard ─────────────────────────────────────────────────────────────
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _generate();
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
    final config = PassphraseConfig(
      wordCount: _wordCount.round(),
      separator: _separator,
      capitalise: _capitalise,
      appendNumber: _appendNumber,
      language: _language,
    );
    try {
      final phrase = await widget.generatePassphraseFn(config);
      final bits = await widget.passphraseEntropyBitsFn(
        _wordCount.round(),
        _language,
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
    if (_useUppercase) size += _excludeAmbiguous ? 24 : 26;
    if (_useLowercase) size += _excludeAmbiguous ? 23 : 26;
    if (_useDigits) size += _excludeAmbiguous ? 8 : 10;
    if (_useSymbols) size += 26; // "!@#$%^&*()-_=+[]{}|;:,.<>?"
    return size;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  Future<void> _copy() async {
    if (_generated.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _generated));
    setState(() => _copied = true);
    Future.delayed(widget.clipboardClearDuration, () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
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

          // Mode-specific controls
          if (_mode == _GeneratorMode.classic) ..._classicControls(l),
          if (_mode == _GeneratorMode.passphrase) ..._passphraseControls(l),
          const SizedBox(height: 24),

          // Minimum length info
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
                  : () => showModalBottomSheet<void>(
                        context: context,
                        builder: (_) =>
                            PasswordBreakdownSheet(password: _generated),
                      ),
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
                overflow:
                    _obscured ? TextOverflow.ellipsis : TextOverflow.visible,
              ),
            ),
          ),
          // Visibility toggle
          IconButton(
            key: const Key('visibility_toggle'),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.lengthLabel),
            Text('${_length.round()}'),
          ],
        ),
        Slider(
          key: const Key('length_slider'),
          value: _length,
          min: 32,
          max: 256,
          divisions: 224,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.wordsLabel),
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
        SectionHeader(label: l.languageHeader),
        const SizedBox(height: 8),
        SegmentedRow<Language>(
          key: const Key('language_selector'),
          values: Language.values,
          selected: _language,
          label: (lang) => switch (lang) {
            Language.english => 'EN',
            Language.french => 'FR',
            Language.german => 'DE',
            Language.spanish => 'ES',
            Language.italian => 'IT',
          },
          onSelected: (lang) {
            setState(() => _language = lang);
            _generatePassphrase();
          },
        ),
        const SizedBox(height: 12),
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
          label: l.capitaliseWords,
          value: _capitalise,
          onChanged: (v) {
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
        foregroundColor:
            value ? colorScheme.onPrimary : colorScheme.onSurface,
      ),
      onPressed: () => onChanged(!value),
      child: Text(label),
    );
  }

  Widget _switchRow({
    required Key key,
    required String label,
    required bool value,
    required void Function(bool) onChanged,
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
