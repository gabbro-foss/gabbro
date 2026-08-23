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

/// The single non-comment, non-blank line of a config file.
String _soleContentLine(String path) {
  final lines = File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
      .toList();
  expect(lines, hasLength(1), reason: '$path: exactly one content line');
  return lines.single;
}

/// Body of a `name() { ... }` shell function: lines after the opener up to
/// the first line that is `}` alone.
String _shellFunctionBody(String script, String name) {
  final lines = script.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('$name()'));
  expect(start, isNot(-1), reason: 'function $name not found');
  final rest = lines.sublist(start + 1);
  final end = rest.indexWhere((l) => l.trim() == '}');
  expect(end, isNot(-1), reason: 'closing brace of $name not found');
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

  group('uhid packaging', () {
    test('canonical udev rule grants the seated user access to /dev/uhid', () {
      // Without this rule /dev/uhid stays root-only and Linux passkeys
      // silently do nothing.
      final rules = File(
        'linux/packaging/udev/70-gabbro-uhid.rules',
      ).readAsStringSync();
      final line = rules
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
          .toList();
      expect(line, hasLength(1), reason: 'exactly one rule line');
      expect(line.single, contains('KERNEL=="uhid"'));
      expect(line.single, contains('SUBSYSTEM=="misc"'));
      expect(line.single, contains('TAG+="uaccess"'));
    });

    test('canonical modules-load conf loads exactly the uhid module', () {
      // Without the uhid module /dev/uhid does not exist and Linux passkeys
      // silently do nothing.
      final conf = File(
        'linux/packaging/modules-load.d/gabbro-uhid.conf',
      ).readAsStringSync();
      final line = conf
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
          .toList();
      expect(line, hasLength(1), reason: 'exactly one module line');
      expect(line.single, 'uhid');
    });

    test('build-deb.sh stages the canonical rule and conf under /usr/lib', () {
      // Package-owned paths: apt remove rolls them back with no scriptlet.
      final s = _debScript();
      expect(
        s,
        contains(
          r'install -Dm644 "$REPO_ROOT/linux/packaging/udev/'
          r'70-gabbro-uhid.rules" '
          r'"$root/usr/lib/udev/rules.d/70-gabbro-uhid.rules"',
        ),
      );
      expect(
        s,
        contains(
          r'install -Dm644 "$REPO_ROOT/linux/packaging/modules-load.d/'
          r'gabbro-uhid.conf" '
          r'"$root/usr/lib/modules-load.d/gabbro-uhid.conf"',
        ),
      );
    });

    test('build-deb.sh postinst activates uhid now; postrm reloads udev', () {
      // Without postinst the user must reboot before passkeys work; each
      // command tolerates containers (no udev/modprobe) via || true.
      final s = _debScript();
      final postinst = _heredocBody(s, 'POSTINST');
      expect(postinst, contains('udevadm control --reload || true'));
      expect(postinst, contains('modprobe uhid || true'));
      expect(postinst, contains('udevadm trigger --name-match=uhid || true'));
      final postrm = _heredocBody(s, 'POSTRM');
      expect(postrm, contains('udevadm control --reload || true'));
      expect(postrm, isNot(contains('modprobe')));
      expect(
        s,
        contains(r'chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"'),
      );
    });

    test('PKGBUILD installs the uhid rule + conf and declares install hooks',
        () {
      // The AUR package builds from the release tarball (which has neither
      // file), so PKGBUILD embeds them inline like the desktop entry.
      final s = _pkgbuild();
      expect(s, contains('install=gabbro-bin.install'));
      expect(
        s,
        contains(r'"$pkgdir/usr/lib/udev/rules.d/70-gabbro-uhid.rules"'),
      );
      expect(
        s,
        contains(r'"$pkgdir/usr/lib/modules-load.d/gabbro-uhid.conf"'),
      );
    });

    test('gabbro-bin.install activates uhid on install/upgrade, remove only '
        'reloads', () {
      final s = File(
        'linux/packaging/aur/gabbro-bin.install',
      ).readAsStringSync();
      final install = _shellFunctionBody(s, 'post_install');
      expect(install, contains('udevadm control --reload || true'));
      expect(install, contains('modprobe uhid || true'));
      expect(install, contains('udevadm trigger --name-match=uhid || true'));
      expect(_shellFunctionBody(s, 'post_upgrade'), contains('post_install'));
      final remove = _shellFunctionBody(s, 'post_remove');
      expect(remove, contains('udevadm control --reload || true'));
      expect(remove, isNot(contains('modprobe')));
    });

    test('rule and conf payloads are byte-identical everywhere they appear',
        () {
      // Canonical files are the source of truth; PKGBUILD embeds copies and
      // README tells tarball users to write them with sudo tee. A drifted
      // copy means one install channel silently gets a different device
      // policy.
      final rule = _soleContentLine('linux/packaging/udev/70-gabbro-uhid.rules');
      final conf = _soleContentLine(
        'linux/packaging/modules-load.d/gabbro-uhid.conf',
      );
      final pkgbuild = _pkgbuild();
      expect(_heredocBody(pkgbuild, 'RULES'), rule);
      expect(_heredocBody(pkgbuild, 'CONF'), conf);
      final readme = File('README.md').readAsStringSync();
      expect(
        readme,
        contains(
          "echo '$rule' | sudo tee /etc/udev/rules.d/70-gabbro-uhid.rules",
        ),
      );
      expect(
        readme,
        contains(
          "echo '$conf' | sudo tee /etc/modules-load.d/gabbro-uhid.conf",
        ),
      );
    });

    test('README has tarball uhid install AND uninstall steps', () {
      // Package channels roll the files back on removal; tarball users must
      // do it by hand or the rule outlives the app.
      final readme = File('README.md').readAsStringSync();
      expect(
        readme,
        contains(
          'sudo udevadm control --reload && sudo modprobe uhid && '
          'sudo udevadm trigger --name-match=uhid',
        ),
      );
      expect(
        readme,
        contains(
          'sudo rm /etc/udev/rules.d/70-gabbro-uhid.rules '
          '/etc/modules-load.d/gabbro-uhid.conf',
        ),
      );
      expect(readme, contains('modprobe -r uhid'));
    });
  });

  test('desktop entry is byte-identical across build-deb.sh and PKGBUILD', () {
    expect(
      _heredocBody(_debScript(), 'DESK'),
      _heredocBody(_pkgbuild(), 'DESK'),
    );
  });
}
