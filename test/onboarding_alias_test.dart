// Unit tests for sanitiseVaultAlias - the function the onboarding alias-path
// auto-sync feeds straight into `<dataDir>/<stem>_gabbro.gabbro`. The security
// property under test: a user-entered alias can never inject a path separator or
// `..` traversal into the generated vault path. (The UI wiring that calls it on
// each alias keystroke - listener -> setState -> keyed PathField rebuild - is
// trivial glue; the real flaw surface is the sanitisation itself.)

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/onboarding_screen.dart';

void main() {
  test('lowercases and turns spaces into underscores', () {
    expect(sanitiseVaultAlias('My Vault'), 'my_vault');
    expect(sanitiseVaultAlias('  Trimmed  '), 'trimmed');
  });

  test('strips path separators and .. so the alias cannot escape the data dir', () {
    expect(sanitiseVaultAlias('../../etc/passwd'), 'etcpasswd');
    expect(sanitiseVaultAlias('a/b\\c'), 'abc');
    expect(sanitiseVaultAlias('..'), 'vault');
    // The result, dropped into '<dir>/<stem>_gabbro.gabbro', contains no separator.
    expect(sanitiseVaultAlias('../../evil').contains('/'), isFalse);
    expect(sanitiseVaultAlias('../../evil').contains('.'), isFalse);
  });

  test('keeps digits, hyphen and underscore; drops other punctuation', () {
    expect(sanitiseVaultAlias('Work-Stuff!@#'), 'work-stuff');
    expect(sanitiseVaultAlias('a_b-1'), 'a_b-1');
  });

  test('empty or all-stripped input falls back to "vault"', () {
    expect(sanitiseVaultAlias(''), 'vault');
    expect(sanitiseVaultAlias('   '), 'vault');
    expect(sanitiseVaultAlias('!@#%^&*'), 'vault');
  });
}
