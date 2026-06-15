# ADR-012: Vault Deletion and Privacy-Mode Multi-Vault Access

## Status
Superseded by ADR-014 (2026-06-14). The `show_vault_list` privacy toggle and the
active-vault deletion *block* described below are removed; the deletion
*authorization* gates (confirmation checkbox + mandatory YubiKey) are retained.
Kept for history.

## Date
2026-06-09

## Context

Gabbro supports multiple vaults per device, tracked in a registry
(`vaults.jsonc`). A security/privacy toggle, **`show_vault_list`** (default
**OFF**), controls whether the *login/unlock* screen lists vaults and offers a
switcher. OFF is an obfuscation / coercion-resistance feature: someone with
access to the device should not even be able to *see* that other vaults exist.
(The post-authentication vault-management screen always lists all vaults — once
unlocked the user has already "seen" them; the toggle governs only the login
screen.)

Deleting the *currently active* vault forced the app to navigate somewhere, and
the existing `onActiveVaultDeleted` routed to the next vault's unlock screen
whenever any vault remained — **ignoring the toggle**. The test-coverage
campaign (2026-06-09) surfaced two faults in this:

1. **Alias leak.** In privacy mode the post-deletion unlock screen displayed the
   remaining vault's alias, revealing the existence/name of another vault to
   someone who only had access to the just-deleted one.
2. **Orphaning.** `OnboardingScreen` is create-only (no "open an existing vault
   by path"), and in privacy mode the *only* way to reach a non-`lastUsed` vault
   is the toggle-gated switcher. So deleting the active vault in privacy mode
   could leave the other vaults unreachable without re-enabling the toggle.

A file-picker "open existing vault by path" (Option B) was considered but
rejected: on Android, vaults live in app-private storage the user cannot browse
to, so B is not viable cross-platform, and Gabbro requires consistent
mobile/desktop behaviour.

Threat model: **one user per device.** Once authenticated the user may act
freely, but may not want others with device access to learn that other vaults
exist. Multi-user-on-one-device is explicitly out of scope (YAGNI).

## Decision

Vault deletion is **registry-based and in-app** (Option A). The rule:

1. **A vault can only be deleted from within a *different* unlocked vault's
   session**, from the post-auth vault-management screen. You delete vault B
   while logged into vault A; afterwards you stay in A — no navigation, no login
   screen, no leak.
2. **Deleting the active vault is blocked when other vaults exist.** Its delete
   action is **shown but disabled**, with an explanatory message ("Open another
   vault to delete this one"), so the constraint is transparent rather than a
   silently missing button.
3. **The sole remaining vault may be deleted** (with the usual confirmations).
   The app then falls back to `OnboardingScreen` — nothing remains, so there is
   no alias to leak and nothing to orphan.

There is a single deletion path — the vault-management screen's delete flow
(`ManageVaultsScreen._showDeleteDialog` → the app's `onDelete`). Its active-vault
branch's "route to the remaining vault" path is removed, so the active vault is
only deleted when it is the sole one (→ onboarding). The old
`onActiveVaultDeleted` method — an unwired remnant of the removed "delete the
active vault from the hamburger menu" option (pre-multi-vault) — is deleted as
dead code; it carried the same leak.

### Why this respects `show_vault_list` OFF

Because deletion never navigates toward a vault the user is not already in, the
login screen never gets the chance to reveal a remaining alias. The user reaches
the login screen only after locking or auto-lock, where `lastUsed` is the vault
they re-open — exactly as in normal use. The toggle is honoured with no
special-casing.

## Deletion authorization (auth scales with protection)

Authorization to delete a vault matches the protection the user chose for it:

- **Passphrase-only vaults:** a warning step + an explicit confirmation
  checkbox. This is *intent confirmation* (foot-gun prevention), not
  cryptographic re-authentication.
- **Passphrase + YubiKey vaults:** the above **plus a mandatory YubiKey tap**.
  Any *registered* key authorizes (single-key vaults via `onConfirmYubikey`,
  multi-key via `onConfirmAnyYubikey`); deletion does not proceed unless the key
  verifies.

This asymmetry is intentional and acceptable for v1: a passphrase-only user opted
out of hardware protection, so a lighter delete gate is consistent with their own
threat model.

**Invariant (must not regress; is tested):** deleting a passphrase+YubiKey vault
requires a registered YubiKey to authorize — a wrong or absent key refuses the
deletion. The authorization is gated behind injectable confirm callbacks, so this
is pinned by an automated widget test (no hardware needed in the test).

**Future hardening (post-v1, not built now):** make the gate symmetric by
requiring the *passphrase* (an Argon2id verify) rather than a magic word for
passphrase-only vaults — "delete re-authenticates with the vault's own
protection."

## Data durability and out-of-band deletion

**Backups are the user's responsibility (3-2-1).** Gabbro does not sync or back
up vaults; in-app deletion is irreversible. Users should keep a copy of each
vault on at least one other device. This is surfaced in the app (vault-management
screen) alongside the deletion controls.

**There is a deliberate, unauthenticated emergency wipe** — destroying all
on-device Gabbro data at the OS level, in seconds, bypassing the app's
authenticated deletion flow. This is the v1 coercion-resistance / panic
mechanism (an in-app panic button is a noted post-v1 enhancement). It is total
and irreversible, which is *why* it works as a panic action — reinforcing the
3-2-1 point above.

- **Linux:**

  ```bash
  rm -rf ~/.local/share/app.gabbro.gabbro/ ~/.config/gabbro/
  ```

  Both directories matter. `~/.local/share/app.gabbro.gabbro/` holds
  default-location vault files; `~/.config/gabbro/` holds `settings.jsonc` **and
  the registry `vaults.jsonc`**, which lists every vault's alias and full path.
  Deleting only the first leaves the registry — leaking vault names and the
  locations of any custom-path vaults, and leaving those custom-path vault files
  intact. **Vaults the user saved to custom locations are not under either
  directory and must be removed separately** — the registry is the only
  on-device record of where they are (3-2-1 again).

- **Android:** Settings → Apps → Gabbro → *Clear data*. Android app-private
  storage holds the vaults, settings, and registry together, so this is a
  complete wipe. (A vault the user *exported* to shared storage / SD card
  survives — 3-2-1.)

The app documents these steps (vault-management screen) so the capability is
transparent and discoverable, in keeping with Gabbro informing rather than
hiding behaviour.

## Consequences

### Positive
- Removes the alias leak and the orphaning at the root: there is no
  "active vault deleted → navigate to another vault" path left to leak from.
- Identical behaviour on desktop and mobile (pure in-app registry logic; no
  reliance on user-reachable file paths, which Android lacks).
- Honours `show_vault_list` OFF with zero special-casing.
- Preserves and pins the YubiKey deletion gate.

### Negative / Tradeoffs
- With the toggle OFF, the *active* vault can only be deleted by first deleting
  its siblings (until it is the sole vault) or by temporarily enabling the toggle
  to switch to another vault. This is a documented, intentional consequence of
  privacy mode, surfaced to the user — Gabbro strives to inform and stay
  transparent.
- Self-deleting the vault you are currently using is deliberately impossible
  while others exist. Arguably a feature: it is a foot-gun.

## References
- ARCHITECTURE.md Bikeshed → Features & UX — the originating issue writeup.
- Surfaced by the Flutter `integration_test`/widget coverage campaign while
  scoping `onActiveVaultDeleted` coverage (2026-06-09).
- ADR-010 (YubiKey FIDO2 hmac-secret authentication) — the key-authorization
  mechanism reused to gate deletion.
