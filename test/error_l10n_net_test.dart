import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A Rust error must not reach the user in English: raw text may only be a
// trailing detail inside a localized template that carries the meaning. A
// source scan: every `e.toString()` fed into user-visible text is classified,
// and a new unlisted leak fails.

// Localized templates whose sentence states what happened; the interpolated
// error is trailing detail only. Adding a site wrapped in one of these is fine.
const Set<String> _approvedTemplates = {
  'failedToSaveAlias',
  'failedToRemoveKey',
  'failedToAddKey',
  'failedToRegisterKey',
  'failedToActivateKey',
  'exportFailed',
  'importFailed',
  'folderActionFailed',
  'syncFailed',
  'vaultLoadFailed',
  'saveEntryFailed',
  'changePassphraseFailed',
  'recoveryActionFailed',
  'setupFailed',
  'biometricEnrollFailed',
  'restoreBackupFailed',
};

// `e.toString()` / `err.toString()` - a caught error rendered to a string. `\b`
// keeps `locale.toString()` / `buffer.toString()` from matching.
final RegExp _rawErrorToString = RegExp(r'\b(?:e|err)\.toString\(\)');

/// The statement text around [index] in [src] - from the previous `;`/`{`/`}` to
/// the next. So a template call and its `e.toString()` argument are seen together
/// even when a formatter wraps them onto separate lines.
String _enclosingStatement(String src, int index) {
  var start = index;
  while (start > 0 && !';{}'.contains(src[start - 1])) {
    start--;
  }
  var end = index;
  while (end < src.length && !';{}'.contains(src[end])) {
    end++;
  }
  return src.substring(start, end);
}

/// True when [statement] surfaces a raw error string that is NOT an argument to
/// an approved meaning-carrying template.
bool _isRawError(String statement) =>
    _rawErrorToString.hasMatch(statement) &&
    !_approvedTemplates.any((t) => statement.contains('$t('));

class _Site {
  final String file;
  final int line;
  final String text;
  const _Site(this.file, this.line, this.text);
  @override
  String toString() => '$file:$line  $text';
}

/// Every raw-error site under lib/, excluding generated bridge and l10n code.
List<_Site> _scanRawErrorSites() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    fail('lib/ does not exist — the scan would pass vacuously');
  }
  final sites = <_Site>[];
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final path = f.path;
    if (!path.endsWith('.dart')) continue;
    if (path.contains('/src/rust/') || path.contains('/l10n/')) continue;
    final src = f.readAsStringSync();
    for (final m in _rawErrorToString.allMatches(src)) {
      if (_isRawError(_enclosingStatement(src, m.start))) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        final lineText =
            src.substring(m.start).split('\n').first.trim();
        sites.add(_Site(path, line, lineText));
      }
    }
  }
  return sites;
}

// Sites that still leak a raw Rust error (Class A + the meaning-empty
// `errorPrefix("Error: {x}")` wrappers), by file -> count. Shrinks to empty as
// each is localized. A count change here is the point: a new leak must be added
// deliberately, and a fix must decrement the count.
const Map<String, int> _todoRawErrors = <String, int>{
  // Empty: every raw Rust error reaching the user is now behind a
  // meaning-carrying localized template. New leaks fail the test below.
};

// Reviewed non-leaks: the string feeds a `contains` branch only, or a field
// that a template wraps at build time (initState runs before
// AppLocalizations is available).
const Map<String, int> _notADisplayLeak = {
  // vault_list: 408 `_error` set in _loadEntries (initState) is shown via
  // `vaultLoadFailed(_error!)` at build; 994 `msg` feeds a
  // `contains('decryption failed')` branch and the dialog shows `syncFailed(msg)`.
  'lib/screens/vault_list_screen.dart': 2,
  // manage_yubikeys: 152 `_error` set in _load (initState) is shown via
  // `manageYubiKeysError(_error!)` = "Couldn't load YubiKeys: {error}" at build.
  'lib/screens/manage_yubikeys_screen.dart': 1,
};

void main() {
  // Guard on the guard: the classifier must flag a raw leak and clear an
  // approved template, or the scan below proves nothing.
  test('the classifier distinguishes a raw leak from an approved template', () {
    expect(_isRawError('_error = e.toString();'), isTrue);
    expect(_isRawError('setState(() => _error = err.toString());'), isTrue);
    expect(_isRawError('Text(l.errorPrefix(e.toString()))'), isTrue,
        reason: 'errorPrefix is meaning-empty — must count as a leak');
    expect(_isRawError('al.failedToAddKey(e.toString())'), isFalse);
    expect(_isRawError('l.importFailed(e.toString())'), isFalse);
    expect(_isRawError('exportFailed(err.toString())'), isFalse);
    expect(_isRawError('final text = buffer.toString();'), isFalse);
    expect(_isRawError('locale.toString()'), isFalse);
    // Statement-scoped: a template wrapping split across lines is still OK.
    expect(
      _isRawError('_enpassError = context.importFailed(\n  e.toString(),\n)'),
      isFalse,
    );
  });

  // Enumerate + freeze. Every raw `e.toString()` in source must be accounted
  // for - either in the leak backlog or as a reviewed non-leak. No new
  // untranslated leak, no stale entry.
  test('every raw-error site is accounted for', () {
    final sites = _scanRawErrorSites();
    final actual = <String, int>{};
    for (final s in sites) {
      actual[s.file] = (actual[s.file] ?? 0) + 1;
    }
    final expected = <String, int>{};
    for (final e in _todoRawErrors.entries) {
      expected[e.key] = (expected[e.key] ?? 0) + e.value;
    }
    for (final e in _notADisplayLeak.entries) {
      expected[e.key] = (expected[e.key] ?? 0) + e.value;
    }
    expect(
      actual,
      expected,
      reason: 'raw-error sites drifted from the backlog. Found:\n'
          '${sites.join('\n')}',
    );
  });
}
