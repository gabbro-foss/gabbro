import 'package:flutter/material.dart';
import 'package:gabbro/widgets/generator_widget.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';

class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final timeout = GabbroApp.maybeOf(context)?.settings.clipboardClearTimeout
        ?? ClipboardClearTimeout.sixtySeconds;
    final duration = switch (timeout) {
      ClipboardClearTimeout.never         => const Duration(hours: 24),
      ClipboardClearTimeout.thirtySeconds => const Duration(seconds: 30),
      ClipboardClearTimeout.sixtySeconds  => const Duration(seconds: 60),
      ClipboardClearTimeout.twoMinutes    => const Duration(minutes: 2),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Password generator')),
      body: GeneratorWidget(clipboardClearDuration: duration),
    );
  }
}
