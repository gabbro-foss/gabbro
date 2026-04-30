import 'package:flutter/material.dart';
import 'package:gabbro/settings.dart';

class SecurityScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onUpdate;

  const SecurityScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(AppSettings updated) {
    widget.onUpdate(updated);
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Foreground lock ────────────────────────────────────────
              _SectionHeader(label: 'Foreground lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after this much inactivity while the app is open.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              _SegmentedRow<ForegroundLockTimeout>(
                values: ForegroundLockTimeout.values,
                selected: _settings.foregroundLockTimeout,
                label: (v) => switch (v) {
                  ForegroundLockTimeout.thirtySeconds => '30s',
                  ForegroundLockTimeout.oneMinute => '1 min',
                  ForegroundLockTimeout.fiveMinutes => '5 min',
                  ForegroundLockTimeout.never => 'Never',
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(foregroundLockTimeout: v)),
              ),
              const SizedBox(height: 32),

              // ── Background lock ────────────────────────────────────────
              _SectionHeader(label: 'Background lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after the app has been in the background for this long.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              _SegmentedRow<BackgroundLockTimeout>(
                values: BackgroundLockTimeout.values,
                selected: _settings.backgroundLockTimeout,
                label: (v) => switch (v) {
                  BackgroundLockTimeout.oneMinute => '1 min',
                  BackgroundLockTimeout.fiveMinutes => '5 min',
                  BackgroundLockTimeout.fifteenMinutes => '15 min',
                  BackgroundLockTimeout.never => 'Never',
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(backgroundLockTimeout: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

// ── Generic segmented row ─────────────────────────────────────────────────────

class _SegmentedRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelected;

  const _SegmentedRow({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: values.map((v) {
        final isSelected = v == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
              onPressed: () => onSelected(v),
              child: Text(label(v)),
            ),
          ),
        );
      }).toList(),
    );
  }
}