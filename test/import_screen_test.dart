import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

/// Scrolls to [sectionTitle], then taps the FilledButton in that section.
Future<void> _tapImportForSection(
    WidgetTester tester, String sectionTitle) async {
  await tester.scrollUntilVisible(
    find.text(sectionTitle),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  final col = find
      .ancestor(of: find.text(sectionTitle), matching: find.byType(Column))
      .first;
  final btn = find.descendant(of: col, matching: find.byType(FilledButton));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pump();
}

void main() {
  group('ImportScreen', () {
    Widget buildScreen({
      Future<ImportResult> Function(List<int>)? onImportEnpass,
      Future<ImportResult> Function(List<int>)? onImportBitwarden,
      Future<ImportResult> Function(List<int>)? onImportGooglePm,
      Future<ImportResult> Function(List<int>)? onImportDashlane,
      CsvPreviewData Function(String)? onSniffCsv,
    }) {
      return testApp(ImportScreen(
        onImportEnpass: onImportEnpass ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportBitwarden: onImportBitwarden ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportGooglePm: onImportGooglePm ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportDashlane: onImportDashlane ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onSniffCsv: onSniffCsv ?? (_) => CsvPreviewData(headers: [], rows: []),
      ));
    }

    testWidgets('shows duplicate warning banner', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(
        find.textContaining('Entries whose UUID already exists'),
        findsOneWidget,
      );
    });

    testWidgets('skipped dialog shows entry title and reason', (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showSkippedEntriesDialog(
            context,
            [
              SkippedEntryData(
                title: 'Dupe Entry',
                reason: 'UUID already exists',
              ),
            ],
          ),
          child: const Text('show'),
        ),
      )));
      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Dupe Entry'), findsOneWidget);
      expect(find.textContaining('UUID already exists'), findsOneWidget);
    });

    testWidgets('skipped dialog shows correct entry count in title',
        (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showSkippedEntriesDialog(
            context,
            [
              SkippedEntryData(title: 'Entry A', reason: 'UUID already exists'),
              SkippedEntryData(title: 'Entry B', reason: 'UUID already exists'),
            ],
          ),
          child: const Text('show'),
        ),
      )));
      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('2 entries skipped'), findsOneWidget);
    });

    testWidgets('warning banner has warning icon', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows Gabbro vault section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Gabbro vault'));
      expect(find.text('Gabbro vault'), findsOneWidget);
    });

    testWidgets('shows passphrase field in Gabbro section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Vault passphrase'));
      expect(find.text('Vault passphrase'), findsOneWidget);
    });

    testWidgets('shows error when Gabbro import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Sync from vault'));
      await tester.tap(find.text('Sync from vault'));
      await tester.pump();
      expect(find.text('Select a file.'), findsOneWidget);
    });

    // ── ADR-013: key-protected source sync ───────────────────────────────────

    YubikeyRecordData fakeRecord() => YubikeyRecordData(
          credentialId: Uint8List.fromList([1, 2]),
          salt: Uint8List.fromList([3, 4]),
        );

    File tempGabbroFile() {
      final f = File(
          '${Directory.systemTemp.path}/gabbro_kp_${DateTime.now().microsecondsSinceEpoch}.gabbro')
        ..writeAsStringSync('x');
      addTearDown(() {
        if (f.existsSync()) f.deleteSync();
      });
      return f;
    }

    testWidgets('key-protected source shows YubiKey PIN field and info note',
        (tester) async {
      final tmp = tempGabbroFile();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
      )));
      await tester.ensureVisible(find.text('YubiKey PIN'));
      expect(find.text('YubiKey PIN'), findsOneWidget);
      expect(find.textContaining('protected by a YubiKey'), findsOneWidget);
    });

    // ADR-016 reveal-eye: the vault-passphrase + YubiKey-PIN eyes scale (capped)
    // at large text and the screen does not overflow.
    testWidgets('key-protected source eyes scale (capped) at large text',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final tmp = tempGabbroFile();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
      )));
      await tester.pumpAndSettle();

      expect(revealEyeButtons(), findsNWidgets(2));
      for (final eye in tester.widgetList<IconButton>(revealEyeButtons())) {
        expect(eye.iconSize, isNotNull);
        expect(eye.iconSize, greaterThan(24));
        expect(eye.iconSize, lessThanOrEqualTo(24 * 1.4));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('transport selector follows NFC capability (Android, key-protected)',
        (tester) async {
      final tmp = tempGabbroFile();
      addTearDown(() => nfcAvailable = false);

      // No NFC hardware: the USB/NFC selector is not offered.
      nfcAvailable = false;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: true,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
      )));
      await tester.pumpAndSettle();
      expect(find.text('NFC'), findsNothing);

      // NFC present: the selector appears.
      nfcAvailable = true;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: true,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
      )));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('NFC'));
      expect(find.text('NFC'), findsOneWidget);
    });

    testWidgets('passphrase-only source shows no YubiKey fields', (tester) async {
      final tmp = tempGabbroFile();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [],
      )));
      await tester.ensureVisible(find.text('Sync from vault'));
      expect(find.text('YubiKey PIN'), findsNothing);
      expect(find.textContaining('protected by a YubiKey'), findsNothing);
    });

    testWidgets('key-protected source routes Sync to import-with-key',
        (tester) async {
      final tmp = tempGabbroFile();
      String? keyPath;
      List<int>? keyHmac;
      List<int>? keyCred;
      String? tapPin;
      var plainCalled = false;

      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
        onGetYubikeyHmac: (records, pin, transport) async {
          tapPin = pin;
          return (hmac: <int>[9, 9, 9], credentialId: <int>[1, 2]);
        },
        onImportGabbroWithKey: (path, pass, hmac, cred) async {
          keyPath = path;
          keyHmac = hmac;
          keyCred = cred;
          return GabbroImportResult(imported: BigInt.one, skipped: []);
        },
        onImportGabbro: (_, _) async {
          plainCalled = true;
          return GabbroImportResult(imported: BigInt.zero, skipped: []);
        },
      )));

      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.enterText(
          find.widgetWithText(TextField, 'YubiKey PIN'), '1234');
      await tester.ensureVisible(find.text('Sync from vault'));
      await tester.tap(find.text('Sync from vault'));
      await tester.pump();
      await tester.pump();

      expect(keyPath, tmp.path);
      expect(keyHmac, [9, 9, 9]);
      expect(keyCred, [1, 2]);
      expect(tapPin, '1234');
      expect(plainCalled, isFalse);
    });

    testWidgets('key-protected sync shows tap-now prompt while awaiting the key',
        (tester) async {
      final tmp = tempGabbroFile();
      final gate = Completer<YubikeyHmacMatch>();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
        onGetYubikeyHmac: (_, _, _) => gate.future,
        onImportGabbroWithKey: (_, _, _, _) async =>
            GabbroImportResult(imported: BigInt.one, skipped: []),
      )));

      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.enterText(
          find.widgetWithText(TextField, 'YubiKey PIN'), '1234');
      await tester.ensureVisible(find.text('Sync from vault'));
      await tester.tap(find.text('Sync from vault'));
      await tester.pump(); // kick off the async; tap is now pending

      expect(find.text('Tap your YubiKey now…'), findsOneWidget);

      // Let the pending tap resolve so no timer is left dangling.
      gate.complete((hmac: <int>[1], credentialId: <int>[1, 2]));
      await tester.pump();
      await tester.pump();
    });

    // ── Enter-submit / focus chain (Gabbro source) ───────────────────────────
    testWidgets('Enter on the passphrase runs the import (passphrase-only source)',
        (tester) async {
      final tmp = tempGabbroFile();
      var plainCalled = false;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [],
        onImportGabbro: (_, _) async {
          plainCalled = true;
          return GabbroImportResult(imported: BigInt.zero, skipped: []);
        },
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(plainCalled, isTrue);
    });

    testWidgets('Enter on the passphrase advances to the PIN (key-protected source)',
        (tester) async {
      final tmp = tempGabbroFile();
      var hmacCalled = false;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
        onGetYubikeyHmac: (_, _, _) async {
          hmacCalled = true;
          return (hmac: <int>[1], credentialId: <int>[1, 2]);
        },
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(hmacCalled, isFalse, reason: 'must not submit before the PIN');
      final pin =
          tester.widget<TextField>(find.widgetWithText(TextField, 'YubiKey PIN'));
      expect(pin.focusNode?.hasFocus, isTrue);
    });

    testWidgets('Enter on the PIN runs the key-protected import', (tester) async {
      final tmp = tempGabbroFile();
      var tapPin = '';
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
        onGetYubikeyHmac: (records, pin, transport) async {
          tapPin = pin;
          return (hmac: <int>[9], credentialId: <int>[1, 2]);
        },
        onImportGabbroWithKey: (_, _, _, _) async =>
            GabbroImportResult(imported: BigInt.one, skipped: []),
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.enterText(
          find.widgetWithText(TextField, 'YubiKey PIN'), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(tapPin, '1234');
    });

    // ── Import failure (net pins) ────────────────────────────────────────────
    // The catch at import_screen.dart:379 had no coverage at all, which is how
    // the raw-Rust-error defect (matrix 4.2 / 4.4) shipped. These pin what the
    // failure path does TODAY, before it is changed.

    // The refusal a pre-v11 vault produces, as the bridge surfaces it.
    const versionRefusal =
        'file version not supported: v10 (this build opens v11 and later) - '
        'https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md';

    Widget failingGabbroImport(Object error) => testApp(ImportScreen(
          isAndroid: false,
          initialGabbroPath: tempGabbroFile().path,
          onDetectSourceRecords: (_) => [],
          onImportGabbro: (_, _) async => throw error,
        ));

    Future<void> runFailingImport(WidgetTester tester, Object error) async {
      await tester.pumpWidget(failingGabbroImport(error));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('N1 a failed Gabbro import shows the error and stays on screen',
        (tester) async {
      await runFailingImport(tester, Exception(versionRefusal));

      expect(find.textContaining('file version not supported'), findsOneWidget);
      // Still on the import screen: a failure must not pop as a success does.
      expect(find.text('Sync from vault'), findsOneWidget);
    });

    testWidgets('N2 the spinner clears after a failed Gabbro import',
        (tester) async {
      await runFailingImport(tester, Exception(versionRefusal));

      // The finally block must re-enable the button, or the user is stranded
      // with a dead screen after one bad file.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Sync from vault'));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('N3 choosing another file clears the previous import error',
        (tester) async {
      await runFailingImport(tester, Exception(versionRefusal));
      expect(find.textContaining('file version not supported'), findsOneWidget);

      // PathField's onChanged is what clears it (import_screen.dart:567); the
      // Gabbro one is identified by its hint, several importers have a field.
      final other = tempGabbroFile();
      final gabbroPathField = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is PathField && w.hint == '/home/user/vault.gabbro'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(gabbroPathField, other.path);
      await tester.pump();

      expect(find.textContaining('file version not supported'), findsNothing);
    });

    testWidgets('N4 the passphrase survives a failed import so retry works',
        (tester) async {
      await runFailingImport(tester, Exception(versionRefusal));

      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Vault passphrase'));
      expect(field.controller?.text, 'pw');
    });

    // ── A pre-v11 source is explained, not dumped as a raw error ─────────────
    // Matrix 4.2 / 4.4. Reuses the unlock screen's strings so both refusals read
    // the same and are already translated. Neither carries a format version
    // number: "v10" means nothing to a user (Bikeshed), so the assertions below
    // must never depend on one.

    const tooOldMessage =
        'This vault uses an older format that this version of Gabbro cannot '
        'open. Your vault file has not been changed.';
    const upgradeLinkLabel = 'How to upgrade this vault';
    const upgradeUrl =
        'https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md';
    const tooNewMessage =
        'This vault was created by a newer version of Gabbro. Update Gabbro to '
        'open it. Your vault file has not been changed.';
    const updateLinkLabel = 'How to update Gabbro';

    Future<void> runImportOfOldSource(
      WidgetTester tester, {
      required bool tooOld,
      Object? error,
    }) async {
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tempGabbroFile().path,
        onDetectSourceRecords: (_) => [],
        onSourceFormatTooOld: (_) async => tooOld,
        onImportGabbro: (_, _) async =>
            throw error ?? Exception(versionRefusal),
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a pre-v11 source explains the format, not the raw Rust error',
        (tester) async {
      await runImportOfOldSource(tester, tooOld: true);

      expect(find.textContaining(tooOldMessage), findsOneWidget);
      expect(find.textContaining('file version not supported'), findsNothing);
    });

    testWidgets('a pre-v11 source offers a tappable link to the upgrade steps',
        (tester) async {
      await runImportOfOldSource(tester, tooOld: true);

      expect(find.text(upgradeLinkLabel), findsOneWidget);
    });

    testWidgets('a too-new source explains "update Gabbro", not the raw error',
        (tester) async {
      // A source from a newer build refuses here too; it is intact, so explain
      // the format and offer the update link instead of dumping the Rust text.
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tempGabbroFile().path,
        onDetectSourceRecords: (_) => [],
        onSourceFormatTooOld: (_) async => false,
        onSourceFormatTooNew: (_) async => true,
        onImportGabbro: (_, _) async => throw Exception(versionRefusal),
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(tooNewMessage), findsOneWidget);
      expect(find.textContaining('file version not supported'), findsNothing);
      expect(find.text(updateLinkLabel), findsOneWidget);
    });

    testWidgets('a generic import failure shows a localized "Import failed:"',
        (tester) async {
      // Not too-old/too-new: a wrong passphrase or damaged source. The localized
      // frame carries the meaning; the raw Rust detail is kept as trailing text
      // (English on purpose, for bug reports) instead of standing alone.
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tempGabbroFile().path,
        onDetectSourceRecords: (_) => [],
        onSourceFormatTooOld: (_) async => false,
        onSourceFormatTooNew: (_) async => false,
        onImportGabbro: (_, _) async => throw Exception('decryption failed'),
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Import failed:'), findsOneWidget);
      expect(find.textContaining('decryption failed'), findsOneWidget);
    });

    testWidgets('tapping the upgrade link shows the URL before the browser',
        (tester) async {
      await runImportOfOldSource(tester, tooOld: true);

      await tester.tap(find.text(upgradeLinkLabel));
      await tester.pumpAndSettle();

      // Same convention as url_link.dart: the user sees where they are going.
      expect(find.text(upgradeUrl), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
    });

    testWidgets('a wrong passphrase on a current source keeps its own error',
        (tester) async {
      await runImportOfOldSource(
        tester,
        tooOld: false,
        error: Exception('wrong passphrase'),
      );

      expect(find.textContaining('wrong passphrase'), findsOneWidget);
      expect(find.textContaining(tooOldMessage), findsNothing);
    });

    testWidgets('a corrupt source keeps its own error, never the format one',
        (tester) async {
      await runImportOfOldSource(
        tester,
        tooOld: false,
        error: Exception('not a Gabbro vault'),
      );

      expect(find.textContaining('not a Gabbro vault'), findsOneWidget);
      expect(find.textContaining(tooOldMessage), findsNothing);
    });

    // ── The too-old refusal under l10n + accessibility ───────────────────────
    // The strings are reused and already translated, but this screen's LAYOUT
    // with them is new. The worst case is the longest translation at the largest
    // scale on the narrowest screen, together — testing them separately never
    // meets it.

    Widget importShell({
      Locale? locale,
      TextScaler? textScaler,
      ThemeMode mode = ThemeMode.light,
      bool highContrast = false,
    }) =>
        MaterialApp(
          // The app's own delegate list, not the raw generated one: it wraps
          // Material/Cupertino so nn and yo fall back to English instead of
          // throwing. A sweep on the raw list tests a shell the app never uses.
          localizationsDelegates: gabbroLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          themeMode: mode,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: textScaler ?? TextScaler.noScaling,
              highContrast: highContrast,
            ),
            child: ImportScreen(
              isAndroid: false,
              initialGabbroPath: tempGabbroFile().path,
              onDetectSourceRecords: (_) => [],
              onSourceFormatTooOld: (_) async => true,
              onImportGabbro: (_, _) async => throw Exception(versionRefusal),
            ),
          ),
        );

    Future<void> showRefusal(WidgetTester tester, Widget shell) async {
      await tester.pumpWidget(shell);
      // Matched by shape, not by label: the sweep runs in 37 locales, so any
      // English finder would fail on the first translated one. With no
      // key-protected source the vault passphrase is the only obscured field.
      final passphrase =
          find.byWidgetPredicate((w) => w is TextField && w.obscureText);
      expect(passphrase, findsOneWidget);
      await tester.enterText(passphrase, 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the too-old refusal survives every locale at 8x text',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      for (final locale in AppLocalizations.supportedLocales) {
        await showRefusal(
          tester,
          importShell(
            locale: locale,
            textScaler: const TextScaler.linear(8.0),
          ),
        );

        expect(tester.takeException(), isNull,
            reason: '$locale at 8x must scroll, never overflow');
      }
    });

    testWidgets('the too-old refusal renders in every theme and contrast',
        (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final hc in [false, true]) {
          await showRefusal(tester, importShell(mode: mode, highContrast: hc));
          expect(tester.takeException(), isNull,
              reason: 'mode=$mode highContrast=$hc must render cleanly');
        }
      }
    });

    testWidgets('the upgrade link meets the labelled-tap-target guideline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await showRefusal(tester, importShell());

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // ── No-file validation for each importer ─────────────────────────────────

    testWidgets('shows error when Enpass import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Enpass');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Bitwarden import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Bitwarden');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Google PM import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Google Password Manager');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Dashlane import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Dashlane');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when CSV continue attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Generic CSV'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final col = find
          .ancestor(
              of: find.text('Generic CSV'), matching: find.byType(Column))
          .first;
      final btn = find.descendant(of: col, matching: find.byType(FilledButton));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      expect(find.text('Select a file.'), findsWidgets);
    });

    // ── Section visibility ────────────────────────────────────────────────────

    testWidgets('Enpass section is visible when scrolled to', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Enpass'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enpass'), findsOneWidget);
    });

    testWidgets('Bitwarden section is visible when scrolled to',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Bitwarden'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bitwarden'), findsOneWidget);
    });

    testWidgets('Google PM section is visible when scrolled to',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Google Password Manager'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Google Password Manager'), findsOneWidget);
    });

    testWidgets('Dashlane section is visible when scrolled to', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Dashlane'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dashlane'), findsOneWidget);
    });

    // ── Passphrase field ─────────────────────────────────────────────────────

    testWidgets('passphrase field toggles visibility', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Vault passphrase'));

      // Initially obscured → visibility icon shown.
      final toggleBtn = find.byIcon(Icons.visibility);
      await tester.ensureVisible(toggleBtn);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // After toggle, passphrase visible → visibility_off icon shown.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    // A11y: the passphrase show/hide eye toggle must carry a semantic label so
    // screen readers announce it, not a bare "button".
    testWidgets('meets labelled-tap-target guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('announces import size limits', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.textContaining('Maximum file size'), findsOneWidget);
      expect(find.textContaining('25 MB'), findsOneWidget);
      expect(find.textContaining('128 MB'), findsOneWidget);
    });

    test('importSizeExceeded enforces per-format caps', () {
      // Text formats reject above 25 MiB; Enpass allows up to 128 MiB.
      expect(importSizeExceeded(kTextImportMaxBytes, isEnpass: false), isFalse);
      expect(importSizeExceeded(kTextImportMaxBytes + 1, isEnpass: false), isTrue);
      expect(importSizeExceeded(kEnpassImportMaxBytes, isEnpass: true), isFalse);
      expect(importSizeExceeded(kEnpassImportMaxBytes + 1, isEnpass: true), isTrue);
      // A file over the text cap but under the Enpass cap is fine for Enpass.
      expect(importSizeExceeded(kTextImportMaxBytes + 1, isEnpass: true), isFalse);
    });

    test('importLimitLabel formats bytes as MB', () {
      expect(importLimitLabel(kTextImportMaxBytes), '25 MB');
      expect(importLimitLabel(kEnpassImportMaxBytes), '128 MB');
    });
  });
}