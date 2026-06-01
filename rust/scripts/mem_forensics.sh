#!/usr/bin/env bash
#
# Memory-forensics self-test (audit L-6 / Appendix C item 6).
#
# Empirically verifies that secrets are scrubbed from gabbro's process memory
# when a vault is locked. Drives the `mem_forensics` harness, takes a `gcore`
# dump while UNLOCKED and again while LOCKED, and greps both dumps for two
# distinct high-entropy canaries: one used as the master passphrase (validates
# Zeroizing + lock_vault) and one used as a Login entry's password (validates
# ZeroizeOnDrop on VaultEntry). Neither canary touches disk in plaintext or argv.
#
# Usage (from the rust/ directory):
#   cargo build --release --features forensics --bin mem_forensics
#   scripts/mem_forensics.sh
#
# Exit: 0 = PASS (canary present unlocked, absent locked)
#       1 = FAIL (canary still recoverable after lock)
#       2 = INCONCLUSIVE (canary not even found unlocked — methodology broken)
#
# No sudo required: the harness calls prctl(PR_SET_PTRACER_ANY) so gcore can
# attach despite yama ptrace_scope=1.
set -euo pipefail

BIN="${BIN:-target/release/mem_forensics}"
if [[ ! -x "$BIN" ]]; then
  echo "harness not built. Run:" >&2
  echo "  cargo build --release --features forensics --bin mem_forensics" >&2
  exit 1
fi
command -v gcore >/dev/null || { echo "gcore not found (install gdb)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
VAULT="$WORK/forensics.gabbro"

# Two distinct high-entropy canaries, alphanumeric so they grep cleanly in a
# binary dump: PASS = the master passphrase, ENTRY = a Login entry's password.
rnd() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48; }
PASS_CANARY="PASSCANARY_$(rnd)"
ENTRY_CANARY="ENTRYCANARY_$(rnd)"

# 1) Seal the vault in a separate short-lived process (its plaintext dies with it).
#    Line 1 = passphrase canary, line 2 = entry-password canary.
printf '%s\n%s\n' "$PASS_CANARY" "$ENTRY_CANARY" | "$BIN" create "$VAULT"

# 2) Drive the test process over a coprocess pipe.
coproc TST { "$BIN" test "$VAULT"; }
printf '%s\n' "$PASS_CANARY" >&"${TST[1]}"   # passphrase canary on stdin (line 1)

read -r tag PID <&"${TST[0]}"                # expect: UNLOCKED <pid>
[[ "$tag" == "UNLOCKED" ]] || { echo "protocol error: got '$tag', expected UNLOCKED" >&2; exit 1; }

# 3) Dump while UNLOCKED — canary MUST be present (proves the grep can see a leak).
gcore -o "$WORK/core_unlocked" "$PID" >/dev/null 2>&1
printf 'go\n' >&"${TST[1]}"                  # release: lock the vault

read -r tag <&"${TST[0]}"                    # expect: LOCKED
[[ "$tag" == "LOCKED" ]] || { echo "protocol error: got '$tag', expected LOCKED" >&2; exit 1; }

# 4) Dump while LOCKED — canary MUST be gone (proves Zeroize scrubbed it).
gcore -o "$WORK/core_locked" "$PID" >/dev/null 2>&1
printf 'go\n' >&"${TST[1]}"                  # release: exit
read -r _ <&"${TST[0]}" || true              # EXIT
wait "$TST_PID" 2>/dev/null || true

# 5) Analyse the two dumps for both canaries.
hits() { grep -c -a -F -- "$1" "$2" 2>/dev/null || true; }
U="$WORK/core_unlocked.$PID"
L="$WORK/core_locked.$PID"

PU="$(hits "$PASS_CANARY"  "$U")"; PL="$(hits "$PASS_CANARY"  "$L")"
EU="$(hits "$ENTRY_CANARY" "$U")"; EL="$(hits "$ENTRY_CANARY" "$L")"
PU="${PU:-0}"; PL="${PL:-0}"; EU="${EU:-0}"; EL="${EL:-0}"

printf '%s\n' "------------------------------------------------------------"
printf '  %-24s unlocked=%-3s locked=%-3s  (want >=1 / 0)\n' "passphrase canary:" "$PU" "$PL"
printf '  %-24s unlocked=%-3s locked=%-3s  (want >=1 / 0)\n' "entry-password canary:" "$EU" "$EL"
printf '%s\n' "------------------------------------------------------------"

if [[ "$PU" -lt 1 || "$EU" -lt 1 ]]; then
  echo "INCONCLUSIVE: a canary was not found even while unlocked — the test cannot detect a leak."
  [[ "$PU" -lt 1 ]] && echo "  - passphrase canary missing (unlock path?)"
  [[ "$EU" -lt 1 ]] && echo "  - entry canary missing (entry not persisted/decrypted?)"
  exit 2
elif [[ "$PL" -ne 0 || "$EL" -ne 0 ]]; then
  echo "FAIL: a secret is still recoverable from memory after lock:"
  [[ "$PL" -ne 0 ]] && echo "  - passphrase ($PL hits) — check Zeroizing/lock_vault and KDF-internal copies"
  [[ "$EL" -ne 0 ]] && echo "  - entry password ($EL hits) — check VaultEntry ZeroizeOnDrop / entries.clear()"
  exit 1
else
  echo "PASS: both secrets present while unlocked, absent after lock — Zeroize verified."
  exit 0
fi
