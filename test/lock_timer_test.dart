// Tests for foreground and background lock behaviour in GabbroApp.
//
// Background lock uses a timestamp-on-background / check-on-resume strategy
// rather than a timer, so tests advance a fake clock injected via
// GabbroApp.clock rather than pumping time while the app is in background.
//
// Frames caveat: hidden/paused/detached call Flutter's _setFramesEnabled(false).
// Tests that assert on the widget tree after a background-triggered lock must
// send AppLifecycleState.resumed first (re-enables frames), then call
// pump() to consume hasScheduledFrame before pump(duration) runs the animation.

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
  DateTime Function()? clock,
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
    clock: clock ?? DateTime.now,
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

      await tester.pump(const Duration(seconds: 31));
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

      await tester.pump(const Duration(seconds: 25));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      // 10 s since the key press — must NOT lock.
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

      await tester.tap(find.text('InitialScreen'));
      await tester.pump();

      // 10 s since tap — must NOT lock.
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

      await tester.pump(const Duration(minutes: 10));
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget);
    });
  });

  group('background lock', () {
    late String vaultPath;
    late Future<void> Function() cleanup;

    setUp(() async {
      (vaultPath, cleanup) = await _makeTempVault();
    });

    tearDown(() async => cleanup());

    // Helper: build app with a manually-controlled clock.
    // Returns (widget, advance) where advance(d) moves the clock forward by d.
    (Widget, void Function(Duration)) buildWithFakeClock({
      required String path,
      required BackgroundLockTimeout backgroundTimeout,
    }) {
      var now = DateTime(2025);
      return (
        _buildApp(
          vaultPath: path,
          settings: AppSettings(
            foregroundLockTimeout: ForegroundLockTimeout.never,
            backgroundLockTimeout: backgroundTimeout,
          ),
          clock: () => now,
        ),
        (Duration d) => now = now.add(d),
      );
    }

    testWidgets('hidden lifecycle locks after background timeout', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);
      expect(find.text('InitialScreen'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      // Advance the fake clock past the threshold.
      advance(const Duration(minutes: 1, seconds: 1));

      // resumed checks elapsed time, calls _lock(), re-enables frames.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('paused lifecycle locks after background timeout', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      advance(const Duration(minutes: 1, seconds: 1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    // Android fires hidden then paused. The ??= means the earliest timestamp
    // (from hidden) is kept. Verify lock still fires after the timeout.
    testWidgets('hidden then paused sequence locks after timeout', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      advance(const Duration(minutes: 1, seconds: 1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('resumed before timeout does not lock', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      // Only 30 s — under the threshold.
      advance(const Duration(seconds: 30));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('InitialScreen'), findsOneWidget);
    });

    // The ??= guard means a second lifecycle event (paused) does not reset the
    // backgroundedAt timestamp recorded by the first (hidden). Verify that
    // resuming after a short background clears the timestamp so a subsequent
    // background session is measured independently.
    testWidgets('backgroundedAt clears on resume, second session measured fresh',
        (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);

      // First background session — 30 s (under threshold).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      advance(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget); // no lock

      // Second background session — also 30 s (not cumulative).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      advance(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('InitialScreen'), findsOneWidget); // still no lock
    });

    // On Linux, workspace switching fires inactive (not hidden/paused).
    // These two tests verify the inactive path; they rely on Platform.isLinux
    // being true in the test environment (Linux dev/CI machine).
    testWidgets('inactive on desktop locks after background timeout', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);
      expect(find.text('InitialScreen'), findsOneWidget);

      // Simulate Qtile workspace switch.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      advance(const Duration(minutes: 1, seconds: 1));

      // User switches back: resumed checks elapsed and locks.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('brief inactive on desktop does not lock', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.oneMinute,
      );
      await tester.pumpWidget(app);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      // Only 30 s away — under the 1-minute threshold.
      advance(const Duration(seconds: 30));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('InitialScreen'), findsOneWidget);
    });

    // Floating WM (X11 or Wayland): minimize fires inactive then hidden.
    // The Timer started on inactive must survive the hidden transition and fire.
    // Frames are disabled after hidden, so resumed is needed to render the result.
    testWidgets('inactive then hidden (floating WM minimize) fires timer while minimized',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.never,
          backgroundLockTimeout: BackgroundLockTimeout.oneMinute,
        ),
      ));
      expect(find.text('InitialScreen'), findsOneWidget);

      // Focus lost, then window minimized.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      // Timer from inactive fires (frames are disabled; _lock() queues navigation).
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      // resumed re-enables frames; _backgroundedAt was cleared by _lock() so no
      // double-lock — just renders the already-queued navigation.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    // When the app stays visible but loses focus (tiling WM, another window
    // active on the same workspace), resumed never fires during the background
    // period. A real Timer is started on inactive so the lock fires in-place.
    testWidgets('inactive on desktop fires timer while app stays visible', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.never,
          backgroundLockTimeout: BackgroundLockTimeout.oneMinute,
        ),
      ));
      expect(find.text('InitialScreen'), findsOneWidget);

      // Focus lost; app still visible — no resumed follows during background.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      // Advance past the timeout; the background timer fires directly.
      // (inactive does not disable frames, so no resumed trick needed.)
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('detached state locks immediately', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.never,
          backgroundLockTimeout: BackgroundLockTimeout.never,
        ),
      ));
      expect(find.text('InitialScreen'), findsOneWidget);

      // detached calls _lock() synchronously; resumed re-enables frames.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('background lock never fires when timeout is never', (tester) async {
      final (app, advance) = buildWithFakeClock(
        path: vaultPath,
        backgroundTimeout: BackgroundLockTimeout.never,
      );
      await tester.pumpWidget(app);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      advance(const Duration(hours: 24));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('InitialScreen'), findsOneWidget);
    });

    testWidgets('resumed after hidden restarts foreground timer', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
          backgroundLockTimeout: BackgroundLockTimeout.never,
        ),
      ));

      // Go to background and immediately come back (under threshold — no lock).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // 25 s since resume — must NOT lock (30 s threshold).
      await tester.pump(const Duration(seconds: 25));
      expect(find.text('InitialScreen'), findsOneWidget);

      // 6 s more (31 s since resume) — MUST lock.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });
  });

  group('foreground lock suspension', () {
    late String vaultPath;
    late Future<void> Function() cleanup;

    setUp(() async {
      (vaultPath, cleanup) = await _makeTempVault();
    });

    tearDown(() async => cleanup());

    testWidgets('suspendForegroundLock prevents lock while suspended', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
        ),
      ));

      final appState =
          GabbroApp.maybeOf(tester.element(find.text('InitialScreen')));
      appState!.suspendForegroundLock();

      await tester.pump(const Duration(minutes: 2));
      await tester.pump();

      expect(find.text('InitialScreen'), findsOneWidget);
    });

    testWidgets('resumeForegroundLock restarts the timer', (tester) async {
      await tester.pumpWidget(_buildApp(
        vaultPath: vaultPath,
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.thirtySeconds,
        ),
      ));

      final appState =
          GabbroApp.maybeOf(tester.element(find.text('InitialScreen')));
      appState!.suspendForegroundLock();

      // Well past the normal threshold — still suspended.
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('InitialScreen'), findsOneWidget);

      appState.resumeForegroundLock();
      await tester.pump();

      // 25 s after resume — must NOT lock yet.
      await tester.pump(const Duration(seconds: 25));
      expect(find.text('InitialScreen'), findsOneWidget);

      // 6 s more (31 s after resume) — MUST lock.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });
  });
}
