import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/sync_settings_screen.dart';
import 'package:gabbro/settings.dart';
import 'test_helpers.dart';

// S5: the Sync settings screen. Auto-merge toggle, sync folder + Remember.
// The folder picker is a seam: tests never open a dialog.

Widget _buildScreen({
  AppSettings settings = const AppSettings(),
  void Function(AppSettings)? onUpdate,
  Future<String?> Function()? onPickFolder,
  bool isAndroid = false,
}) => testApp(
  SyncSettingsScreen(
    settings: settings,
    onUpdate: onUpdate ?? (_) {},
    onPickFolder: onPickFolder ?? () async => null,
    isAndroid: isAndroid,
  ),
);

Widget _buildScaled(double scale, {AppSettings settings = const AppSettings()}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: SyncSettingsScreen(
        settings: settings,
        onUpdate: (_) {},
        onPickFolder: () async => null,
        isAndroid: false,
      ),
    );

Finder _autoMergeTile() => find.widgetWithText(SwitchListTile, 'Merge automatically');
Finder _rememberTile() => find.widgetWithText(CheckboxListTile, 'Remember');

void main() {
  group('auto-merge toggle', () {
    testWidgets('is off by default', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(tester.widget<SwitchListTile>(_autoMergeTile()).value, isFalse);
    });

    testWidgets('reflects the setting', (tester) async {
      await tester.pumpWidget(
        _buildScreen(settings: const AppSettings(autoMergeSync: true)),
      );
      expect(tester.widget<SwitchListTile>(_autoMergeTile()).value, isTrue);
    });

    testWidgets('flipping it calls onUpdate with the new value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(_autoMergeTile());
      await tester.pumpAndSettle();
      expect(updated?.autoMergeSync, isTrue);
      expect(tester.widget<SwitchListTile>(_autoMergeTile()).value, isTrue);
    });

    testWidgets('its description carries the same-passphrase warning', (
      tester,
    ) async {
      // The chooser that showed the warning is skipped when auto-merge is on,
      // so this screen is the only place left that can say it.
      await tester.pumpWidget(_buildScreen());
      expect(
        find.text('Same passphrase does not prove same vault.'),
        findsOneWidget,
      );
    });
  });

  group('sync folder', () {
    testWidgets('shows "not set" and Remember unticked when empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.textContaining('Not set'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(_rememberTile()).value, isFalse);
    });

    testWidgets('shows the remembered Linux folder and Remember ticked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(settings: const AppSettings(syncFolder: '/tmp/GabbroSync')),
      );
      expect(find.text('/tmp/GabbroSync'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(_rememberTile()).value, isTrue);
    });

    testWidgets('shows an Android tree URI as a readable folder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          isAndroid: true,
          settings: const AppSettings(
            syncFolder:
                'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FGabbroSync',
          ),
        ),
      );
      expect(find.text('primary:Download/GabbroSync'), findsOneWidget);
    });

    testWidgets('Choose folder picks, remembers and ticks Remember', (
      tester,
    ) async {
      AppSettings? updated;
      await tester.pumpWidget(
        _buildScreen(
          onUpdate: (s) => updated = s,
          onPickFolder: () async => '/home/user/GabbroSync',
        ),
      );
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(updated?.syncFolder, '/home/user/GabbroSync');
      expect(find.text('/home/user/GabbroSync'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(_rememberTile()).value, isTrue);
    });

    testWidgets('a cancelled pick changes nothing', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _buildScreen(
          settings: const AppSettings(syncFolder: '/tmp/GabbroSync'),
          onUpdate: (_) => calls++,
          onPickFolder: () async => null,
        ),
      );
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('/tmp/GabbroSync'), findsOneWidget);
    });

    testWidgets('unticking Remember forgets the folder', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(
        _buildScreen(
          settings: const AppSettings(syncFolder: '/tmp/GabbroSync'),
          onUpdate: (s) => updated = s,
        ),
      );
      await tester.tap(_rememberTile());
      await tester.pumpAndSettle();

      expect(updated?.syncFolder, '');
      expect(find.textContaining('Not set'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(_rememberTile()).value, isFalse);
    });

    testWidgets('ticking Remember with no folder opens the picker', (
      tester,
    ) async {
      // A tick with nothing to remember is a request to choose.
      var picks = 0;
      await tester.pumpWidget(
        _buildScreen(
          onPickFolder: () async {
            picks++;
            return null;
          },
        ),
      );
      await tester.tap(_rememberTile());
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(tester.widget<CheckboxListTile>(_rememberTile()).value, isFalse);
    });
  });

  group('accessibility', () {
    testWidgets('every tappable control is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildScreen(settings: const AppSettings(syncFolder: '/tmp/GabbroSync')),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the screen scrolls; nothing overflows at 2x and 3x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final scale in [2.0, 3.0]) {
        await tester.pumpWidget(
          _buildScaled(
            scale,
            settings: const AppSettings(
              syncFolder:
                  '/home/user/a/rather/long/folder/path/that/wraps/GabbroSync',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow at ${scale}x');
        await tester.scrollUntilVisible(_rememberTile(), 200);
        expect(_rememberTile(), findsOneWidget);
      }
    });
  });
}
