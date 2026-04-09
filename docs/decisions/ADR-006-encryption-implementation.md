# ADR-006: Encryption Stack Implementation

## Status
Accepted

## Date
2026-04-09

## Context

ARCHITECTURE.md specifies the encryption stack at a high level:
passphrase → Argon2id → ML-KEM → AES-256-GCM. Before implementing,
the specific parameter choices, crate selections, and byte-level key
derivation flow must be decided and recorded.

Five decisions are made in this ADR.

## Decisions

### 1. ML-KEM parameter set: ML-KEM-1024

ML-KEM comes in three parameter sets (512/768/1024) at NIST security
levels 1, 3, and 5 respectively. Gabbro already uses AES-256-GCM
(level 5 equivalent) for symmetric encryption. Using ML-KEM-512
(level 1) would create an inconsistent security profile — the chain
is only as strong as its weakest link.

ML-KEM-1024 public key (1568 bytes) and ciphertext (1568 bytes) live
in the vault file header as a one-time cost. Storage is not a
constraint on a modern device. ML-KEM-1024 is consistent with the
rest of the stack.

Note: ADR-005 chose ML-DSA-44 (level 2) for *authentication
signatures*. That is a different operation — a signature is computed
live per auth event, where size has a mild cost. Key encapsulation
data is stored once; size is irrelevant.

### 2. Hybrid key exchange: X25519 + ML-KEM-1024 combined via HKDF

Rather than using ML-KEM alone, the vault encryption key is derived
from two independent shared secrets: one from ML-KEM-1024 and one
from X25519 (elliptic curve Diffie-Hellman). These are concatenated
(A ∥ B, meaning A followed by B as a single byte sequence) and fed
into HKDF-SHA256:

combined_key = HKDF-SHA256(
ikm  = ml_kem_shared_secret ∥ x25519_shared_secret,
salt = random 32 bytes (stored in header),
info = b"gabbro-hybrid-kex-v1"
)

The `info` string domain-separates this derivation from any other
key material. An attacker must break both ML-KEM-1024 and X25519
simultaneously — if either holds, the vault is secure.

X25519 is chosen over ECDH/P-256: it is faster, has no known
implementation pitfalls, and is the modern standard (used in
TLS 1.3).

Note: hybrid *key exchange* is the right tradeoff here. ADR-005
rejected hybrid *signatures* for authentication — that reasoning
does not carry over. Ephemeral key material is cheap to compose;
signature protocol complexity is not.

### 3. Argon2id parameters as a serializable struct

### 3. Argon2id parameters as a serializable struct

Parameters:
m_cost = 65536 KiB  (64 MiB)
t_cost = 25
p_cost = 4

Source: OWASP Password Storage Cheat Sheet
https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html

64 MiB is the OWASP preferred floor for memory hardness. t_cost=25
was chosen by benchmarking on a 2011 desktop (667ms) — conservative
by design. On a mid-range Android phone this is expected to take
1.5–2.5s, which is acceptable because:

1. Biometric unlock bypasses the KDF entirely for frequent unlocks.
   The full passphrase + KDF path is cold boot and reinstall only.
2. Gabbro's threat model explicitly includes high-risk users
   (journalists, activists, researchers) for whom stronger parameters
   are worth the unlock cost.

OWASP minimum is t_cost=2. Gabbro's t_cost=25 is deliberately well
above that floor.

These values are stored in the vault header as an `Argon2idParams`
struct, not hardcoded. When decrypting an existing vault, the stored
parameters are used — not the current defaults. This allows future
parameter upgrades without breaking old vaults.

### 4. Crate selections (RustCrypto family)

| Purpose         | Crate           |
|-----------------|-----------------|
| Argon2id        | `argon2`        |
| ML-KEM-1024     | `ml-kem`        |
| X25519          | `x25519-dalek`  |
| HKDF            | `hkdf`          |
| SHA-256         | `sha2`          |
| AES-256-GCM     | `aes-gcm`       |
| Random numbers  | `rand`          |

All RustCrypto crates share a common design philosophy: conservative,
audited, minimal unsafe code. Using one family reduces the risk of
subtle incompatibilities at boundaries between operations.

### 5. Byte-level key derivation flow

Argon2id outputs 96 bytes, split as follows:
bytes [0..32]  → X25519 private key (32 bytes required)
bytes [32..96] → ML-KEM-1024 private key seed (64 bytes required)

Public keys are derived deterministically from these. The public keys
are stored in the vault header; the private keys are re-derived from
the passphrase on each unlock — they are never stored.

**Lock (encrypt):**
1. Generate random 32-byte session key K
2. ML-KEM-1024: encapsulate K to own public key
   → ml_kem_ciphertext (1568 bytes, stored in header)
   → ml_kem_shared_secret (32 bytes)
3. X25519: ephemeral key exchange with own public key
   → x25519_ciphertext (32 bytes, stored in header)
   → x25519_shared_secret (32 bytes)
4. HKDF-SHA256(ikm = A ∥ B, salt, info) → 32-byte vault key
5. AES-256-GCM encrypt vault body with vault key

**Unlock (decrypt):**
1. Read salt + Argon2id params from header
2. Argon2id(passphrase, salt) → 96 bytes → keypairs
3. ML-KEM-1024 decapsulate → ml_kem_shared_secret
4. X25519 reverse exchange → x25519_shared_secret
5. HKDF-SHA256(same inputs) → vault key
6. AES-256-GCM decrypt → vault body (auth tag failure = wrong passphrase)

The session key K is random, not derived from the passphrase. This
means changing the passphrase only requires re-running the
encapsulation step — the vault body need not be re-encrypted.

## Consequences

### Positive
- Consistent security level across the stack (level 5 throughout)
- Belt-and-suspenders: vault secure if either ML-KEM or X25519 holds
- Argon2id params travel with the vault — old vaults always open
- Passphrase change is cheap — re-encapsulate the key, not the vault
- All crates from one audited family (RustCrypto)

### Negative / Tradeoffs
- ML-KEM-1024 adds ~3 KB to the vault header vs ML-KEM-512.
  Irrelevant in practice.
- x25519-dalek is from the Dalek project, not RustCrypto proper.
  It is widely used and well-audited; the minor inconsistency is
  acceptable given X25519's role.
- Argon2id with 64 MiB memory may be slow on very old or constrained
  hardware. Parameters should be benchmarked on the minimum target
  device before v1 ships.

## References

- OWASP Password Storage Cheat Sheet:
  https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- NIST FIPS 203 (ML-KEM standard)
- RFC 7748 (X25519)
- RFC 5869 (HKDF)
- ADR-005 (authentication signatures — related but distinct decisions)