import 'package:flutter/material.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/widgets/segmented_row.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late AppSettings _settings;

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
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Theme ──────────────────────────────────────────────────
              SectionHeader(label: 'Theme'),
              const SizedBox(height: 8),
              SegmentedRow<ThemeChoice>(
                values: ThemeChoice.values,
                selected: _settings.theme,
                label: (v) => switch (v) {
                  ThemeChoice.system => 'System',
                  ThemeChoice.light => 'Light',
                  ThemeChoice.dark => 'Dark',
                },
                onSelected: (v) => _update(_settings.copyWith(theme: v)),
              ),
              const SizedBox(height: 32),

              // ── Text size ──────────────────────────────────────────────
              SectionHeader(label: 'Text size'),
              const SizedBox(height: 8),
              SegmentedRow<TextSizeChoice>(
                values: TextSizeChoice.values,
                selected: _settings.textSize,
                label: (v) => switch (v) {
                  TextSizeChoice.small => 'Small',
                  TextSizeChoice.regular => 'Regular',
                  TextSizeChoice.large => 'Large',
                  TextSizeChoice.extraLarge => 'XL',
                  TextSizeChoice.xxLarge => 'XXL',
                },
                onSelected: (v) => _update(_settings.copyWith(textSize: v)),
              ),
              const SizedBox(height: 12),
              // Live preview so the user can see the effect immediately.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Gabbro is an intrusive igneous rock that is  Mg- and Fe-rich and coarse-grained.',
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 32),

              // ── High contrast ──────────────────────────────────────────
              SectionHeader(label: 'Accessibility'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('High contrast'),
                subtitle: const Text(
                  'Increases contrast for better readability',
                ),
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
