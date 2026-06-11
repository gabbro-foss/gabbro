import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/vault_registry.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

VaultRecord _record({
  String path = '/tmp/vault.gabbro',
  String alias = 'Test',
  DateTime? lastUsedAt,
}) => VaultRecord(
  path: path,
  alias: alias,
  lastUsedAt: lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── VaultRecord.fromJson ────────────────────────────────────────────────────

  group('VaultRecord.fromJson', () {
    test('parses all fields', () {
      final r = VaultRecord.fromJson({
        'path': '/tmp/a.gabbro',
        'alias': 'Alpha',
        'last_used_at': '2026-01-01T00:00:00.000000',
      });
      expect(r.path, '/tmp/a.gabbro');
      expect(r.alias, 'Alpha');
      expect(r.lastUsedAt, DateTime.parse('2026-01-01T00:00:00.000000'));
    });

    test('defaults alias to "Vault" when missing', () {
      final r = VaultRecord.fromJson({'path': '/tmp/a.gabbro'});
      expect(r.alias, 'Vault');
    });

    test('defaults lastUsedAt to epoch when missing', () {
      final r = VaultRecord.fromJson({'path': '/tmp/a.gabbro'});
      expect(r.lastUsedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('parses yubikey type', () {
      final r = VaultRecord.fromJson({'path': '/tmp/a.gabbro', 'type': 'yubikey'});
      expect(r.type, VaultType.yubikey);
    });

    test('defaults type to passphrase when missing', () {
      final r = VaultRecord.fromJson({'path': '/tmp/a.gabbro'});
      expect(r.type, VaultType.passphrase);
    });

    test('defaults type to passphrase for unknown value', () {
      final r = VaultRecord.fromJson({'path': '/tmp/a.gabbro', 'type': 'unknown'});
      expect(r.type, VaultType.passphrase);
    });
  });

  // ── VaultRecord.toJson ──────────────────────────────────────────────────────

  group('VaultRecord.toJson', () {
    test('serialises all fields', () {
      final r = _record(path: '/tmp/b.gabbro', alias: 'Beta');
      final json = r.toJson();
      expect(json['path'], '/tmp/b.gabbro');
      expect(json['alias'], 'Beta');
      expect(json['last_used_at'], isA<String>());
    });

    test('round-trips through fromJson', () {
      final original = VaultRecord(
        path: '/p',
        alias: 'A',
        lastUsedAt: DateTime.parse('2026-05-01T10:00:00.000'),
        type: VaultType.yubikey,
      );
      final restored = VaultRecord.fromJson(original.toJson());
      expect(restored.path, original.path);
      expect(restored.alias, original.alias);
      expect(restored.lastUsedAt, original.lastUsedAt);
      expect(restored.type, VaultType.yubikey);
    });
  });

  // ── VaultRecord.copyWith ────────────────────────────────────────────────────

  group('VaultRecord.copyWith', () {
    test('overrides only path', () {
      final r = _record(alias: 'A');
      final r2 = r.copyWith(path: '/new');
      expect(r2.path, '/new');
      expect(r2.alias, 'A');
    });

    test('overrides only alias', () {
      final r = _record(path: '/p');
      final r2 = r.copyWith(alias: 'New');
      expect(r2.alias, 'New');
      expect(r2.path, '/p');
    });

    test('no-op when called with no arguments', () {
      final r = _record(path: '/p', alias: 'A');
      final r2 = r.copyWith();
      expect(r2.path, r.path);
      expect(r2.alias, r.alias);
    });
  });

  // ── VaultRegistry construction ──────────────────────────────────────────────

  group('VaultRegistry', () {
    test('empty registry has zero records', () {
      final reg = VaultRegistry([]);
      expect(reg.records, isEmpty);
    });

    test('records are accessible', () {
      final r = _record(path: '/a');
      final reg = VaultRegistry([r]);
      expect(reg.records.length, 1);
      expect(reg.records.first.path, '/a');
    });

    test('records list is unmodifiable', () {
      final reg = VaultRegistry([_record()]);
      expect(() => reg.records.add(_record()), throwsUnsupportedError);
    });
  });

  // ── VaultRegistry.lastUsed ──────────────────────────────────────────────────

  group('VaultRegistry.lastUsed', () {
    test('returns null for empty registry', () {
      expect(VaultRegistry([]).lastUsed, isNull);
    });

    test('returns only entry in single-record registry', () {
      final r = _record(path: '/only');
      final reg = VaultRegistry([r]);
      expect(reg.lastUsed!.path, '/only');
    });

    test('returns the most recently used vault', () {
      final older = _record(
        path: '/old',
        lastUsedAt: DateTime.parse('2026-01-01T00:00:00.000'),
      );
      final newer = _record(
        path: '/new',
        lastUsedAt: DateTime.parse('2026-06-01T00:00:00.000'),
      );
      final reg = VaultRegistry([older, newer]);
      expect(reg.lastUsed!.path, '/new');
    });

    test('ordering is consistent regardless of insertion order', () {
      final older = _record(
        path: '/old',
        lastUsedAt: DateTime.parse('2026-01-01T00:00:00.000'),
      );
      final newer = _record(
        path: '/new',
        lastUsedAt: DateTime.parse('2026-06-01T00:00:00.000'),
      );
      expect(VaultRegistry([newer, older]).lastUsed!.path, '/new');
      expect(VaultRegistry([older, newer]).lastUsed!.path, '/new');
    });
  });

  // ── VaultRegistry.add ──────────────────────────────────────────────────────

  group('VaultRegistry.add', () {
    test('adds a record', () {
      final reg = VaultRegistry([]).add(_record(path: '/a'));
      expect(reg.records.length, 1);
      expect(reg.records.first.path, '/a');
    });

    test('returns new instance; original unchanged', () {
      final original = VaultRegistry([]);
      final updated = original.add(_record(path: '/a'));
      expect(original.records, isEmpty);
      expect(updated.records.length, 1);
    });
  });

  // ── VaultRegistry.remove ────────────────────────────────────────────────────

  group('VaultRegistry.remove', () {
    test('removes by path', () {
      final reg = VaultRegistry([_record(path: '/a'), _record(path: '/b')]);
      final updated = reg.remove('/a');
      expect(updated.records.length, 1);
      expect(updated.records.first.path, '/b');
    });

    test('no-op when path not found', () {
      final reg = VaultRegistry([_record(path: '/a')]);
      final updated = reg.remove('/x');
      expect(updated.records.length, 1);
    });

    test('original unchanged after remove', () {
      final original = VaultRegistry([_record(path: '/a')]);
      original.remove('/a');
      expect(original.records.length, 1);
    });
  });

  // ── VaultRegistry.updateAlias ───────────────────────────────────────────────

  group('VaultRegistry.updateAlias', () {
    test('updates alias for matching path', () {
      final reg = VaultRegistry([_record(path: '/a', alias: 'Old')]);
      final updated = reg.updateAlias('/a', 'New');
      expect(updated.records.first.alias, 'New');
    });

    test('no-op when path not found', () {
      final reg = VaultRegistry([_record(path: '/a', alias: 'Old')]);
      final updated = reg.updateAlias('/x', 'New');
      expect(updated.records.first.alias, 'Old');
    });

    test('does not affect other records', () {
      final reg = VaultRegistry([
        _record(path: '/a', alias: 'AA'),
        _record(path: '/b', alias: 'BB'),
      ]);
      final updated = reg.updateAlias('/a', 'NewAA');
      expect(updated.records.firstWhere((r) => r.path == '/b').alias, 'BB');
    });
  });

  // ── VaultRegistry.touchLastUsed ─────────────────────────────────────────────

  group('VaultRegistry.touchLastUsed', () {
    test('updates lastUsedAt for matching path', () {
      final before = DateTime.parse('2020-01-01T00:00:00.000');
      final reg = VaultRegistry([_record(path: '/a', lastUsedAt: before)]);
      final updated = reg.touchLastUsed('/a');
      expect(updated.records.first.lastUsedAt.isAfter(before), isTrue);
    });

    test('does not affect other records', () {
      final before = DateTime.parse('2020-01-01T00:00:00.000');
      final reg = VaultRegistry([
        _record(path: '/a', lastUsedAt: before),
        _record(path: '/b', lastUsedAt: before),
      ]);
      final updated = reg.touchLastUsed('/a');
      expect(
        updated.records.firstWhere((r) => r.path == '/b').lastUsedAt,
        before,
      );
    });
  });

  // ── VaultRegistry serialisation ─────────────────────────────────────────────

  group('VaultRegistry serialisation', () {
    test('empty registry round-trips', () {
      final reg = VaultRegistry([]);
      final restored = VaultRegistry.fromJson(reg.toJson());
      expect(restored.records, isEmpty);
    });

    test('round-trips a record through fromJson/toJson', () {
      final r = _record(
        path: '/p',
        alias: 'P',
        lastUsedAt: DateTime.parse('2026-05-27T07:00:00.000'),
      );
      final reg = VaultRegistry([r]);
      final restored = VaultRegistry.fromJson(reg.toJson());
      expect(restored.records.length, 1);
      expect(restored.records.first.path, '/p');
      expect(restored.records.first.alias, 'P');
    });

    test('multiple records round-trip', () {
      final reg = VaultRegistry([
        _record(path: '/a', alias: 'A'),
        _record(path: '/b', alias: 'B'),
      ]);
      final restored = VaultRegistry.fromJson(reg.toJson());
      expect(restored.records.length, 2);
    });
  });

  // ── VaultRegistry migration ─────────────────────────────────────────────────

  // R-03: deleting a vault must also delete its .bak safety copy — on Android
  // the user has no file manager access to clean it up themselves.
  group('deleteVaultFiles', () {
    test('deletes the vault file and its .bak sibling', () async {
      final dir = await Directory.systemTemp.createTemp('gabbro_del_test_');
      final vault = File('${dir.path}/v.gabbro')..writeAsStringSync('vault');
      final bak = File('${dir.path}/v.gabbro.bak')..writeAsStringSync('bak');

      await deleteVaultFiles(vault.path);

      expect(vault.existsSync(), isFalse, reason: 'vault file must be deleted');
      expect(bak.existsSync(), isFalse,
          reason: '.bak must not survive vault deletion');
      await dir.delete(recursive: true);
    });

    test('succeeds when no .bak exists', () async {
      final dir = await Directory.systemTemp.createTemp('gabbro_del_test_');
      final vault = File('${dir.path}/v.gabbro')..writeAsStringSync('vault');

      await deleteVaultFiles(vault.path);

      expect(vault.existsSync(), isFalse);
      await dir.delete(recursive: true);
    });

    test('succeeds when neither file exists', () async {
      final dir = await Directory.systemTemp.createTemp('gabbro_del_test_');
      await deleteVaultFiles('${dir.path}/absent.gabbro');
      await dir.delete(recursive: true);
    });
  });

  group('VaultRegistry migration', () {
    test('buildMigratedRegistryForTest creates one entry with given path', () {
      final reg = VaultRegistry.buildMigratedRegistryForTest(
        '/legacy/gabbro.gabbro',
      );
      expect(reg.records.length, 1);
      expect(reg.records.first.path, '/legacy/gabbro.gabbro');
      expect(reg.records.first.alias, 'Gabbro');
    });

    test('migrated entry becomes lastUsed', () {
      final reg = VaultRegistry.buildMigratedRegistryForTest(
        '/legacy/gabbro.gabbro',
      );
      expect(reg.lastUsed, isNotNull);
      expect(reg.lastUsed!.path, '/legacy/gabbro.gabbro');
    });
  });
}
