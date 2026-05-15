# ADR-010: YubiKey Authentication via FIDO2 hmac-secret

## Status
Accepted

## Date
2026-05-15

## Context

Gabbro requires hardware key authentication for sensitive operations (vault
create, unlock, delete, add vault, change master passphrase). ADR-005 documents
the signature algorithm decision (Ed25519 interim, ML-DSA-44 target). This ADR
documents the *mechanism* by which the YubiKey contributes to vault access —
specifically, how a hardware tap produces the key material needed to decrypt
the vault.

Three options were considered:

**Option A — HMAC-SHA1 challenge-response (OTP slot)**
The YubiKey signs a challenge using a symmetric secret baked into OTP slot 2.
Used by KeePassXC. Rejected: HMAC-SHA1 is the wrong direction for a
post-quantum-oriented project; the symmetric secret must be configured
externally via `ykman`; loses the asymmetric "private key never leaves silicon"
property.

**Option B — FIDO2 hmac-secret extension (chosen)**
A FIDO2 credential is registered with Gabbro as the relying party. On each
sensitive operation, Gabbro sends a salt to the YubiKey via CTAP2; the key
returns HMAC-SHA256 output derived from its internal credential secret and the
salt. That output is fed into HKDF alongside the Argon2id output to reconstruct
the vault key.

**Option C — FIDO2 full WebAuthn assertion**
A WebAuthn challenge is signed by the YubiKey; Gabbro verifies the signature.
Rejected: assertion proves identity (boolean) but does not produce key material.
Getting from a verified assertion to vault key bytes requires a separate
mechanism — Option B solves this directly.

### Why FIDO2 hmac-secret is the right shape for Gabbro

Gabbro is a local-first, fully-offline application. WebAuthn has no network
requirement — Gabbro is its own relying party, using `"app.gabbro.gabbro"` as
the relying party ID. The CTAP2 protocol runs entirely over USB or NFC.
hmac-secret produces deterministic key material from hardware on every tap: the
same credential + the same salt → the same 32 bytes, always. This output feeds
directly into the existing HKDF combiner with no additional escrow or
key-wrapping mechanism needed.

### Post-quantum status

hmac-secret uses HMAC-SHA256 internally (symmetric — quantum-resistant at
128-bit equivalent strength under Grover's algorithm). The FIDO2 credential
itself uses Ed25519 in v1 (classical, per ADR-005 interim). When Yubico ships
ML-DSA-44-capable hardware, credential re-registration upgrades the signature
algorithm; the hmac-secret mechanism is unaffected.

## Decision

Gabbro uses **FIDO2 hmac-secret** as the mechanism by which YubiKey hardware
contributes key material to vault operations.

The vault key is derived as:

```
vault_key = HKDF(
    argon2id_output || hmac_secret_output,
    ...
)
```

Neither the passphrase (Argon2id) nor the YubiKey (hmac-secret) alone is
sufficient to reconstruct the vault key.

## Operational design

**Registration (vault creation / onboarding):**
1. Gabbro requests a new FIDO2 credential from the YubiKey
   (relying party: `"app.gabbro.gabbro"`)
2. YubiKey generates a key pair internally; returns a credential ID and
   public key
3. Gabbro generates a random 32-byte salt per registered key
4. Vault header stores: credential ID + salt (one record per registered key)
5. The private key never leaves the YubiKey

**Unlock / sensitive operations:**
1. Gabbro reads the stored credential ID and salt from the vault header
2. Sends credential ID + salt to the presented YubiKey via CTAP2 (USB or NFC)
3. YubiKey returns the 32-byte hmac-secret output
4. Output is combined with Argon2id output in HKDF to reconstruct the vault key
5. On mismatch (wrong key presented), HKDF output is wrong → AES-GCM auth
   tag fails → vault does not open

**Multiple keys (min 2, soft max 4):**
The vault header stores one independent credential ID + salt record per
registered key. On unlock, Gabbro tries the presented key against all stored
records. Keys are independent — adding or removing a key does not affect other
registered keys. This is the correct model for backup key management and PQ
migration (register new key, verify, retire old key — no lockout risk).

**Sensitive operations requiring a YubiKey tap:**
- Vault create
- Vault unlock
- Vault delete
- Add new vault (future)
- Change master passphrase

All other operations (entry CRUD, search, export read) require only an unlocked
session.

**YubiKey PIN:**
FIDO2 hmac-secret requires a PIN to be set on the YubiKey. Gabbro never sets
or reads the PIN directly — the SDK handles PIN entry. If no PIN is detected,
Gabbro surfaces an in-app message:

> **Your YubiKey has no PIN set.**
> A PIN is required before Gabbro can register your key.
> Set one using the **Yubico Authenticator** app (Android) or
> **`ykman fido access change-pin`** (Linux terminal), then return here.

**Platform libraries:**
- Android: `yubikit-android` v3.1.0+ — FIDO2 + NFC + USB-C,
  `fido-android-ui` module for PIN entry UI
- Linux: `libfido2` via Rust FFI — all crypto remains in Rust per core
  architecture principle. Confirmed available on Arch (`extra/libfido2
  1.17.0-1`) and Mint/Debian (`libfido2-1` in Debian sid;
  `fido2-tools` in Linux Mint community repos).

## Consequences

### Positive
- YubiKey tap directly produces vault key material — no boolean-to-key-material
  gap
- Fully offline; no server, no network, no third party
- Multi-key design supports backup keys and future PQ migration without lockout
  risk
- PIN requirement enforced by hardware; Gabbro never handles the PIN
- Consistent with ADR-005 interim (Ed25519) and target (ML-DSA-44)

### Negative / Tradeoffs
- Vault format requires a new header section: one (credential ID, salt) record
  per registered key
- Registration is a one-time onboarding step; losing all registered keys without
  a backup means the vault is unrecoverable — enforced minimum of 2 keys
  mitigates this
- `libfido2` adds a native dependency on Linux; confirmed available on Arch and
  Mint
- `yubikit-android` is a Kotlin/Java dependency; bridged from Flutter via the
  existing Android layer

## References
- ADR-005: Post-Quantum Authentication — Pure ML-DSA-44
- FIDO2 hmac-secret extension spec:
  https://fidoalliance.org/specs/fido-v2.1-ps-20210615/fido-client-to-authenticator-protocol-v2.1-ps-20210615.html#sctn-hmac-secret-extension
- yubikit-android: https://github.com/Yubico/yubikit-android
- libfido2: https://github.com/Yubico/libfido2
- libfido2 on Arch: https://archlinux.org/packages/extra/x86_64/libfido2/
- libfido2 on Debian: https://packages.debian.org/sid/libfido2-1
- fido2-tools on Linux Mint: https://community.linuxmint.com/software/view/fido2-tools
