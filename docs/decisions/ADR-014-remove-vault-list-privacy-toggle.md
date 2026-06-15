# ADR-014: Remove the `show_vault_list` Privacy Toggle

## Status
Accepted — supersedes ADR-012.

## Date
2026-06-14

## Context

ADR-012 introduced a login-screen privacy toggle, **`show_vault_list`** (default
OFF), meant as coercion-resistance: someone with device access should not even be
able to *see* that other vaults exist. Its threat model is **one user per
device** under duress.

That promise does not hold. The vault registry, `~/.config/gabbro/vaults.jsonc`,
is **plaintext** and lists every vault's alias and full path (ADR-012 §"out-of-band
deletion" documents exactly this). The toggle therefore hides other vaults only
from a shoulder-surfer who *merely opens the app* — not from the very adversary it
targets, who can read `vaults.jsonc` directly. We were paying real complexity for
protection the storage layer already defeats:

- A class of leak/orphan bugs at the deletion boundary (the whole subject of
  ADR-012).
- A surprising UX rule: the active vault could not be deleted while siblings
  existed.
- Special-casing across `main.dart`, `unlock_screen.dart`,
  `manage_vaults_screen.dart`, `security_screen.dart`, `settings.dart`, plus four
  localized strings in every locale.

No other manager ships this. Account-based managers (Bitwarden, 1Password)
enumerate accounts openly on the lock screen; file-based managers (KeePassXC) keep
no managed registry to hide. "Destroy the vault you're in → land on a neutral
screen" is the universal norm; ADR-012's block was the outlier.

A half-strength privacy feature is worse than none: it implies a protection we do
not provide.

## Decision

**Remove the `show_vault_list` toggle entirely.**

1. The login/unlock screen **always** lists registered vaults and offers the
   switcher. The `showVaultList` setting and its Security-screen section are
   deleted.
2. **Active-vault deletion is no longer blocked.** Deleting any vault (active or
   not) routes to the remaining last-used vault's unlock screen, or to
   `OnboardingScreen` when none remain. There is no longer a leak to avoid, so the
   two deletion paths in `main.dart` collapse into one.
3. The deletion *authorization* gates from ADR-012 are retained unchanged: a
   confirmation checkbox for passphrase-only vaults, plus a mandatory registered
   YubiKey tap for passphrase+YubiKey vaults.

### Privacy posture going forward

Gabbro protects vault **contents** with the passphrase (+ optional YubiKey). It
does **not** claim to hide the existence of other vaults from someone with device
access — the plaintext registry makes that claim unsupportable. If a real
hidden-vault capability is ever wanted, it requires encrypting the registry, and
would be a new ADR — not a UI toggle.

## Consequences

### Positive
- Deletes the leak/orphan bug class and the active-vault delete block at the root.
- Removes special-casing and four strings × every locale.
- Honest about what Gabbro actually protects.
- Makes the rejected "open existing vault by path" backlog item moot — it existed
  only to relax the toggle's privacy rules.

### Negative / Tradeoffs
- The login screen now reveals all registered vault aliases to anyone who opens
  the app. This is the deliberate, documented posture (see above), matching every
  mainstream manager.

## References
- Supersedes ADR-012 (vault deletion and privacy-mode access) — its deletion
  *authorization* rules survive here; its privacy-toggle machinery does not.
- ADR-010 (YubiKey FIDO2 hmac-secret) — the retained deletion-authorization gate.
