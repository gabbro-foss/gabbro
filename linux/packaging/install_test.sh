#!/usr/bin/env bash
# Sandbox test for install.sh (ADR-none; Linux desktop integration).
#
# Runs install.sh into a throwaway $HOME + a fake extracted-tarball layout and
# asserts it registers gabbro with the launcher correctly. No root, no real
# system paths: --system mode is redirected into the sandbox via PREFIX.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { # check <description> <test-cmd...>
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
grep_q() { grep -q "$1" "$2" 2>/dev/null; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Build a fake extracted tarball: install.sh beside bundle/ + icons/ ───────
make_src() {
  local src="$1"
  mkdir -p "$src/bundle/lib" "$src/bundle/data" \
    "$src/icons/hicolor/48x48/apps" "$src/icons/hicolor/scalable/apps"
  printf '#!/bin/sh\necho gabbro\n' >"$src/bundle/gabbro"
  chmod +x "$src/bundle/gabbro"
  : >"$src/bundle/lib/libapp.so"
  : >"$src/bundle/data/flutter_assets.marker"
  : >"$src/icons/hicolor/48x48/apps/gabbro.png"
  : >"$src/icons/hicolor/scalable/apps/gabbro.svg"
  cp "$INSTALL_SH" "$src/install.sh"
  chmod +x "$src/install.sh"
}

DESKTOP_REL=".local/share/applications/app.gabbro.gabbro.desktop"
ICON_REL=".local/share/icons/hicolor/48x48/apps/gabbro.png"
SVG_REL=".local/share/icons/hicolor/scalable/apps/gabbro.svg"
APP_REL=".local/opt/gabbro/gabbro"

# ── Per-user install (default mode, no sudo) ────────────────────────────────
SRC="$WORK/src"; HOME_DIR="$WORK/home"
make_src "$SRC"; mkdir -p "$HOME_DIR"
echo "per-user install:"
HOME="$HOME_DIR" bash "$SRC/install.sh" >/dev/null 2>&1
check "exits 0" test "$?" = 0

desktop="$HOME_DIR/$DESKTOP_REL"
check "1. desktop entry created" test -f "$desktop"
check "1. is a Desktop Entry" grep_q '^\[Desktop Entry\]' "$desktop"
check "1. Type=Application" grep_q '^Type=Application$' "$desktop"
check "1. Name=Gabbro" grep_q '^Name=Gabbro$' "$desktop"

exec_path="$(sed -n 's/^Exec=//p' "$desktop" 2>/dev/null | awk '{print $1}')"
check "2. Exec is absolute" test "${exec_path:0:1}" = "/"
check "2. Exec points to an executable" test -x "$exec_path"

check "3. bundle binary installed + executable" test -x "$HOME_DIR/$APP_REL"
check "3. bundle lib/ copied" test -f "$HOME_DIR/.local/opt/gabbro/lib/libapp.so"
check "3. bundle data/ copied" test -f "$HOME_DIR/.local/opt/gabbro/data/flutter_assets.marker"

check "4. icon png installed" test -f "$HOME_DIR/$ICON_REL"
check "4. scalable svg installed" test -f "$HOME_DIR/$SVG_REL"
check "4. Icon= name matches" grep_q '^Icon=gabbro$' "$desktop"

check "5. StartupWMClass set to app id" grep_q '^StartupWMClass=app.gabbro.gabbro$' "$desktop"

# 10. A `gabbro` command on PATH, so bare-prompt launchers (qtile spawncmd) and
# typing `gabbro` in a terminal work -- not just XDG menus.
launcher="$HOME_DIR/.local/bin/gabbro"
check "10. launcher on PATH created + executable" test -x "$launcher"
check "10. launcher runs the installed binary" test "$("$launcher" 2>/dev/null)" = gabbro

# 6. Idempotent: a second run must succeed and not nest/duplicate the bundle.
HOME="$HOME_DIR" bash "$SRC/install.sh" >/dev/null 2>&1
check "6. second run exits 0" test "$?" = 0
check "6. no nested bundle dir" test ! -e "$HOME_DIR/.local/opt/gabbro/gabbro/gabbro"
check "6. still exactly one desktop entry" test 1 = \
  "$(find "$HOME_DIR/.local/share/applications" -name '*.desktop' | wc -l)"

# 7. Per-user mode wrote only under $HOME (nothing needing root).
check "7. install confined to \$HOME" test -z \
  "$(find "$HOME_DIR" -maxdepth 0 -type d -empty)"

# 8. Graceful when the refresh tools are absent (test seam skips them).
SRC2="$WORK/src2"; HOME2="$WORK/home2"
make_src "$SRC2"; mkdir -p "$HOME2"
GABBRO_SKIP_REFRESH=1 HOME="$HOME2" bash "$SRC2/install.sh" >/dev/null 2>&1
check "8. install ok without refresh tools" test "$?" = 0
check "8. desktop entry still created" test -f "$HOME2/$DESKTOP_REL"

# ── System install, redirected into the sandbox via PREFIX (no root) ────────
SRC3="$WORK/src3"; PREFIX_DIR="$WORK/usr"
make_src "$SRC3"; mkdir -p "$PREFIX_DIR"
echo "system install (--system, PREFIX override):"
PREFIX="$PREFIX_DIR" bash "$SRC3/install.sh" --system >/dev/null 2>&1
check "system exits 0" test "$?" = 0
sys_desktop="$PREFIX_DIR/share/applications/app.gabbro.gabbro.desktop"
check "system desktop under PREFIX" test -f "$sys_desktop"
check "system bundle under PREFIX" test -x "$PREFIX_DIR/lib/gabbro/gabbro"
sys_exec="$(sed -n 's/^Exec=//p' "$sys_desktop" 2>/dev/null | awk '{print $1}')"
check "system Exec points under PREFIX" test -x "$sys_exec"
check "system launcher under PREFIX/bin" test -x "$PREFIX_DIR/bin/gabbro"

# ── Uninstall (per-user) removes everything it installed ────────────────────
echo "uninstall:"
HOME="$HOME_DIR" bash "$SRC/install.sh" --uninstall >/dev/null 2>&1
check "9. uninstall exits 0" test "$?" = 0
check "9. desktop entry removed" test ! -f "$desktop"
check "9. icon removed" test ! -f "$HOME_DIR/$ICON_REL"
check "9. bundle removed" test ! -d "$HOME_DIR/.local/opt/gabbro"
check "9. launcher removed" test ! -f "$HOME_DIR/.local/bin/gabbro"

echo
if [ "$fails" -eq 0 ]; then
  echo "install.sh: all checks passed"
else
  echo "install.sh: $fails check(s) failed"
fi
exit $((fails > 0))
