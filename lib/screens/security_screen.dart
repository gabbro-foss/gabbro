import 'package:flutter/material.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/widgets/segmented_row.dart';

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
              SectionHeader(label: 'Foreground lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after this much inactivity while the app is open.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<ForegroundLockTimeout>(
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
              SectionHeader(label: 'Background lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after the app has been in the background for this long.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<BackgroundLockTimeout>(
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
