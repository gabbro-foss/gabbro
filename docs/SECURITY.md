# Gabbro — Security Overview

**Version:** pre-v1 (0.1.0-alpha)  
**Last updated:** 2026-06-14  
**Status: this codebase has not been reviewed by an external cryptographer or security auditor.**

---

## What this document is — and is not

This document describes what Gabbro does to protect your vault, what has been
verified, and what has not. It is written by the project author with AI
assistance. It is not a security certificate. It is not a claim of perfection.
It is an honest account of the current state.

If you find a mistake in this document or in the code, please open an issue or
email the contact listed in `README.md`.

---

## Two authentication modes

Gabbro supports two modes, chosen when you create a vault:

| Mode | What unlocks the vault | Recommended? |
|------|------------------------|--------------|
| **Passphrase-only** | Your master passphrase alone | For users without a YubiKey |
| **Passphrase + YubiKey** | Your master passphrase **and** a physical YubiKey tap | **Strongly recommended** |

**Why YubiKey is strongly recommended:** in passphrase-only mode, anyone who
obtains your vault file can attempt to brute-force your passphrase offline.
Argon2id makes each attempt slow, but a sufficiently weak passphrase is still
at risk. With a YubiKey, the vault file is useless without the physical key —
offline brute-force is blocked by hardware.

The rest of this document distinguishes the two modes where they differ.

---

## The short version (non-technical)

Your passwords are stored in a single encrypted file (`.gabbro`) on your device.
Nothing is sent to a server.

**Passphrase-only mode:** the file can only be decrypted by someone who knows
your master passphrase. The encryption is strong, but the security is only as
good as your passphrase.

**Passphrase + YubiKey mode:** the file requires both your master passphrase
and a physical tap of your YubiKey. The two factors are cryptographically
combined — knowing the passphrase without the key (or vice versa) is not enough.
In this mode, a stolen vault file is not useful to an attacker who does not also
have your hardware key.

In YubiKey mode, at least two keys must be registered (primary + backup).
Losing both means losing access. Losing one is recoverable if you have the other.

---

## Encryption: how it works

### The simple version

Unlocking your vault involves these steps:

1. **Key derivation.** Your passphrase is fed into Argon2id, a deliberately slow
   hashing algorithm designed to make brute-force guessing expensive. It produces
   192 bytes of key material from which two keypairs are derived.

2. **Hybrid key exchange.** The derived keypairs perform a key exchange with
   values stored in the vault file: one classical (X25519), one post-quantum
   (ML-KEM-1024). The two resulting shared secrets are combined using HKDF-SHA256
   to produce an intermediate key. This step is the same in both modes.

3. **YubiKey factor (YubiKey mode only).** The intermediate key is combined with
   the YubiKey's HMAC-secret in a second HKDF pass to produce the final vault key.
   Without the physical key, the HMAC-secret is unavailable and decryption cannot
   proceed.

4. **Decryption.** The vault key decrypts the vault body using AES-256-GCM. If
   any input is wrong — wrong passphrase, wrong key, tampered file — decryption
   fails and no data is released.

### The technical version

Both modes share the same first phase. The second phase differs.

**Phase 1 — shared by both modes (passphrase → intermediate key)**

| Step | Algorithm | Parameters / notes |
|------|-----------|---------------------|
| KDF | Argon2id (RFC 9106) | m = 64 MiB, t = 25, p = 4. Exceeds RFC 9106 second-recommended profile (m=64 MiB, t=3, p=4) and OWASP minimum. Tuned to ~667 ms on the reference hardware. |
| Classical KEM | X25519 (RFC 7748) | Ephemeral keypair on the sealer side; static keypair derived from KDF bytes [0..32]. |
| Post-quantum KEM | ML-KEM-1024 (FIPS 203) | Keypair derived via `ML-KEM.KeyGen(d, z)` directly from KDF bytes [32..64] (d) and [64..96] (z) — FIPS 203 §7.1 conformant as of VERSION 6. |
| Hybrid combiner | HKDF-SHA256 (RFC 5869) | `HKDF(hkdf_salt, ml_kem_ss ∥ x25519_ss, "gabbro-hybrid-kex-v1") → 32-byte intermediate_key`. `hkdf_salt` is a fresh 32-byte random value per seal, stored in the vault header. |

