import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// lib/ may never read a FocusNode's debugLabel: Flutter assigns it inside an
// assert, so it is null in release and code keyed on it works under
// `flutter test` and silently does nothing on a real machine. Writing a
// label is fine.
List<File> _sourceFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Drop a trailing line comment so a doc/comment mention of the name is not a
/// hit - only real code counts.
String _stripComment(String line) {
  final i = line.indexOf('//');
  return i < 0 ? line : line.substring(0, i);
}

/// True when [line] READS a debugLabel. The named-argument form (writing one at
/// construction) is removed first, so only a read survives.
bool _readsDebugLabel(String line) => _stripComment(line)
    .replaceAll(RegExp(r'debugLabel\s*:'), '')
    .contains('debugLabel');

void main() {
  test('the scan finds source files, so the net is not vacuous', () {
    expect(_sourceFiles().length, greaterThan(50));
  });

  test('the read check flags a read and allows a write or a comment', () {
    // Guard on the guard: a green sweep proves nothing if the predicate is
    // blind to the pattern it exists to catch.
    expect(_readsDebugLabel('final lbl = scope.debugLabel ?? "";'), isTrue);
    expect(_readsDebugLabel('if (n.debugLabel!.startsWith("region:")) {'), isTrue);
    expect(
      _readsDebugLabel("final s = FocusScopeNode(debugLabel: 'region:list');"),
      isFalse,
    );
    expect(_readsDebugLabel('// identity, not the debugLabel (null in release)'), isFalse);
  });

  test('no production file under lib/ reads a FocusNode debugLabel', () {
    final offenders = <String>[
      for (final f in _sourceFiles())
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (_readsDebugLabel(line)) '${f.path}:${i + 1}',
    ]..sort();
    expect(
      offenders,
      isEmpty,
      reason: 'debugLabel read in:\n  ${offenders.join('\n  ')}\n'
          'debugLabel is null in RELEASE builds — this works in tests and '
          'fails on the user machine. Identify the node by identity instead.',
    );
  });
}
