import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/safe_file_picker.dart' show FilePickerUnavailable;
import 'package:gabbro/screens/adopt_vault_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';

import 'test_helpers.dart';

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({
  Future<String?> Function()? onPickFile,
  Future<VaultHeaderData> Function(String path)? onReadHeader,
  Future<bool> Function(String path)? onFormatTooOld,
  Future<bool> Function(String path)? onFormatTooNew,
  Future<void> Function(String path, String alias)? onRegistered,
  Future<void> Function(String source, String dest)? onAdoptCopy,
  Future<String> Function()? onDefaultVaultDir,
  bool isAndroid = false,
  VaultRegistry? registry,
}) => testApp(
  AdoptVaultScreen(
    registry: registry ?? VaultRegistry([]),
    onPickFile: onPickFile ?? () async => null,
    onReadHeader:
        onReadHeader ?? (_) async => const VaultHeaderData(yubikeyRecords: []),
    onFormatTooOld: onFormatTooOld ?? (_) async => false,
    onFormatTooNew: onFormatTooNew ?? (_) async => false,
    onRegistered: onRegistered ?? (_, _) async {},
    onAdoptCopy: onAdoptCopy ?? (_, _) async {},
    onDefaultVaultDir: onDefaultVaultDir ?? () async => '/tmp/appdata',
    isAndroid: isAndroid,
  ),
);

