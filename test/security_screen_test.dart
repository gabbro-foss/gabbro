import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/segmented_row.dart';

Widget _buildScreen({
  AppSettings settings = const AppSettings(),
  void Function(AppSettings)? onUpdate,
  bool isAndroid = false,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  Future<bool> Function()? onBiometricAvailable,
  Future<void> Function(List<int>, String)? onBiometricEnroll,
  Future<void> Function(String)? onBiometricUnenroll,
  String? vaultPath,
}) => testApp(SecurityScreen(
  settings: settings,
  onUpdate: onUpdate ?? (_) {},
  isAndroid: isAndroid,
  vaultPath: vaultPath,
  onBiometricIsEnrolled: onBiometricIsEnrolled ?? (_) async => false,
  onBiometricAvailable: onBiometricAvailable ?? () async => false,
  onBiometricEnroll: onBiometricEnroll ?? (_, _) async {},
  onBiometricUnenroll: onBiometricUnenroll ?? (_) async {},
));

void main() {
  group('SecurityScreen', () {
    testWidgets('renders foreground and background timeout section headers', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Foreground lock'), findsOneWidget);
      expect(find.text('Background lock'), findsOneWidget);
    });

    testWidgets('foreground timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('30s'), findsAtLeastNWidgets(1));
      expect(find.text('1 min'), findsAtLeastNWidgets(1));
      expect(find.text('5 min'), findsAtLeastNWidgets(1));
      expect(find.text('Never'), findsAtLeastNWidgets(1));
    });

    testWidgets('background timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('15 min'), findsOneWidget);
    });

    testWidgets('tapping a foreground button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.text('Never').first);
      await tester.pumpAndSettle();
      expect(updated?.foregroundLockTimeout, ForegroundLockTimeout.never);
    });

    testWidgets('tapping a background button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(updated?.backgroundLockTimeout, BackgroundLockTimeout.fifteenMinutes);
    });

    testWidgets('SegmentedRow uses Wrap not Row', (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: SegmentedRow<ForegroundLockTimeout>(
            values: ForegroundLockTimeout.values,
            selected: ForegroundLockTimeout.thirtySeconds,
            label: (v) => v.name,
            onSelected: (_) {},
          ),
        )),
      );
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('clipboard clear timeout section header is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Clipboard clear'), findsOneWidget);
    });

    testWidgets('clipboard clear timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('30s'), findsAtLeastNWidgets(1));
      expect(find.text('60s'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
    });

    testWidgets('tapping a clipboard clear button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.scrollUntilVisible(find.text('2 min'), 100);
      await tester.tap(find.text('2 min'));
      await tester.pumpAndSettle();
      expect(updated?.clipboardClearTimeout, ClipboardClearTimeout.twoMinutes);
    });

    testWidgets('block passphrase copy/paste section header is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Passphrase copy/paste'), findsOneWidget);
    });

    testWidgets('block passphrase copy/paste toggle is on by default', (tester) async {
      await tester.pumpWidget(_buildScreen());
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Block copy/paste'),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('tapping passphrase copy/paste toggle calls onUpdate with false', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block copy/paste'));
      await tester.pumpAndSettle();
      expect(updated?.blockPassphraseCopyPaste, isFalse);
    });

    testWidgets('selected foreground button reflects current settings', (tester) async {
      await tester.pumpWidget(_buildScreen(
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.oneMinute,
        ),
      ));
      // The screen receives the setting — no exception thrown, renders cleanly.
      expect(find.text('1 min'), findsAtLeastNWidgets(1));
    });
  });

  // ── biometricUnlock ───────────────────────────────────────────────────────

  group('biometricUnlock', () {
    testWidgets('biometric section hidden when isAndroid is false', (tester) async {
      await tester.pumpWidget(_buildScreen(isAndroid: false));
      expect(find.text('Biometric unlock'), findsNothing);
    });

    testWidgets('biometric section shown when isAndroid is true', (tester) async {
      await tester.pumpWidget(_buildScreen(isAndroid: true));
      await tester.scrollUntilVisible(find.text('Biometric unlock'), 300);
      expect(find.text('Biometric unlock'), findsOneWidget);
    });

    testWidgets('biometric toggle is off by default', (tester) async {
      await tester.pumpWidget(_buildScreen(isAndroid: true));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('biometric toggle ON when isEnrolled returns true for this vault', (tester) async {
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        vaultPath: '/vault/a.gabbro',
        onBiometricIsEnrolled: (_) async => true,
      ));
      await tester.pump(); // allow initState async to settle
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('biometric toggle OFF when isEnrolled returns false', (tester) async {
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        vaultPath: '/vault/b.gabbro',
        onBiometricIsEnrolled: (_) async => false,
      ));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('tapping toggle OFF calls unenroll with this vault path', (tester) async {
      String? unenrolledPath;
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        vaultPath: '/vault/a.gabbro',
        onBiometricIsEnrolled: (_) async => true,
        onBiometricUnenroll: (path) async { unenrolledPath = path; },
      ));
      await tester.pump(); // let initState isEnrolled resolve
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      expect(unenrolledPath, '/vault/a.gabbro');
    });

    testWidgets('tapping toggle ON when unavailable shows error and does not update setting',
        (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onUpdate: (s) => updated = s,
        onBiometricAvailable: () async => false,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      expect(updated, isNull);
      expect(find.text('Biometric unlock is not available on this device.'
          ' No biometric sensor was found or no biometrics are enrolled in system settings.'),
          findsOneWidget);
    });

    testWidgets('tapping toggle ON when available shows explanation dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onBiometricAvailable: () async => true,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      expect(find.text('About biometric unlock'), findsOneWidget);
    });

    testWidgets('cancelling explanation dialog does not update setting', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onUpdate: (s) => updated = s,
        onBiometricAvailable: () async => true,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(updated, isNull);
    });

    // Net: a failed enrolment must tell the user why, and the toggle stays
    // off. Pins the message text, not its container.
    testWidgets('a failed enrolment shows the failure message', (tester) async {
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        vaultPath: '/vault/a.gabbro',
        onBiometricAvailable: () async => true,
        onBiometricEnroll: (_, _) async => throw Exception('boom'),
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'pass');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't enable biometric unlock: Exception: boom"),
        findsOneWidget,
      );
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'),
      );
      expect(tile.value, isFalse, reason: 'failed enrolment stays off');
    });

    // Red (SnackBar clip): the failure explanation must be fully readable in
    // the worst supported case - largest reachable text, narrowest phone, a
    // plausible long platform error. A SnackBar clips it with no scroll.
    testWidgets(
        'a failed enrolment message is fully reachable at 2x on a 360dp phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = kPhoneMaxScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      const longError =
          'PlatformException(enroll-failed, Unable to establish connection '
          'on channel app.gabbro.gabbro/biometric: the platform thread has '
          'shut down unexpectedly while waiting for the sensor, null, null)';
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        vaultPath: '/vault/a.gabbro',
        onBiometricAvailable: () async => true,
        onBiometricEnroll: (_, _) async => throw Exception(longError),
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      // Drive the dialog buttons directly: at 2x they can sit off-screen and
      // a centre-tap misses (harness artifact; tappability is pinned at 1x).
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'pass');
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed!();
      await tester.pumpAndSettle();

      final message = find.textContaining("Couldn't enable biometric unlock:");
      expect(messageIsReachable(tester, message), isTrue,
          reason: 'the failure explanation must be fully readable at 2x');
    });

    // ADR-016 reveal-eye: the enroll passphrase dialog eye scales (capped) at
    // large text and the dialog does not overflow.
    testWidgets('enroll passphrase dialog eye scales (capped) at large text',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onBiometricAvailable: () async => true,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      // At 2x the dialog is taller than the screen, so its buttons sit below
      // the fold and scroll into reach (see gabbro_dialog_test.dart).
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(revealEyeButtons(), findsNWidgets(1));
      final eye = tester.widget<IconButton>(revealEyeButtons().first);
      expect(eye.iconSize, isNotNull);
      expect(eye.iconSize, greaterThan(24));
      expect(eye.iconSize, lessThanOrEqualTo(24 * 1.4));
      expect(tester.takeException(), isNull);
    });

    // Net-first: pin the passphrase eye toggle in the enroll passphrase dialog
    // (switch on -> Continue -> passphrase prompt) so the later a11y label work
    // cannot regress the flip. Field starts obscured (Icons.visibility_off).
    testWidgets('enroll passphrase dialog eye toggle flips', (tester) async {
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onBiometricAvailable: () async => true,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });

    // A11y: the passphrase eye toggle in the enroll dialog must carry a semantic
    // label so screen readers announce it, not a bare "button".
    testWidgets('enroll passphrase dialog meets labelled-tap-target guideline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onBiometricAvailable: () async => true,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('Enter in the enroll passphrase dialog confirms enrollment',
        (tester) async {
      List<int>? enrolled;
      await tester.pumpWidget(_buildScreen(
        isAndroid: true,
        onBiometricAvailable: () async => true,
        onBiometricEnroll: (pass, _) async => enrolled = pass,
      ));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'), 300);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable biometric unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mypass');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(enrolled, 'mypass'.codeUnits);
    });
  });

  // ── Vault list section removed (ADR-014) ──────────────────────────────────

  group('Vault list section removed (ADR-014)', () {
    testWidgets('no Vault list section is rendered', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Vault list'), findsNothing);
      expect(
        find.widgetWithText(SwitchListTile, 'Show vault list on login'),
        findsNothing,
      );
    });
  });
}