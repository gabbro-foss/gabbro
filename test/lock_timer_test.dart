// Tests for foreground lock timer behaviour in GabbroApp.
//
// Background lock (AppLifecycleState.hidden / paused) disables Flutter's
// rendering loop, making full navigation assertions unreliable in widget tests.
// The hidden-lifecycle fix is verified manually / via hardware test per
// CLAUDE.md ("Hardware tests are valid TDD").

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

// Sentinel widget shown before the vault locks.
class _InitialScreen extends StatelessWidget {
  const _InitialScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('InitialScreen')));
}

Widget _buildApp({
  required String vaultPath,
  AppSettings settings = const AppSettings(),
}) {
  final registry = VaultRegistry([
    VaultRecord(
      path: vaultPath,
      alias: 'Lock Test',
      lastUsedAt: DateTime.now(),
    ),
  ]);
  return GabbroApp(
    registry: registry,
    vaultPath: vaultPath,
    settings: settings,
    initialScreen: const _InitialScreen(),
  );
}

Future<(String, Future<void> Function())> _makeTempVault() async {
  final dir = await Directory.systemTemp.createTemp('gabbro_lock_test_');
  final file = File('${dir.path}/vault.gabbro');
  await file.create();
  return (file.path, () => dir.delete(recursive: true));
}

void main() {
  group('foreground lock', () {
    late String vaultPath;
    late Future<void> Function() cleanup;

    setUp(() async {
      (vaultPath, cleanup) = await _makeTempVault();
    });

    tearDown(() async => cleanup());

    testWidgets('timer fires after timeout with no activity', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
        ),
      ));

      expect(find.text('InitialScreen'), findsOneWidget);

      // Advance past the 30 s threshold.
      await tester.pump(const Duration(seconds: 31));
      // Give the Material page transition time to complete (~300 ms).
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('key press resets foreground timer', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
        ),
      ));

      // Advance 25 s — 5 s remaining before lock.
      await tester.pump(const Duration(seconds: 25));

      // Key press should restart the 30 s window.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      // Only 10 s since the key press — must NOT lock.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget);

      // 25 more seconds (35 s since key press) — MUST lock.
      await tester.pump(const Duration(seconds: 25));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('pointer tap resets foreground timer', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
        ),
      ));

      await tester.pump(const Duration(seconds: 25));

      // Tap anywhere — timer should restart.
      await tester.tap(find.text('InitialScreen'));
      await tester.pump();

      // Only 10 s since tap — must NOT lock.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget);
    });

    testWidgets('lock never fires when timeout is set to never', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.never,
        ),
      ));

      // Advance well past any reasonable timeout.
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget);
    });
  });
}