**Phase 2 — differs by mode**

*Passphrase-only:* `intermediate_key` **is** the vault key. Used directly with AES-256-GCM.

*Single YubiKey:*
```
vault_key = HKDF(yubikey_salt, intermediate_key ∥ hmac_secret, "gabbro-yubikey-v1")
```
`yubikey_salt` is a fresh 32-byte random value per seal, stored in the vault header.

*Multi-key (≥ 2 YubiKeys, minimum enforced):* a random `vault_key_master` encrypts
the body. A random `wrapping_key` is encrypted under `intermediate_key`
(`passphrase_blob`). Each registered key's `key_blob` is
`AES-GCM(HKDF(yubikey_salt_i, wrapping_key ∥ hmac_i, "gabbro-yubikey-v1"), vault_key_master)`.
Any single registered key can decrypt the body. Passphrase changes only re-encrypt
`passphrase_blob` — `key_blob`s and the vault body are untouched.

**Symmetric encryption (both modes)**

| Step | Algorithm | Notes |
|------|-----------|-------|
| Symmetric encryption | AES-256-GCM (FIPS 197 / NIST SP 800-38D) | 96-bit nonce generated via OS CSPRNG (`getrandom`). GCM authentication tag detects any tampering of the ciphertext. |
| File format | `.gabbro` binary | Plaintext header (params, salts, nonces, KEM ciphertext, ephemeral pubkey, YubiKey records, alias) + AES-GCM encrypted body. Self-contained. |

The vault file is written with `0600` permissions (user-read/write only) via an
atomic temp-file-then-rename. Symlinks at the vault path are rejected on both
read and write.

---

## Authentication (YubiKey mode)

In YubiKey mode, access requires a physical YubiKey. The passphrase alone is
not enough — the HMAC-secret is bound into the vault key, and it is only
available when the hardware key is present and tapped.

- At least two keys must be registered (primary + backup). Maximum four.
- Each key is registered via FIDO2 CTAP2.1 (`hmac-secret` extension).
- On Android: USB (HID) and NFC are both supported.
- On Linux: USB (HID) via `libfido2`.
- Auto-lock after 30 seconds of inactivity by default (configurable).

In passphrase-only mode, authentication is the passphrase alone. Auto-lock
still applies.

---

## Local-first: what it means for your security

Gabbro stores your vault as a single file on your device. There is no Gabbro
server, no account, no sync infrastructure. This has security consequences:

**Advantages:**
- No server breach can expose your vault.
- No Gabbro employee or contractor can access your passwords.
- No network traffic to intercept. No API keys to leak.
- No telemetry.

**Consequences you must manage yourself:**
- Backup is your responsibility. A lost device without a backup means lost vault.
- Syncing between devices requires a solution you choose and control (e.g. rsync,
  Syncthing, a USB drive). Gabbro does not provide one.
- Revocation of a compromised key requires unlocking the vault and using
  Settings → Security to remove the key. There is no remote wipe.

---

## What has been verified

The following claims are backed by reproducible tests or verifiable specifications,
not by assertion alone.

**Argon2id parameters exceed published recommendations.**
The parameters (m=64 MiB, t=25, p=4) were measured with `rust/src/bin/bench_kdf.rs`
on the development hardware. They exceed the RFC 9106 second-recommended profile
and the OWASP minimum by a factor of ~8× on time cost.

**ML-KEM keypair derivation follows FIPS 203 §7.1.**
Since VERSION 6, the ML-KEM-1024 keypair is derived by calling
`ML-KEM.KeyGen(d, z)` directly with `d = kdf[32..64]`, `z = kdf[64..96]`.
This is the FIPS 203-conformant construction. The implementation is tested for
determinism, full consumption of both seed bytes, and divergence from the legacy
derivation path. Legacy vaults (VERSION ≤ 5) remain readable.

