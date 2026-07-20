import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Error-localization net (item 4). Governs: a Rust error must not reach the user
// in English. The rule (see memory project_error_l10n_by_log_level): the
// localized part must carry the actionable MEANING; raw English is allowed only
// as a trailing technical detail, never as the whole message or the only
// meaningful words.
//
// This is a source scan, not a behavioural test: it finds every site that feeds
// a caught error's `.toString()` into user-visible text and classifies it. A
// site is OK only when the `e.toString()` is an argument to an approved,
// meaning-carrying localized template; otherwise it is a raw leak and must be
// listed in `_todoRawErrors` until fixed. A new, unlisted leak fails the test.
//
// The already-correct too-old-vault path (vaultFormatTooOld shown, not raw) is
// pinned behaviourally in test/unlock_screen_test.dart. Regressions elsewhere —
// e.g. reverting a mapped onboarding FIDO code to raw `e.toString()` — reappear
// as a scan site here, so they cannot slip through silently.

// Localized templates whose sentence states what happened; the interpolated
// error is trailing detail only. Adding a site wrapped in one of these is fine.
const Set<String> _approvedTemplates = {
  'failedToSaveAlias',
  'failedToRemoveKey',
  'failedToAddKey',
  'failedToRegisterKey',
  'failedToActivateKey',
  'exportFailed',
};

// `e.toString()` / `err.toString()` — a caught error rendered to a string. `\b`
// keeps `locale.toString()` / `buffer.toString()` from matching.
final RegExp _rawErrorToString = RegExp(r'\b(?:e|err)\.toString\(\)');

/// True when [line] surfaces a raw error string that is NOT wrapped in an
/// approved meaning-carrying template.
bool isRawErrorLine(String line) =>
    _rawErrorToString.hasMatch(line) &&
    !_approvedTemplates.any((t) => line.contains('$t('));

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
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (isRawErrorLine(lines[i])) {
        sites.add(_Site(path, i + 1, lines[i].trim()));
      }
    }
  }
  return sites;
}

// Sites that still leak a raw Rust error (Class A + the meaning-empty
// `errorPrefix("Error: {x}")` wrappers), by file -> count. Shrinks to empty as
// each is localized. A count change here is the point: a new leak must be added
// deliberately, and a fix must decrement the count.
const Map<String, int> _todoRawErrors = {
  'lib/screens/review_changes_screen.dart': 1,
  'lib/screens/manage_folders_screen.dart': 3,
  'lib/screens/onboarding_screen.dart': 1,
  'lib/screens/export_screen.dart': 1,
  'lib/screens/import_screen.dart': 6,
  'lib/screens/vault_list_screen.dart': 3,
  'lib/screens/security_screen.dart': 1,
  'lib/screens/csv_mapping_screen.dart': 1,
  'lib/screens/manage_yubikeys_screen.dart': 1,
  'lib/screens/change_passphrase_screen.dart': 1,
  'lib/screens/unlock_screen.dart': 1,
  'lib/screens/recovery_history_screen.dart': 1,
  'lib/screens/create_entry_screen.dart': 1,
};

void main() {
  // Guard on the guard: the classifier must flag a raw leak and clear an
  // approved template, or the scan below proves nothing.
  test('the classifier distinguishes a raw leak from an approved template', () {
    expect(isRawErrorLine('_error = e.toString();'), isTrue);
    expect(isRawErrorLine('setState(() => _error = err.toString());'), isTrue);
    expect(isRawErrorLine('Text(l.errorPrefix(e.toString()))'), isTrue,
        reason: 'errorPrefix is meaning-empty — must count as a leak');
    expect(isRawErrorLine('al.failedToAddKey(e.toString())'), isFalse);
    expect(isRawErrorLine('exportFailed(err.toString())'), isFalse);
    expect(isRawErrorLine('final text = buffer.toString();'), isFalse);
    expect(isRawErrorLine('locale.toString()'), isFalse);
  });

  // Enumerate + freeze. The set of raw-error sites in source must equal the
  // documented backlog exactly — no new untranslated leak, no stale entry.
  test('every raw-error site is accounted for', () {
    final sites = _scanRawErrorSites();
    final actual = <String, int>{};
    for (final s in sites) {
      actual[s.file] = (actual[s.file] ?? 0) + 1;
    }
    expect(
      actual,
      _todoRawErrors,
      reason: 'raw-error sites drifted from the backlog. Found:\n'
          '${sites.join('\n')}',
    );
  });
}