VaultRecord _record(String path, String alias) => VaultRecord(
  path: path,
  alias: alias,
  lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Future<VaultHeaderData> _throwingHeader(String _) async =>
    throw Exception('not a vault');

// Taps the PathField's browse button (the picker affordance).
Future<void> _tapBrowse(WidgetTester tester) => tester.tap(
  find.descendant(
    of: find.byKey(const Key('adopt_path_field')),
    matching: find.byType(IconButton),
  ),
);

void main() {
  group('F1: picked valid file', () {
    testWidgets('prefills the alias from the header, editable', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/picked.gabbro',
          onReadHeader: (_) async =>
              const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      // Alias prefilled from the vault file's header…
      final aliasField = find.byKey(const Key('adopt_alias_field'));
      expect(aliasField, findsOneWidget);
      expect(
        tester.widget<TextField>(aliasField).controller?.text,
        'Personal',
      );
      // …and editable.
      await tester.enterText(aliasField, 'Work');
      expect(tester.widget<TextField>(aliasField).controller?.text, 'Work');
    });

    testWidgets('no alias in the header leaves the field empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/picked.gabbro',
          onReadHeader: (_) async =>
              const VaultHeaderData(yubikeyRecords: []),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      final aliasField = find.byKey(const Key('adopt_alias_field'));
      expect(aliasField, findsOneWidget);
      expect(tester.widget<TextField>(aliasField).controller?.text, isEmpty);
    });
  });

  group('F2: triage of an unusable picked file', () {
    testWidgets('not a vault -> error, no alias field', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/junk.bin',
          onReadHeader: _throwingHeader,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt_error_invalid')), findsOneWidget);
      expect(find.byKey(const Key('adopt_alias_field')), findsNothing);
    });

    testWidgets('too-old vault -> upgrade-path message with link', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/old.gabbro',
          onReadHeader: _throwingHeader,
          onFormatTooOld: (_) async => true,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt_error_too_old')), findsOneWidget);
      expect(find.byKey(const Key('adopt_upgrade_link')), findsOneWidget);
      expect(find.byKey(const Key('adopt_alias_field')), findsNothing);
    });

    testWidgets('too-new vault -> its own message', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/new.gabbro',
          onReadHeader: _throwingHeader,
          onFormatTooNew: (_) async => true,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt_error_too_new')), findsOneWidget);
      expect(find.byKey(const Key('adopt_alias_field')), findsNothing);
    });

    testWidgets('a good pick after a bad one clears the error', (
      tester,
    ) async {
      var pick = 0;
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => ++pick == 1 ? '/tmp/junk.bin' : '/tmp/ok.gabbro',
          onReadHeader: (path) async => path == '/tmp/junk.bin'
              ? throw Exception('not a vault')
              : const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adopt_error_invalid')), findsOneWidget);

      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adopt_error_invalid')), findsNothing);
      expect(find.byKey(const Key('adopt_alias_field')), findsOneWidget);
    });
  });

  group('F3: alias collision', () {
    testWidgets('an alias already in the registry blocks adopt', (
      tester,
    ) async {
      var registered = 0;
      await tester.pumpWidget(
        _buildScreen(
          registry: VaultRegistry([_record('/tmp/a.gabbro', 'Personal')]),
          onPickFile: () async => '/tmp/picked.gabbro',
          onReadHeader: (_) async =>
              const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
          onRegistered: (_, _) async => registered++,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adopt_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt_alias_collision')), findsOneWidget);
      expect(registered, 0, reason: 'a colliding alias must not register');
    });

    testWidgets('editing to a free alias clears the block and adopts', (
      tester,
    ) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        _buildScreen(
          registry: VaultRegistry([_record('/tmp/a.gabbro', 'Personal')]),
          onPickFile: () async => '/tmp/picked.gabbro',
          onReadHeader: (_) async =>
              const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
          onRegistered: (path, alias) async => calls.add((path, alias)),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adopt_confirm_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adopt_alias_collision')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('adopt_alias_field')),
        'Work',
      );
      await tester.tap(find.byKey(const Key('adopt_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt_alias_collision')), findsNothing);
      expect(calls, [('/tmp/picked.gabbro', 'Work')]);
    });
  });

  group('F4: already-registered path', () {
    testWidgets('picking a path already in the registry is refused', (
      tester,
    ) async {
      var headerReads = 0;
      await tester.pumpWidget(
        _buildScreen(
          registry: VaultRegistry([_record('/tmp/mine.gabbro', 'Personal')]),
          onPickFile: () async => '/tmp/mine.gabbro',
          onReadHeader: (_) async {
            headerReads++;
            return const VaultHeaderData(yubikeyRecords: []);
          },
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('adopt_error_already_registered')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('adopt_alias_field')), findsNothing);
      expect(headerReads, 0, reason: 'refuse before touching the file');
    });
  });

  group('F5/F6: platform split on confirm', () {
    Future<void> pickAndConfirm(WidgetTester tester) async {
      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('adopt_alias_field')),
        'Work',
      );
      await tester.tap(find.byKey(const Key('adopt_confirm_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('F5 Linux: registers the picked path in place, no copy', (
      tester,
    ) async {
      final copies = <(String, String)>[];
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/picked.gabbro',
          onAdoptCopy: (s, d) async => copies.add((s, d)),
          onRegistered: (path, alias) async => calls.add((path, alias)),
        ),
      );
      await pickAndConfirm(tester);

      expect(copies, isEmpty, reason: 'Linux must not copy the file');
      expect(calls, [('/tmp/picked.gabbro', 'Work')]);
    });

    testWidgets('F6 Android: copies into app storage, registers the copy', (
      tester,
    ) async {
      final copies = <(String, String)>[];
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        _buildScreen(
          isAndroid: true,
          onPickFile: () async => '/cache/B.gabbro',
          onDefaultVaultDir: () async => '/tmp/appdata',
          onAdoptCopy: (s, d) async => copies.add((s, d)),
          onRegistered: (path, alias) async => calls.add((path, alias)),
        ),
      );
      await pickAndConfirm(tester);

      expect(copies, [('/cache/B.gabbro', '/tmp/appdata/B.gabbro')]);
      expect(calls, [('/tmp/appdata/B.gabbro', 'Work')]);
    });

    testWidgets('F6 Android: an occupied basename gets a free suffix', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('gabbro_adopt_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/B.gabbro').writeAsBytesSync([1]);

      final copies = <(String, String)>[];
      await tester.pumpWidget(
        _buildScreen(
          isAndroid: true,
          onPickFile: () async => '/cache/B.gabbro',
          onDefaultVaultDir: () async => dir.path,
          onAdoptCopy: (s, d) async => copies.add((s, d)),
        ),
      );
      await pickAndConfirm(tester);

      expect(copies, [('/cache/B.gabbro', '${dir.path}/B-2.gabbro')]);
    });
  });

  // N5 (Linux desktop): the whole flow must complete without a pointer —
  // typed path, Enter to triage, Tab to the Add button, Enter to adopt.
  group('N5: keyboard only', () {
    testWidgets('typed path -> Enter -> Tab -> Enter adopts', (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        _buildScreen(
          onReadHeader: (_) async =>
              const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
          onRegistered: (path, alias) async => calls.add((path, alias)),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('adopt_path_field')),
        '/tmp/typed.gabbro',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adopt_alias_field')), findsOneWidget);

      bool confirmFocused() {
        final f = FocusManager.instance.primaryFocus;
        if (f?.context == null) return false;
        var found = false;
        f!.context!.visitAncestorElements((e) {
          if (e.widget.key == const Key('adopt_confirm_button')) {
            found = true;
            return false;
          }
          return true;
        });
        return found;
      }

      var reached = false;
      for (var i = 0; i < 8 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        reached = confirmFocused();
      }
      expect(reached, isTrue, reason: 'Tab must reach the Add button');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, [('/tmp/typed.gabbro', 'Personal')]);
    });
  });

  // N4: an error card appearing moves no focus, so on Linux the reader would
  // say nothing — announce it. Android is gated off (deprecated events;
  // TalkBack reads the widgets themselves).
  group('N4: errors are announced on Linux', () {
    testWidgets('triage error is spoken', (tester) async {
      final said = recordAnnouncements(tester);
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => '/tmp/junk.bin',
          onReadHeader: _throwingHeader,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(said, contains(l.restoreFromFileInvalidError));
    });

    testWidgets('collision is spoken', (tester) async {
      final said = recordAnnouncements(tester);
      await tester.pumpWidget(
        _buildScreen(
          registry: VaultRegistry([_record('/tmp/a.gabbro', 'Personal')]),
          onPickFile: () async => '/tmp/picked.gabbro',
          onReadHeader: (_) async =>
              const VaultHeaderData(alias: 'Personal', yubikeyRecords: []),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adopt_confirm_button')));
      await tester.pumpAndSettle();

      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(said, contains(l.vaultNameAlreadyExists('Personal')));
    });

    testWidgets('Android stays silent', (tester) async {
      final said = recordAnnouncements(tester);
      await tester.pumpWidget(
        _buildScreen(
          isAndroid: true,
          onPickFile: () async => '/tmp/junk.bin',
          onReadHeader: _throwingHeader,
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(said, isEmpty);
    });
  });

  // N2: longest strings x largest text x narrowest phone, together, through
  // every state of the flow — the catalog probe only sweeps the initial state
  // at 2x.
  group('N2: every locale at 8x on a 360dp phone', () {
    testWidgets('all five states render without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      for (final locale in AppLocalizations.supportedLocales) {
        // Pick sequence: valid -> unparseable -> too-old -> registered path.
        final picks = [
          '/tmp/ok.gabbro',
          '/tmp/junk.bin',
          '/tmp/old.gabbro',
          '/tmp/mine.gabbro',
        ];
        var pick = 0;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: gabbroLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(8.0)),
            child: child!,
          ),
          home: AdoptVaultScreen(
            registry: VaultRegistry([
              _record('/tmp/mine.gabbro', 'Personal'),
            ]),
            isAndroid: false,
            onPickFile: () async => picks[pick++],
            onReadHeader: (path) async => path == '/tmp/ok.gabbro'
                ? const VaultHeaderData(
                    alias: 'Personal', yubikeyRecords: [])
                : throw Exception('not a vault'),
            onFormatTooOld: (path) async => path == '/tmp/old.gabbro',
            onFormatTooNew: (_) async => false,
            onRegistered: (_, _) async {},
          ),
        ));
        await tester.pumpAndSettle();
        final l = lookupAppLocalizations(locale);

        // The screen's own list, not a TextField's inner scrollable — at 8x a
        // huge field can own the list's centre, so centre-drags are unsafe.
        final list = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        Future<void> show(Finder f, double delta) async {
          await tester.scrollUntilVisible(f, delta, scrollable: list);
          await tester.pumpAndSettle();
        }

        Future<void> browse() async {
          // Back to the top: at 8x the lazy ListView disposes the path field
          // once later steps scroll it away.
          await show(find.byKey(const Key('adopt_path_field')), -400);
          await _tapBrowse(tester);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'state after pick ${picks[pick - 1]} must scroll at 8x '
                  'in $locale, never overflow');
        }

        // 1. valid pick -> alias + confirm visible.
        await browse();
        expect(find.text(l.adoptConfirm), findsOneWidget,
            reason: 'confirm must be on screen for $locale');

        // 2. confirm with the colliding alias -> collision error. Invoked
        // directly: at 8x the button can be taller than the viewport, so a
        // centre-tap misses — a harness artifact. Tappability is pinned at
        // 1x by F3; this sweep asserts layout.
        await show(find.byKey(const Key('adopt_confirm_button')), 400);
        tester
            .widget<FilledButton>(find.byKey(const Key('adopt_confirm_button')))
            .onPressed!();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'collision error must scroll at 8x in $locale');
        // The zero-size collision marker can sit outside the lazy list's
        // build range at 8x — assert the user-visible signal instead: the
        // localized collision message on the alias field.
        await show(find.byKey(const Key('adopt_alias_field')), -400);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('adopt_alias_field')))
              .decoration
              ?.errorText,
          lookupAppLocalizations(locale).vaultNameAlreadyExists('Personal'),
          reason: 'the collision must be reported, localized, for $locale',
        );

        // 3-5. unparseable, too-old (with its link), registered path.
        await browse();
        expect(find.byKey(const Key('adopt_error_invalid')), findsOneWidget);
        await browse();
        expect(find.byKey(const Key('adopt_error_too_old')), findsOneWidget);
        await browse();
        expect(find.byKey(const Key('adopt_error_already_registered')),
            findsOneWidget);
      }
    });
  });

  group('F8: picker edge cases', () {
    testWidgets('cancelling the picker changes nothing', (tester) async {
      var headerReads = 0;
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => null,
          onReadHeader: (_) async {
            headerReads++;
            return const VaultHeaderData(yubikeyRecords: []);
          },
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(headerReads, 0);
      expect(find.byKey(const Key('adopt_alias_field')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('portal unavailable -> SnackBar inviting a typed path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickFile: () async => throw const FilePickerUnavailable('no portal'),
        ),
      );
      await _tapBrowse(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a typed path submitted with Enter is triaged', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          onReadHeader: (path) async => path == '/tmp/typed.gabbro'
              ? const VaultHeaderData(alias: 'Typed', yubikeyRecords: [])
              : throw Exception('wrong path'),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('adopt_path_field')),
        '/tmp/typed.gabbro',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final aliasField = find.byKey(const Key('adopt_alias_field'));
      expect(aliasField, findsOneWidget);
      expect(tester.widget<TextField>(aliasField).controller?.text, 'Typed');
    });
  });
}