**Secrets are absent from memory after lock.**
A reproducible memory-forensics self-test (`rust/scripts/mem_forensics.sh`) seals
a vault with two known-value canaries (master passphrase + an entry password),
takes a `gcore` dump while unlocked (canaries must be present), and a second dump
after lock (canaries must be absent). 12/12 runs pass on the development machine.
The test can be reproduced by anyone with the source. Long-lived in-memory secrets
(master passphrase, YubiKey HMAC-secret, derived vault key) are held in
`Zeroizing<T>` wrappers and scrubbed on lock and on drop.

**Vault files are owned by the user and written atomically.**
`0600` permissions are set at file creation. Writes use a temp-file-then-`rename`
pattern (atomic on POSIX). Symlinks at the vault path are rejected.

**No secrets or keys in git history.**
`git log` has been scanned for private keys, passwords, and signing credentials.
None found. Build secrets (Android keystore, `key.properties`) are git-ignored
and verified absent from all commits.

---

## Known limitations and open questions

**This is the honest section. Read it.**

### NOT externally reviewed

The cryptographic implementation has not been reviewed by an independent
cryptographer, a security firm, or any third party. The AI-assisted internal
audit (`docs/AI_SECURITY_AUDIT.md`) is informational — it checked for obvious
problems, not for subtle ones. Do not treat it as a substitute for a real audit.

This is a pre-v1 project. The version numbering (`0.1.0-alpha`) is intentional:
it signals to users that no external trust validation has happened yet.

### Passphrase-only mode: weaker security profile

In passphrase-only mode, the vault has no hardware factor. Its security against
offline attack is bounded by:
- The strength of your passphrase (length, unpredictability).
- The cost of Argon2id (currently ~667 ms per guess on one machine — a determined
  attacker with faster hardware can parallelise across machines).

A long, randomly generated passphrase (use the built-in generator) substantially
raises the cost of a brute-force attack, but cannot match the categorical
protection of a hardware second factor. **If you have a YubiKey, use it.**

### Secrets in the Flutter (UI) layer

All key material and decryption live in Rust and are zeroized on lock (verified by
the gcore self-test). But the master passphrase is **typed into** Flutter, and any
password you **view, generate, or autofill** must reach the UI in plaintext to be
shown. These live in the Dart heap, which is garbage-collected and cannot be
zeroized: a root memory dump of the unlocked app finds them, and they can linger
after lock until garbage collection (measured 2026-06-14). This is inherent to any
GUI password manager — the master **keys** never enter Flutter, so a vault you
never opened stays protected. As of the core-dump hardening (R-04) a same-user
process can no longer dump the app's memory; the residual needs root, swap, or a
cold-boot attack. (The non-dumpable flag is briefly raised only while a native
file dialog is open, since `xdg-desktop-portal` must read the process's `/proc`
to serve it; the kernel's yama `ptrace_scope`≥1 still blocks a same-user tracer
during that window. The no-core-dump `RLIMIT_CORE=0` guarantee is never relaxed.)
Bounded further by auto-lock and clipboard auto-clear.

### Header integrity (fixed in VERSION 7)

Since VERSION 7, every byte of the `.gabbro` plaintext header — Argon2id
parameters, salts, ML-KEM ciphertext, X25519 public key, YubiKey records (including
credential IDs, salts, and key blobs), alias, and passphrase_blob — is committed to
the AES-256-GCM authentication tag as additional authenticated data (AAD). Any
modification to the header without possessing the vault key causes body decryption
to fail immediately.

**What this protects:**
- **Alias**: renaming the vault without an active unlocked session is now detectable.
  The rename path requires unlock; the body is re-sealed with the new alias bound as
  AAD.
- **YubiKey records**: adding, removing, or reordering records without the vault key
  causes decryption failure. Key management operations (add / remove YubiKey) always
  re-seal the body with the updated header as AAD.

