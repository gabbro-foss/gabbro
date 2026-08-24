# ADR-009: Software Passkey Storage

## Status

Accepted (amended 2026-08-20; original decision reversed — see history below)

## Date

2026-05-15 (created); 2026-06-22 (edited); 2026-08-20 (amended)

## Context

Passkey managers such as Bitwarden store FIDO2 private keys encrypted in the
vault, acting as a software authenticator: generating the key pair in software
and serving WebAuthn credential creation/assertion from the vault.

## Decision

Gabbro will implement software passkey storage: a `Passkey` vault entry type
served by an Android Credential Manager provider and a Linux virtual FIDO2
authenticator (uhid). No browser extension on any platform (ADR-008 stands).
Plan and sources: PASSKEY_INVESTIGATION.md (deleted after implementation
shipped, 2026-08-24; full text in git history).

## Rationale

- Vault passkeys sync, back up, and have no slot cap; a YubiKey caps at 25
  passkeys (firmware 5.0-5.6.x) or 100 (5.7+).
- The choice mirrors app unlock: hardware (AAL3, NIST SP 800-63B-4) remains the
  stronger option and stays fully supported; vault storage (AAL2) is the
  user's informed trade-off, not a replacement. Users who want hardware-bound
  passkeys keep registering them on their YubiKeys directly.
- Extension-free provider paths now exist on both target platforms, removing
  the original implementation-cost objection's largest component.

## History (original decision, 2026-05-15, reversed)

The original ADR-009 rejected software passkey storage permanently: a YubiKey
owner already holds a strictly stronger (AAL3) authenticator, vault-stored
keys live in the vault's own threat model, and the implementation cost
(CredentialManager, CTAP2, browser extension) bought no net security for the
target user. Reversed because the no-cap/sync/backup benefit stands on its
own, the flows need no extension, and hardware remains recommended for those
who prefer it. Full original text: git history of this file.

## Consequences

- New `Passkey` entry type; new vault format VERSION.
- Android `CredentialProviderService` integration; Linux uhid daemon.
- Vault-stored passkeys are AAL2 by definition; documented honestly (README /
  SECURITY.md) — Gabbro never claims hardware-equivalent passkey security.

## References

- NIST SP 800-63B-4: <https://pages.nist.gov/800-63-4/sp800-63b.html>
- YubiKey passkey capacity: <https://docs.yubico.com/hardware/yubikey-guidance/best-practices/all-faq-passkeys.html>
- ADR-008 (no browser extension), ADR-010 (YubiKey vault unlock)
