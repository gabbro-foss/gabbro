#!/usr/bin/env bash
# Build a binary .deb for Gabbro by repackaging the prebuilt Flutter Linux bundle
# (no compilation). Attach the result to the GitHub Release; users install with:
#   sudo apt install ./gabbro_<ver>_amd64.deb
#
# Runs inside a Debian environment (dpkg-deb required) -- e.g. a `debian:trixie`
# container with the repo mounted. See BUILD_AND_RELEASE.md.
#
# Usage:
#   build-deb.sh --version <upstream-ver> [--tarball <gabbro-*-linux-x86_64.tar.gz>] [--out <dir>]
#   build-deb.sh --version <upstream-ver> --bundle <bundle-dir> [--icons <hicolor-dir>] [--out <dir>]
#
# With neither --tarball nor --bundle, downloads the release tarball for --version
# from GitHub (needs curl). --bundle/--icons feed a locally built bundle at release time.
set -euo pipefail

REPO_URL="https://github.com/gabbro-foss/gabbro"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"   # linux/packaging/deb -> repo root

version=""; tarball=""; bundle=""; icons=""; out="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --tarball) tarball="$2"; shift 2 ;;
    --bundle)  bundle="$2";  shift 2 ;;
    --icons)   icons="$2";   shift 2 ;;
    --out)     out="$2";     shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "build-deb.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$version" ] || { echo "build-deb.sh: need --version (e.g. 0.1.0-alpha.15)" >&2; exit 2; }

# Debian version: upstream '0.1.0-alpha.15' -> '0.1.0~alpha.15' (~ sorts BEFORE the
# release '0.1.0', correct for a pre-release) + '-1' debian revision.
deb_upstream="${version/-/\~}"
deb_ver="${deb_upstream}-1"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
root="$work/pkgroot"

# --- obtain the bundle + icons ---
if [ -z "$tarball" ] && [ -z "$bundle" ]; then
  tarball="$work/src.tar.gz"
  echo "Downloading release tarball for v$version ..."
  curl -fL "$REPO_URL/releases/download/v${version}/gabbro-${version}-linux-x86_64.tar.gz" -o "$tarball"
fi
if [ -n "$tarball" ]; then
  tar -xzf "$tarball" -C "$work"
  bundle="$work/bundle"
  [ -z "$icons" ] && icons="$work/icons/hicolor"
fi
[ -d "$bundle" ] || { echo "build-deb.sh: bundle dir not found: $bundle" >&2; exit 1; }
[ -d "$icons" ]  || { echo "build-deb.sh: icons hicolor dir not found: $icons" >&2; exit 1; }

# --- stage the file tree under /usr ---
install -dm755 "$root/usr/lib/gabbro"
cp -r "$bundle/." "$root/usr/lib/gabbro/"
chmod 755 "$root/usr/lib/gabbro/gabbro"

install -dm755 "$root/usr/bin"
cat > "$root/usr/bin/gabbro" <<'SH'
#!/bin/sh
exec /usr/lib/gabbro/gabbro "$@"
SH
chmod 755 "$root/usr/bin/gabbro"

install -dm755 "$root/usr/share/icons"
cp -r "$icons" "$root/usr/share/icons/"

install -dm755 "$root/usr/share/applications"
cat > "$root/usr/share/applications/app.gabbro.gabbro.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Gabbro
GenericName=Password Manager
Comment=Quantum-resistant password manager
Exec=/usr/bin/gabbro
Icon=gabbro
Terminal=false
Categories=Utility;Security;
Keywords=password;vault;passphrase;security;
StartupWMClass=app.gabbro.gabbro
DESK

# Debian doc dir: a DEP-5 copyright that keeps the maintainer copyright line but points at
# the system GPL-3 text (don't duplicate it), plus a minimal changelog. The holder is read
# from the repo LICENSE so this script carries no personal name.
install -dm755 "$root/usr/share/doc/gabbro"
holder="$(grep -m1 -iE '^copyright \(c\) ' "$REPO_ROOT/LICENSE" | sed -E 's/^[Cc]opyright \([Cc]\) //')"
[ -n "$holder" ] || { echo "build-deb.sh: could not read copyright holder from LICENSE" >&2; exit 1; }
cat > "$root/usr/share/doc/gabbro/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Gabbro
Source: ${REPO_URL}

Files: *
Copyright: ${holder}
License: GPL-3.0-only
 This program is free software: you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation, version 3 of the License.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 .
 On Debian systems, the full text of the GNU General Public License version 3
 can be found in /usr/share/common-licenses/GPL-3.
CR

cat > "$work/changelog.Debian" <<CL
gabbro (${deb_ver}) unstable; urgency=medium

  * Release ${version}. Full notes: ${REPO_URL}/releases/tag/v${version}

 -- Gabbro <gabbro@tuta.com>  $(date -R)
CL
gzip -9n < "$work/changelog.Debian" > "$root/usr/share/doc/gabbro/changelog.Debian.gz"

# --- control ---
installed_kb="$(du -sk "$root/usr" | cut -f1)"
install -dm755 "$root/DEBIAN"
cat > "$root/DEBIAN/control" <<CTRL
Package: gabbro
Version: ${deb_ver}
Architecture: amd64
Maintainer: Gabbro <gabbro@tuta.com>
Installed-Size: ${installed_kb}
Depends: libc6, libgtk-3-0t64, libfido2-1, libcbor0.10, libpcsclite1
Recommends: xdg-desktop-portal-gtk
Suggests: pcscd
Section: utils
Priority: optional
Homepage: ${REPO_URL}
Description: Quantum-resistant password manager
 Gabbro is a cross-platform, local-only password manager. All keys and
 cryptography live in Rust; the vault is decrypted there and the master keys
 never leave it. Vaults are encrypted at rest with Argon2id, HKDF-SHA256 and
 AES-256-GCM. A FIDO2/WebAuthn hardware key (e.g. YubiKey) is supported but not
 required. Includes an optional Linux auto-type helper.
CTRL

# --- build ---
deb_name="gabbro_${deb_ver}_amd64.deb"
mkdir -p "$out"
dpkg-deb --root-owner-group --build "$root" "$out/$deb_name"
echo "Built: $out/$deb_name"