**What remains observable (by design):**
- **YubiKey credential IDs** are still visible in the plaintext header — the unlock
  screen needs them to identify the right key before any decryption can occur. They
  cannot be silently changed or removed, but they can be read by anyone with
  file-system access to the vault file.

Existing vaults (VERSION ≤ 6) gain this protection automatically on the next save,
CRUD operation, or key management action.

### F-03 — Hybrid KEM combiner is not transcript-binding

The Phase 1 combiner `HKDF(hkdf_salt, ml_kem_ss ∥ x25519_ss, "gabbro-hybrid-kex-v1")`
does not include the KEM ciphertext or public keys in the key material, as
recommended by X-Wing and the IETF hybrid-design drafts. Modern analysis of
hybrid constructions recommends transcript-binding for provable IND-CCA security.

No concrete attack against the current construction is known — both ML-KEM-1024
and X25519 are IND-CCA secure components, and the combiner uses a fresh random
salt per seal. However, the construction has not been assessed by a cryptographer
against a formal security model. This is one of the questions the planned expert
review must answer before v1.0.

### What a future expert reviewer should look at

- The full hybrid construction in `rust/src/crypto/` — in particular the two-step
  HKDF combiner design (Phase 1 + YubiKey phase) and the multi-key vault state
  machine.
- Whether to upgrade to an X-Wing-style transcript-binding combiner (F-03) before
  the 1.0 file format is frozen.
- Side-channel behaviour of the Argon2id / X25519 / ML-KEM call sites at the
  compiled-code level.
- The formal correctness of `add_key_to_sealed` / `remove_key_from_sealed` /
  `change_vault_passphrase_with_keys` (invariant: any registered key can always
  unlock; passphrase change does not invalidate existing keys).

### Developer/build environment — analysis tools run dependency code

A developer-side, not end-user, surface. To give accurate analysis, **rust-analyzer
runs `build.rs` build scripts and expands procedural macros by default** — i.e. it
executes code from the crate *and its dependencies* at edit time, before any explicit
`cargo build`. The compiled build does the same. So a malicious dependency could run
code on a contributor's machine. Mitigation is dependency hygiene, not disabling the
tooling (Gabbro relies on proc-macros — `serde`, `thiserror`, `flutter_rust_bridge`):
deps are pinned (`Cargo.lock` / `pubspec.lock`) and lockfile diffs reviewed on update
(see `MAINTENANCE.md`). `flutter pub get` / `cargo` fetches are the only online steps
and are run deliberately (IDE auto-fetch prompts disabled). Note: `pub get` itself does
not execute package code; the Rust toolchain (build scripts/proc-macros) does.

---

## Threat model

Gabbro's design targets the standard local-storage threat model for a password
manager. The protections available depend on which mode you use.

**In scope — passphrase-only mode:**
- File disclosure/theft: Argon2id raises the cost of offline brute-force. A weak
  passphrase is still at risk.
- File tampering: AES-GCM authentication tag detects ciphertext tampering. Since
  VERSION 7 the full plaintext header is also bound as AAD, so header tampering is
  detected on the next decrypt attempt. YubiKey credential IDs remain visible in
  the header (by design) but cannot be silently modified.
- Local file permissions: `0600` prevents other local users from reading the file.
- Memory after lock: `Zeroizing` scrubs Rust-side secrets; verified by `gcore`
  self-test. The Flutter UI heap retains typed/viewed secrets — see *Secrets in
  the Flutter (UI) layer*.

**In scope — YubiKey mode (additional protection):**
- Offline brute-force: blocked by hardware. The HMAC-secret is unavailable without
  the physical key, regardless of how fast the attacker can guess passphrases.
- Vault file theft without the key: useless.

**Out of scope (neither mode resists):**
- A compromised operating system or root-level attacker.
- A compromised or cloned YubiKey.
- Coercion (the attacker forces you to unlock the vault).
- Side-channel attacks at the hardware or micro-architecture level.
- Physical extraction of RAM from an *unlocked* running process.
- Key material paged to **swap** before it is zeroized — use encrypted swap (or disable swap) on the host. (`mlock`/`madvise` hardening is deferred to the planned expert review.)
- Vault paths and aliases in the local registry (`vaults.jsonc`) are readable by anyone with local file access — metadata only, no secrets.
- A malicious build of the application distributed as a fake update.

