import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/save_confirm_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// The save-confirm screen resolves the user's choice (update / save-new /
// pick-another / cancel) and writes through injected seams — never a silent
// overwrite. Real bridge calls are replaced by fakes here.

VaultEntryData _login(String id, {String password = 'old', String username = 'alice'}) =>
    VaultEntryData.login(LoginEntryData(
      id: id,
      createdAt: 'c',
      updatedAt: 'u',
      folder: 'Personal',
      title: 'Example',
      url: 'https://example.com',
      username: username,
      password: password,
      notes: null,
      customFields: const [],
      previousPassword: null,
      appId: null,
      email: null,
    ));

SaveContext _ctx({
  SaveActionKind action = SaveActionKind.create,
  String? matchedId,
  List<SaveCandidate> candidates = const [],
  String password = 'newpw',
}) =>
    SaveContext(
      username: 'alice',
      email: '',
      password: password,
      url: 'https://example.com',
      appId: '',
      action: action,
      matchedId: matchedId,
      candidates: candidates,
    );

Future<void> _pump(WidgetTester tester, SaveConfirmScreen screen) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FD1 update action defaults to Update this login', (tester) async {
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(action: SaveActionKind.update, matchedId: 'id-1'),
        onGetEntry: (id) => _login(id),
        onDone: () {},
        onCancel: () {},
      ),
    );
    expect(find.text('Update this login'), findsOneWidget);
    expect(find.text('Save as a new login'), findsOneWidget);
  });

  testWidgets('FD1 create action shows Save as new, no Update', (tester) async {
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(action: SaveActionKind.create),
        onDone: () {},
        onCancel: () {},
      ),
    );
    expect(find.text('Save as a new login'), findsOneWidget);
    expect(find.text('Update this login'), findsNothing);
  });

  testWidgets('FD2 Update writes the swapped password, preserving other fields',
      (tester) async {
    VaultEntryData? updated;
    var done = false;
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(action: SaveActionKind.update, matchedId: 'id-1', password: 'brandnew'),
        onGetEntry: (id) => _login(id, password: 'old'),
        onUpdate: (e, d) async => updated = e,
        onDone: () => done = true,
        onCancel: () {},
      ),
    );
    await tester.tap(find.text('Update this login'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    final login = updated as VaultEntryData_Login;
    expect(login.field0.password, 'brandnew');
    expect(login.field0.id, 'id-1');
    expect(login.field0.username, 'alice'); // preserved from the existing entry
  });

  testWidgets('FD3 Save as new creates an entry from the captured fields',
      (tester) async {
    VaultEntryData? created;
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(action: SaveActionKind.create, password: 'secret'),
        onCreate: (e) async => created = e,
        onDone: () {},
        onCancel: () {},
      ),
    );
    await tester.tap(find.text('Save as a new login'));
    await tester.pumpAndSettle();

    final login = created as VaultEntryData_Login;
    expect(login.field0.password, 'secret');
    expect(login.field0.username, 'alice');
    expect(login.field0.url, 'https://example.com');
  });

  testWidgets('FD4 Choose another updates the picked candidate', (tester) async {
    String? updatedId;
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(
          action: SaveActionKind.update,
          matchedId: 'id-1',
          candidates: const [SaveCandidate(id: 'id-2', label: 'bob')],
        ),
        onGetEntry: (id) => _login(id),
        onUpdate: (e, d) async => updatedId = (e as VaultEntryData_Login).field0.id,
        onDone: () {},
        onCancel: () {},
      ),
    );
    await tester.tap(find.text('Choose another login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();

    expect(updatedId, 'id-2');
  });

  testWidgets('FD5 Cancel signals cancel and writes nothing', (tester) async {
    var cancelled = false;
    var wrote = false;
    await _pump(
      tester,
      SaveConfirmScreen(
        saveContext: _ctx(action: SaveActionKind.create),
        onCreate: (e) async => wrote = true,
        onUpdate: (e, d) async => wrote = true,
        onDone: () {},
        onCancel: () => cancelled = true,
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(wrote, isFalse);
  });

  test('FD6 expiryDaysFor maps the retention setting', () {
    expect(expiryDaysFor(PasswordHistoryExpiry.sevenDays), 7);
    expect(expiryDaysFor(PasswordHistoryExpiry.thirtyDays), 30);
    expect(expiryDaysFor(PasswordHistoryExpiry.ninetyDays), 90);
    expect(expiryDaysFor(PasswordHistoryExpiry.keepForever), isNull);
  });

  test('SaveContext.fromJson parses an update with candidates', () {
    final ctx = SaveContext.fromJson(const {
      'captured': {
        'username': 'a',
        'email': 'e',
        'password': 'p',
        'url': 'u',
        'appId': 'app',
      },
      'decision': {'action': 'update', 'matchedId': 'id-1'},
      'candidates': [
        {'id': 'id-2', 'label': 'bob'}
      ],
    });
    expect(ctx.action, SaveActionKind.update);
    expect(ctx.matchedId, 'id-1');
    expect(ctx.candidates.single.id, 'id-2');
    expect(ctx.username, 'a');
    expect(ctx.appId, 'app');
  });

  test('SaveContext.fromJson defaults to create on unknown/absent action', () {
    final ctx = SaveContext.fromJson(const {
      'captured': <String, dynamic>{},
      'decision': <String, dynamic>{},
      'candidates': <dynamic>[],
    });
    expect(ctx.action, SaveActionKind.create);
    expect(ctx.username, '');
    expect(ctx.candidates, isEmpty);
  });
}
