import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Net for the Linux passkey daemon (docs/PASSKEY_INVESTIGATION.md): auto-type
// and the daemon stay strangers, and daemon code never reaches an Android
// build. If either breaks, a Linux passkey change ships inside auto-type or
// inside the Android .so.
//
// Daemon sources are the ones the plan names: uhid transport + CTAPHID
// framing. The sweeps arm themselves the moment such a file or module lands.

final RegExp _daemonPattern = RegExp('uhid|ctaphid', caseSensitive: false);

/// A `mod` declaration whose name marks it as daemon code.
final RegExp _daemonMod = RegExp(
  r'^\s*(?:pub\s+)?mod\s+\w*(?:uhid|ctaphid)\w*',
  caseSensitive: false,
);

List<File> _rustSources(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    fail('$dir does not exist - the sweep would pass vacuously');
  }
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.rs'))
      .toList();
}

void main() {
  test('autotype sources never reference the passkey daemon', () {
    final files = _rustSources('rust/src/autotype');
    expect(files, isNotEmpty, reason: 'empty listing checks nothing');
    for (final f in files) {
      expect(
        _daemonPattern.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} references uhid/ctaphid',
      );
    }
  });

  test('daemon sources never reference autotype', () {
    // Zero matches today; arms itself when the first daemon file lands.
    final daemonFiles = _rustSources(
      'rust/src',
    ).where((f) => _daemonPattern.hasMatch(f.path));
    for (final f in daemonFiles) {
      expect(
        f.readAsStringSync().contains('autotype'),
        isFalse,
        reason: '${f.path} references autotype',
      );
    }
  });

  test('daemon modules are declared behind cfg(target_os = "linux")', () {
    // cfg(unix) is not enough: it matches Android too, and the daemon must
    // never be compiled into the Android .so.
    final files = _rustSources('rust/src');
    expect(files, isNotEmpty, reason: 'empty listing checks nothing');
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_daemonMod.hasMatch(lines[i])) continue;
        final before = lines.sublist(0, i).reversed.take(3).join('\n');
        expect(
          before.contains('target_os = "linux"'),
          isTrue,
          reason:
              '${f.path}:${i + 1} declares a daemon module without '
              'cfg(target_os = "linux")',
        );
      }
    }
  });
}
