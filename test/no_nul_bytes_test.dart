import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Repo-hygiene net: no source file under lib/ may contain a NUL byte. A stray
// NUL makes grep treat the whole file as binary and silently return nothing
// (this hid a real search over sync_review.dart), and — as a key/string
// separator — is a latent "won't match a normally-typed string" trap.
List<File> _sourceFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.arb'))
    .toList();

void main() {
  test('the scan finds source files, so the net is not vacuous', () {
    expect(_sourceFiles().length, greaterThan(50));
  });

  test('the NUL check flags a NUL and passes clean bytes', () {
    // Guard on the guard: the predicate used below must catch a NUL and only a
    // NUL, or a green sweep proves nothing.
    expect(<int>[0x41, 0x00, 0x42].contains(0), isTrue);
    expect(<int>[0x41, 0x42, 0x43].contains(0), isFalse);
  });

  test('no source file under lib/ contains a NUL byte', () {
    final offenders = <String>[
      for (final f in _sourceFiles())
        if (f.readAsBytesSync().contains(0)) f.path,
    ]..sort();
    expect(
      offenders,
      isEmpty,
      reason: 'NUL byte in:\n  ${offenders.join('\n  ')}\n'
          'grep treats these as binary and silently returns nothing.',
    );
  });
}
