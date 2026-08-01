import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adopt_error_invalid')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
      await tester.tap(find.byKey(const Key('adopt_pick_button')));
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
}
