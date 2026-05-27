import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VaultRecord {
  final String path;
  final String alias;
  final DateTime lastUsedAt;

  VaultRecord({
    required this.path,
    required this.alias,
    required this.lastUsedAt,
  });

  VaultRecord copyWith({String? path, String? alias, DateTime? lastUsedAt}) =>
      VaultRecord(
        path: path ?? this.path,
        alias: alias ?? this.alias,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'alias': alias,
    'last_used_at': lastUsedAt.toIso8601String(),
  };

  factory VaultRecord.fromJson(Map<String, dynamic> json) => VaultRecord(
    path: json['path'] as String,
    alias: json['alias'] as String? ?? 'Vault',
    lastUsedAt: json['last_used_at'] != null
        ? DateTime.parse(json['last_used_at'] as String)
        : DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class VaultRegistry {
  final List<VaultRecord> _records;

  VaultRegistry(List<VaultRecord> records) : _records = List.of(records);

  List<VaultRecord> get records => List.unmodifiable(_records);

  VaultRecord? get lastUsed {
    if (_records.isEmpty) return null;
    return _records.reduce(
      (a, b) => a.lastUsedAt.isAfter(b.lastUsedAt) ? a : b,
    );
  }

  VaultRegistry add(VaultRecord record) =>
      VaultRegistry([..._records, record]);

  VaultRegistry remove(String path) =>
      VaultRegistry(_records.where((r) => r.path != path).toList());

  VaultRegistry updateAlias(String path, String alias) => VaultRegistry(
    _records
        .map((r) => r.path == path ? r.copyWith(alias: alias) : r)
        .toList(),
  );

  VaultRegistry touchLastUsed(String path) => VaultRegistry(
    _records
        .map((r) => r.path == path ? r.copyWith(lastUsedAt: DateTime.now()) : r)
        .toList(),
  );

  // ── Serialisation ───────────────────────────────────────────────────────────

  List<Map<String, dynamic>> toJson() =>
      _records.map((r) => r.toJson()).toList();

  factory VaultRegistry.fromJson(List<dynamic> json) => VaultRegistry(
    json.map((e) => VaultRecord.fromJson(e as Map<String, dynamic>)).toList(),
  );

  // ── File I/O ─────────────────────────────────────────────────────────────────

  static Future<File> _registryFile() async {
    final String dirPath;
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      dirPath = Platform.isLinux
          ? '$home/.config/gabbro'
          : '$home/Library/Application Support/gabbro';
    } else {
      final dir = await getApplicationSupportDirectory();
      dirPath = dir.path;
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('$dirPath/vaults.jsonc');
  }

  static Future<VaultRegistry> load() async {
    try {
      final file = await _registryFile();
      if (!file.existsSync()) return await _migrate();
      final raw = await file.readAsString();
      final stripped = _stripComments(raw);
      if (stripped.trim().isEmpty) return VaultRegistry([]);
      final json = jsonDecode(stripped) as List<dynamic>;
      return VaultRegistry.fromJson(json);
    } catch (_) {
      return VaultRegistry([]);
    }
  }

  static Future<VaultRegistry> _migrate() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final legacyVault = File('${appDir.path}/gabbro.gabbro');
      if (legacyVault.existsSync()) {
        final registry = VaultRegistry([
          VaultRecord(
            path: legacyVault.path,
            alias: 'Gabbro',
            lastUsedAt: DateTime.now(),
          ),
        ]);
        await registry.save();
        return registry;
      }
    } catch (_) {}
    return VaultRegistry([]);
  }

  Future<void> save() async {
    final file = await _registryFile();
    await file.writeAsString(_toJsonc());
  }

  String _toJsonc() {
    const encoder = JsonEncoder.withIndent('  ');
    return '// Gabbro vault registry\n${encoder.convert(toJson())}\n';
  }

  // ── JSONC parser ─────────────────────────────────────────────────────────────

  static String _stripComments(String input) {
    return input
        .split('\n')
        .where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('//') && !trimmed.startsWith('#');
        })
        .join('\n');
  }

  // Exposed for testing only.
  static VaultRegistry buildMigratedRegistryForTest(String vaultPath) =>
      VaultRegistry([
        VaultRecord(
          path: vaultPath,
          alias: 'Gabbro',
          lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]);
}