---

## Comparison tables

### Gabbro vs other open-source local-first password managers

This table compares documented properties. For competing projects, the source is
their public documentation and published security audits. Gabbro's entries reflect
the current implementation.

| Property | Gabbro (0.1.0-alpha) | KeePass 2.x | Bitwarden (self-hosted) | pass (Unix) |
|---|---|---|---|---|
| Local-first (no mandatory cloud) | ✓ | ✓ | ✓ (self-host) | ✓ |
| Open source | ✓ GPL-3.0 | ✓ GPL-2.0 | ✓ AGPL-3.0 | ✓ GPL-2.0 |
| Post-quantum encryption | ✓ ML-KEM-1024 | ✗ | ✗ | ✗ |
| Hardware key (2FA) support | ✓ FIDO2 (optional but strongly recommended) | Optional (plugins) | Optional (TOTP / hardware token) | ✗ (GPG only) |
| Memory-scrubbing on lock | ✓ (verified by gcore test) | ✓ (documented) | Unknown | Relies on GPG agent |
| External cryptographic audit | **✗ none yet** | ✓ multiple | ✓ multiple (Cure53, etc.) | ✓ (GPG is audited) |
| No telemetry | ✓ | ✓ | ✓ (self-hosted) | ✓ |
| In-app help (offline, no external calls) | ✓ | Partial (local CHM on Windows; online wiki for many topics) | ✗ (links to bitwarden.com) | ✓ (man pages) |
| File format stability | Pre-v1 (may change) | Stable (KDBX4) | Stable | Stable (GPG) |

**Note:** KeePass and Bitwarden have received multiple independent security audits.
Gabbro has not. This is the most significant gap in the table.

### Gabbro's crypto choices vs alternatives

| Decision | Gabbro | Common alternative | Why Gabbro's choice |
|---|---|---|---|
| KDF | Argon2id (RFC 9106) | PBKDF2-HMAC-SHA256 | Argon2id is memory-hard; PBKDF2 is not. Memory-hardness is the main defence against GPU/ASIC brute-force. Argon2id is the current OWASP and NIST recommendation. |
| Key exchange | X25519 + ML-KEM-1024 hybrid | X25519 alone (classical) | The hybrid approach adds a post-quantum layer without weakening classical security: if ML-KEM has a flaw, X25519 still protects the vault; if a quantum computer breaks X25519, ML-KEM still protects it. |
| YubiKey binding | Second HKDF pass after the hybrid combiner | Passphrase alone | Adds a hardware factor that blocks offline brute-force entirely, independent of passphrase strength. |
| Symmetric cipher | AES-256-GCM | AES-256-CBC + HMAC, or ChaCha20-Poly1305 | AES-256-GCM is an AEAD — it authenticates as well as encrypts in a single pass. ChaCha20-Poly1305 would be an equally valid choice; AES-GCM was chosen for FIPS alignment. |
| KDF combiner | HKDF-SHA256 (RFC 5869) | Concatenation + hash | HKDF is a standard, well-studied PRF. The random per-seal salt means even identical passphrases produce different vault keys. |
| Combiner transcript binding | Not yet (see F-03) | X-Wing-style (includes ciphertext + pubkeys) | Known open question, not an oversight. Deferred to the expert review before v1.0. |

---

## How to verify for yourself

Gabbro is fully open source under GPL-3.0. You can:

- Read the cryptographic implementation: `rust/src/crypto/`.
- Run the memory-forensics self-test: `rust/scripts/mem_forensics.sh`
  (requires `gcore`, builds the `--features forensics` binary).
- Read the AI-assisted security audit: `docs/AI_SECURITY_AUDIT.md`.
- Run the full test suite: `cargo test -q` and `flutter test`.

If you find a problem, please report it. There is no bug bounty programme yet,
but findings will be credited and taken seriously.
