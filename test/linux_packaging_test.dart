import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nets for the Linux packaging scripts (deb + AUR). Content pins only: Arch
/// has no dpkg-deb, so the real end-to-end net is the release container run.
/// These fail fast and name the reason if the staging layout, metadata, or
/// the shared desktop entry drifts.

String _debScript() =>
    File('linux/packaging/deb/build-deb.sh').readAsStringSync();

String _pkgbuild() => File('linux/packaging/aur/PKGBUILD').readAsStringSync();

/// The body of a `<<'TAG'`-style heredoc: lines after the opener up to the
/// terminator line, which must be the tag alone (leading whitespace allowed,
/// as in PKGBUILD's indented `package()` body).
String _heredocBody(String script, String tag) {
  final lines = script.split('\n');
  final start = lines.indexWhere((l) => l.contains("<<'$tag'"));
  expect(start, isNot(-1), reason: "heredoc <<'$tag' not found");
  final rest = lines.sublist(start + 1);
  final end = rest.indexWhere((l) => l.trim() == tag);
  expect(end, isNot(-1), reason: "heredoc terminator $tag not found");
  return rest.sublist(0, end).join('\n');
}

void main() {
  group('build-deb.sh', () {
    test('stages the bundle to /usr/lib/gabbro with an executable binary', () {
      final s = _debScript();
      expect(s, contains('install -dm755 "\$root/usr/lib/gabbro"'));
      expect(s, contains('cp -r "\$bundle/." "\$root/usr/lib/gabbro/"'));
      expect(s, contains('chmod 755 "\$root/usr/lib/gabbro/gabbro"'));
    });

    test('installs a /usr/bin/gabbro wrapper that execs the bundle binary', () {
      final s = _debScript();
      expect(s, contains('cat > "\$root/usr/bin/gabbro"'));
      expect(_heredocBody(s, 'SH'), contains('exec /usr/lib/gabbro/gabbro'));
      expect(s, contains('chmod 755 "\$root/usr/bin/gabbro"'));
    });

    test('stages icons and the desktop entry', () {
      final s = _debScript();
      expect(s, contains('cp -r "\$icons" "\$root/usr/share/icons/"'));
      expect(
        s,
        contains(
          'cat > "\$root/usr/share/applications/app.gabbro.gabbro.desktop"',
        ),
      );
    });

    test('reads the copyright holder from the repo LICENSE, never inline', () {
      final s = _debScript();
      expect(s, contains(r'"$REPO_ROOT/LICENSE"'));
      expect(
        s,
        contains('could not read copyright holder'),
        reason: 'an unreadable LICENSE must fail the build, not ship blank',
      );
    });

    test('control has the package name and runtime Depends', () {
      final s = _debScript();
      expect(s, contains('Package: gabbro'));
      expect(
        s,
        contains(
          'Depends: libc6, libgtk-3-0t64, libfido2-1, libcbor0.10, '
          'libpcsclite1',
        ),
      );
    });

    test('transforms upstream 0.1.0-alpha.N to Debian 0.1.0~alpha.N-1', () {
      final s = _debScript();
      expect(s, contains(r'deb_upstream="${version/-/\~}"'));
      expect(s, contains(r'deb_ver="${deb_upstream}-1"'));
    });

    test('accepts --tarball, --bundle and --out', () {
      final s = _debScript();
      expect(s, contains('--tarball) tarball="\$2"'));
      expect(s, contains('--bundle)  bundle="\$2"'));
      expect(s, contains('--out)     out="\$2"'));
    });
  });

  group('PKGBUILD', () {
    test('sources tarball and LICENSE from the _pkgver release tag', () {
      final s = _pkgbuild();
      expect(s, contains(r'_pkgver=${pkgver//_/-}'));
      expect(
        s,
        contains(
          r'${url}/releases/download/v${_pkgver}/'
          r'gabbro-${_pkgver}-linux-x86_64.tar.gz',
        ),
      );
      expect(s, contains(r'gabbro/v${_pkgver}/LICENSE'));
    });

    test('stages the same /usr layout as the deb', () {
      final s = _pkgbuild();
      expect(s, contains('install -dm755 "\$pkgdir/usr/lib/gabbro"'));
      expect(s, contains('cp -r "\$srcdir/bundle/." "\$pkgdir/usr/lib/gabbro/"'));
      expect(s, contains('chmod 755 "\$pkgdir/usr/lib/gabbro/gabbro"'));
      expect(s, contains('cat > "\$pkgdir/usr/bin/gabbro"'));
      expect(s, contains('chmod 755 "\$pkgdir/usr/bin/gabbro"'));
      expect(
        s,
        contains('cp -r "\$srcdir/icons/hicolor" "\$pkgdir/usr/share/icons/"'),
      );
    });

    test('declares provides/conflicts gabbro and keeps the bundle unstripped',
        () {
      final s = _pkgbuild();
      expect(s, contains("provides=('gabbro')"));
      expect(s, contains("conflicts=('gabbro')"));
      expect(s, contains("options=('!strip' '!debug')"));
    });

    test('installs the repo LICENSE as the package licence', () {
      expect(
        _pkgbuild(),
        contains(
          r'install -Dm644 "$srcdir/LICENSE" '
          r'"$pkgdir/usr/share/licenses/$pkgname/LICENSE"',
        ),
      );
    });
  });

  test('desktop entry is byte-identical across build-deb.sh and PKGBUILD', () {
    expect(
      _heredocBody(_debScript(), 'DESK'),
      _heredocBody(_pkgbuild(), 'DESK'),
    );
  });
}
