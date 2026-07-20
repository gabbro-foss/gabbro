#!/usr/bin/env bash
# Install Gabbro's launcher entry + icons on Linux (XDG desktop integration).
#
# A Flutter Linux app is a self-contained bundle (the `gabbro` binary plus
# `lib/` and `data/`) that must stay together, so this copies the whole bundle
# to a stable location and writes a `.desktop` entry pointing at it -- extracting
# the tarball alone never registers anything with the launcher.
#
#   ./install.sh              per-user install, no root (~/.local)
#   sudo ./install.sh --system   system-wide (/usr, honours $PREFIX)
#   ./install.sh --uninstall     remove a per-user install (--system to undo one)
#
# $PREFIX overrides the --system prefix (default /usr); used by the test harness
# to redirect a system install into a sandbox without root.
set -eu

APP_ID="app.gabbro.gabbro"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

system=0
uninstall=0
for arg in "$@"; do
  case "$arg" in
    --system) system=1 ;;
    --uninstall) uninstall=1 ;;
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
    -h | --help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: unknown option '$arg'" >&2
      exit 2
      ;;
  esac
done

# Resolve install locations from the mode.
if [ "$system" -eq 1 ]; then
  prefix="${PREFIX:-/usr}"
  app_dir="$prefix/lib/gabbro"
  data_dir="$prefix/share"
  bin_dir="$prefix/bin"
else
  app_dir="$HOME/.local/opt/gabbro"
  data_dir="$HOME/.local/share"
  bin_dir="$HOME/.local/bin"
fi
desktop="$data_dir/applications/$APP_ID.desktop"
icon_root="$data_dir/icons/hicolor"
launcher="$bin_dir/gabbro"

# Best-effort launcher/icon cache refresh; never fails the install, and skipped
# entirely when the tools are absent (or GABBRO_SKIP_REFRESH is set, for tests).
refresh() {
  [ -n "${GABBRO_SKIP_REFRESH:-}" ] && return 0
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$icon_root" >/dev/null 2>&1 || true
  fi
}

if [ "$uninstall" -eq 1 ]; then
  rm -f "$desktop"
  rm -f "$launcher"
  find "$icon_root" -name 'gabbro.*' -delete 2>/dev/null || true
  rm -rf "$app_dir"
  refresh
  echo "Gabbro removed."
  exit 0
fi

# ── Install ─────────────────────────────────────────────────────────────────
# Bundle: wipe any prior copy first so a re-run overwrites cleanly instead of
# nesting bundle/gabbro under an existing directory.
mkdir -p "$(dirname "$app_dir")"
rm -rf "$app_dir"
cp -r "$SRC_DIR/bundle" "$app_dir"
chmod +x "$app_dir/gabbro"

# Icons: copy the whole hicolor tree shipped in the tarball (size-agnostic).
mkdir -p "$icon_root"
cp -r "$SRC_DIR/icons/hicolor/." "$icon_root/"

# Desktop entry, with Exec pointing at the installed bundle's binary.
mkdir -p "$data_dir/applications"
cat >"$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Gabbro
GenericName=Password Manager
Comment=Quantum-resistant password manager
Exec=$app_dir/gabbro
Icon=gabbro
Terminal=false
Categories=Utility;Security;
Keywords=password;vault;passphrase;security;
StartupWMClass=$APP_ID
EOF

# A `gabbro` command on PATH. XDG menus (Mint's, GNOME's) read the .desktop
# above, but bare-prompt launchers (qtile's spawncmd) and terminals need an
# actual command -- a wrapper that execs the bundle's binary in place.
mkdir -p "$bin_dir"
cat >"$launcher" <<EOF
#!/bin/sh
exec "$app_dir/gabbro" "\$@"
EOF
chmod +x "$launcher"

refresh
echo "Gabbro installed. Launch it from your application menu, or run 'gabbro'."
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "Note: $bin_dir is not on your PATH; add it to run 'gabbro' by name." ;;
esac
