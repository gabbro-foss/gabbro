import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/text_size_slider.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late AppSettings _settings;

  /// Live text scale while the slider is being dragged (previews without
  /// persisting every frame); null when not dragging.
  double? _dragScale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = GabbroApp.of(context).settings;
  }

  Future<void> _update(AppSettings updated) async {
    await GabbroApp.of(context).updateSettings(updated);
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.appearanceTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Theme ──────────────────────────────────────────────────
              SectionHeader(label: l.sectionTheme),
              const SizedBox(height: 8),
              SegmentedRow<ThemeChoice>(
                values: ThemeChoice.values,
                selected: _settings.theme,
                label: (v) => switch (v) {
                  ThemeChoice.system => l.themeSystem,
                  ThemeChoice.light => l.themeLight,
                  ThemeChoice.dark => l.themeDark,
                },
                onSelected: (v) => _update(_settings.copyWith(theme: v)),
              ),
              const SizedBox(height: 32),

              // ── Text size ──────────────────────────────────────────────
              SectionHeader(label: l.sectionTextSize),
              const SizedBox(height: 8),
              TextSizeSlider(
                scale: _dragScale ?? _settings.textScale,
                deviceMax:
                    deviceMaxScale(MediaQuery.of(context).size.shortestSide),
                previewText: l.textSizePreview,
                onChanged: (s) => setState(() => _dragScale = s),
                onChangeEnd: (s) {
                  _update(_settings.copyWith(textScale: s));
                  setState(() => _dragScale = null);
                },
              ),
              const SizedBox(height: 32),

              // ── Alphabet bar position ──────────────────────────────────
              SectionHeader(label: l.sectionAlphabetBar),
              const SizedBox(height: 4),
              Text(
                l.alphabetBarNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedRow<AlphabetBarPosition>(
                values: AlphabetBarPosition.values,
                selected: _settings.alphabetBarPosition,
                label: (v) => switch (v) {
                  AlphabetBarPosition.left => l.alphabetBarLeft,
                  AlphabetBarPosition.right => l.alphabetBarRight,
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(alphabetBarPosition: v)),
              ),
              const SizedBox(height: 32),

              // ── High contrast ──────────────────────────────────────────
              SectionHeader(label: l.sectionAccessibility),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.highContrastTitle),
                subtitle: Text(l.highContrastSubtitle),
                trailing: Switch(
                  value: _settings.highContrast,
                  onChanged: (v) =>
                      _update(_settings.copyWith(highContrast: v)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
