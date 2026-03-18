# ADR-002 — Detached SHA-256 Hash on Vault Export

**Date:** 2026-03-18
**Status:** Accepted

---

## Context

When a user exports their vault, they receive an encrypted `.gabbro` file.
The question arose: should we also provide a way to verify that file has
not been tampered with — for example by malware or a corrupted transfer —
before attempting to open it?

This pattern is familiar to Linux users who routinely verify ISO downloads
via a `.sha256` file.

---

## Decision

On every export, Gabbro produces two files side by side:

- `<vault-name>.gabbro` — the encrypted vault
- `<vault-name>.gabbro.sha256` — a detached SHA-256 hash of the entire `.gabbro` file

The hash is computed in Rust (consistent with the principle: if it touches
security, it lives in Rust) and written as a standard hex digest, one line,
matching the format produced by `sha256sum` on Linux.

---

## Why not just rely on AES-256-GCM's authentication tag?

AES-256-GCM already includes a cryptographic authentication tag that
detects **any** tampering with the encrypted vault body. This is
cryptographically strong and built into the decryption step.

However, the auth tag only reveals tampering *at decryption time*,
which requires the user's passphrase and YubiKey. The detached hash
provides a complementary, lightweight check that:

1. Can be verified by any tool (`sha256sum`, `certutil`, etc.) without
   opening Gabbro at all
2. Follows a convention users already trust from verifying OS images
3. Adds defence-in-depth: detects gross file corruption (e.g. from
   a bad drive) before the user even attempts to unlock
4. Gives users confidence when moving backups between devices or
   cloud storage

In short: the auth tag is the cryptographic guarantee; the detached hash
is the UX complement.

---

## Alternatives Considered

| Option | Reason rejected |
|---|---|
| SHA-512 instead of SHA-256 | SHA-256 is sufficient and more universally supported by verification tools |
| Embed hash inside the `.gabbro` header | Creates a chicken-and-egg problem (the hash of a file can't be inside the file) |
| No detached hash, rely on auth tag alone | Cryptographically sufficient, but worse UX and diverges from user expectations |
| Sign the export with the user's YubiKey | Interesting for v2, but adds complexity and requires YubiKey to be present for verification — defeats the backup-verification use case |

---

## Consequences

- Export flow produces two files instead of one — UI must make this clear
- Import flow should offer to verify the hash before decrypting,
  and warn (not block) if no `.sha256` is present
- Hash computation is fast (SHA-256 on a few MB is imperceptible)
- Rust `sha2` crate handles this; no new cryptographic dependencies
  needed beyond what the vault encryption already requires
