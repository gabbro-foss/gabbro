import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/text_scale.dart';

// A failure SnackBar is the only explanation the user gets, so every message
// still shown in one must be reachable at the 2x phone ceiling in every
// locale; messages that could not are in a scrolling dialog and gated in
// their own tests. Judge by the message's rectangle: a SnackBar clips
// instead of overflowing, so it never throws.

/// A 360dp-wide phone surface, restored after the test.
void phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Shows [message] in a SnackBar at [locale] and [scale], and returns the
/// rectangle the text actually occupies.
Future<Rect> _rectFor(
  WidgetTester tester,
  Locale locale,
  double scale,
  String Function(AppLocalizations) message,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  tester.platformDispatcher.textScaleFactorTestValue = scale;
  late String shown;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              shown = message(AppLocalizations.of(context));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(shown)));
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return tester.getRect(find.text(shown));
}

/// Whether the user can actually get to the whole message: either it fits the
/// screen, or it has a scroll ancestor to reach the rest of it. A SnackBar has
/// neither once the text outgrows the strip - it clips, and the remainder is
/// unreachable by any gesture.
bool _isReachable(WidgetTester tester, Rect rect, Finder message) {
  final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  if (rect.top >= 0 && rect.bottom <= screen) return true;
  return find
      .ancestor(of: message, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty;
}

/// A bounded worst-case error string (~130 chars, the measured ceiling for
/// every {error} argument except the FileSystemException path cases).
const _boundedError =
    'PlatformException(channel-error, Unable to establish connection on '
    'channel: the platform thread has shut down unexpectedly, null, null)';

/// A realistic export path a phone user actually produces (SAF folder).
const _realisticPath = '/storage/emulated/0/Documents/GabbroSync/backup.gabbro';

void main() {
  // Every SnackBar message in the app (the 26-message sweep in
  // docs/ARCHITECTURE.md), with worst-case arguments where parameterised.
  final cases = <String, String Function(AppLocalizations)>{
    // manage_yubikeys_screen
    'yubiKeyAdded': (l) => l.yubiKeyAdded,
    'yubiKeyRemoved': (l) => l.yubiKeyRemoved,
    'tapYubiKeyToRegister': (l) => l.tapYubiKeyToRegister,
    'noFidoDeviceFound': (l) => l.noFidoDeviceFound,
    'failedToAddKey': (l) => l.failedToAddKey(_boundedError),
    'failedToRemoveKey': (l) => l.failedToRemoveKey(_boundedError),
    'failedToSaveAlias': (l) => l.failedToSaveAlias(_boundedError),
    'failedToRegisterKey': (l) => l.failedToRegisterKey(_boundedError),
    'failedToActivateKey': (l) => l.failedToActivateKey(_boundedError),
    // vault_list_screen
    'vaultSynced': (l) => l.vaultSynced(999, 999, 999),
    'nothingToSync': (l) => l.nothingToSync,
    'syncCancelled': (l) => l.syncCancelled,
    'importedEntries': (l) => l.importedEntries(9999),
    // manage_folders_screen
    'folderActionFailed': (l) => l.folderActionFailed(_boundedError),
    // entry_detail_screen
    'copiedClears60s': (l) => l.copiedClears60s,
    'exportedToPath': (l) => l.exportedToPath(_realisticPath),
    // security_screen
    'biometricUnavailable': (l) => l.biometricUnavailable,
    // create_entry_screen
    'noChangesToSave': (l) => l.noChangesToSave,
    // change_passphrase_screen
    'changePassphraseSuccess': (l) => l.changePassphraseSuccess,
    'changePassphraseBiometricDisabled': (l) =>
        l.changePassphraseBiometricDisabled,
    // safe_file_picker
    'filePickerUnavailable': (l) => l.filePickerUnavailable,
    'filePickerNoPortal': (l) => l.filePickerNoPortal,
  };

  testWidgets('sweep: every SnackBar message at 2x in every locale', (
    tester,
  ) async {
    phoneSurface(tester);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final failed = <String>[];
    for (final entry in cases.entries) {
      for (final locale in AppLocalizations.supportedLocales) {
        final rect = await _rectFor(
          tester,
          locale,
          kPhoneMaxScale,
          entry.value,
        );
        final text = entry.value(lookupAppLocalizations(locale));
        if (!_isReachable(tester, rect, find.text(text))) {
          failed.add('${entry.key} in ${locale.toLanguageTag()} '
              '(${text.length} chars, bottom ${rect.bottom.round()}dp)');
        }
      }
    }
    expect(failed, isEmpty,
        reason: 'SnackBar messages clipped at 2x - move them to '
            'showFailureMessage (ADR-016): $failed');
  });
}
