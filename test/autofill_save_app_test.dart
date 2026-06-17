import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/save_confirm_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

// The autofill save app shell: when already unlocked it fetches the save context
// and shows the confirm screen; when locked it shows the unlock flow first.

VaultRecord _rec(String path, String alias) => VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

VaultRegistry _vaults() => VaultRegistry([
      _rec('/tmp/a.gabbro', 'Alpha'),
      _rec('/tmp/b.gabbro', 'Beta'),
    ]);

String _createJson() => jsonEncode({
      'captured': {
        'username': 'alice',
        'email': '',
        'password': 'pw',
        'url': 'https://example.com',
        'appId': '',
      },
      'decision': {'action': 'create'},
      'candidates': const [],
    });

void main() {
  testWidgets('already unlocked: fetches context and shows the confirm screen',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      fetchSaveContextJson: () async => _createJson(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SaveConfirmScreen), findsOneWidget);
    expect(find.byType(UnlockScreen), findsNothing);
    expect(find.text('Save as a new login'), findsOneWidget);
  });

  testWidgets('locked: shows the unlock screen first, not the confirm screen',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => '{}',
    ));
    await tester.pump();

    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.byType(SaveConfirmScreen), findsNothing);
  });
}
