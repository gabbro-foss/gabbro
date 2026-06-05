# AI Security Audit — Gabbro

**Date:** 2026-05-31
**Auditor:** Claude Opus 4.7 (AI-assisted review)
**Scope:** `rust/src/crypto/` and `rust/src/vault/` (per ARCHITECTURE.md Current Focus)
**Status:** Pre-v1 informational review. **Not a substitute for human expert cryptography review** (see Bikeshed → "Security (pre-v1 gates)").

> **Reading note.** This is a findings report. Remediation is a separate session. Severities are AI estimates and should be re-rated by a human cryptographer. Nothing here unblocks the pre-v1 gate that requires academic / RustCrypto / formal audit sign-off.

---

## Remediation status (updated 2026-06-01)

The Executive summary and findings below are the **original 2026-05-31 pass**, kept as a historical record. Current status of each finding:

| Finding | Sev. | Status |
|---------|------|--------|
| **F-01** header not AEAD-authenticated | Low | **Fixed** (VERSION 7, 2026-06-05) — full header bound as AES-GCM AAD; alias rename and key management now require unlock + reseal. |
| **F-02** ML-KEM KeyGen vs FIPS 203 | Low | **Fixed** 2026-06-01 (VERSION 6, `generate_deterministic(d,z)`). |
| **F-03** hybrid combiner not transcript-binding | Low | **Open** — gated on human crypto review (X-Wing). |
| **F-04** session secrets not `Zeroizing` | Low | **Fixed** (Round 1). |
| **F-05** plaintext JSON export | Info | By design; no action. |
| **F-06** `unwrap` on length-checked slices | Info | **Fixed** (Round 1). |
| **F-07** kdf.rs doc drift | Info | **Fixed** (Round 1; realigned 2026-06-01 with F-02). |
| **F-08** vault files not `0600` | Low | **Fixed** (Round 1). |
| **F-09** no symlink validation | Low | **Fixed** (Round 1). |
| **F-10** eTLD+1 autofill matching | Info | **Open** — post-v1 "Strict FQDN" toggle. |
| **F-11** decrypted body not zeroized | Low | **Fixed** 2026-06-01 (found by the memory-forensics self-test). |
| **L-6** memory-forensics test | — | **Done** 2026-06-01 (`scripts/mem_forensics.sh`). |

**Still open:** F-03 (→ human crypto review), F-10 (→ post-v1). Everything else is fixed or by-design.

---

## Executive summary

> Reflects the original 2026-05-31 pass. See **Remediation status** above for what has since changed.

| Category                       | Result                                                    |
|--------------------------------|-----------------------------------------------------------|
| Known CVEs in dependency tree  | **0** (cargo audit, 211 crates, advisory DB 2026-05-31)   |
| Secrets / keys in git history  | **0** found                                               |
| Unsafe / transmute / asm! in scope | **0**                                                 |
| Non-test `panic!` / `unwrap` in security-critical paths | **0** unbounded (all bounded by prior length check) |
| Hardcoded credentials in source | **0** found                                              |
| Memory hygiene (Zeroize)       | Mostly good; **two `Vec<u8>` secrets** are zeroized manually rather than via `Zeroizing<T>` (defence-in-depth gap, not a leak) |
| Crypto primitives              | All NIST/IETF-standard; one **deviation from FIPS 203 ML-KEM KeyGen** (uses CSPRNG indirection, not d/z directly) |
| AEAD header binding (AAD)      | **Absent.** All key-relevant headers cause decryption failure on tamper, but `alias` (plaintext metadata) is unauthenticated. |
| Argon2id parameters            | Significantly exceed OWASP / RFC 9106 minimums (m=64 MiB, t=25, p=4) |

**No exploitable defect identified in this pass.** Findings are recommendations / hardening / spec-alignment improvements.

---

## Checks completed

### 1. Static read of all in-scope files

- [x] `rust/src/crypto/mod.rs`
- [x] `rust/src/crypto/kdf.rs`            — Argon2id key derivation
- [x] `rust/src/crypto/keypair.rs`        — X25519 keypair derivation
- [x] `rust/src/crypto/ml_kem.rs`         — ML-KEM-1024 keypair derivation
- [x] `rust/src/crypto/hkdf.rs`           — HKDF-SHA256 hybrid + YubiKey combiners
- [x] `rust/src/crypto/aes_gcm.rs`        — AES-256-GCM seal/open
- [x] `rust/src/crypto/vault_crypto.rs`   — Seal/open orchestration (V2/V4 multi-key, passphrase change, add/remove key)
- [x] `rust/src/vault/mod.rs`
- [x] `rust/src/vault/entry.rs`           — Entry types + Zeroize derives
- [x] `rust/src/vault/file_format.rs`     — `.gabbro` serializer (V2–V5)
- [x] `rust/src/vault/io.rs`              — Disk read/write
- [x] `rust/src/vault/serialization.rs`   — `VaultBody` JSON + legacy migration
- [x] `rust/src/vault/session.rs`         — In-memory session state, CRUD, merge, autofill

### 2. Dependency audit

- [x] `cargo audit` run against current Cargo.lock (211 crates) — see Appendix A
- [x] Crate version currency cross-checked against `cargo search` — see Appendix B
- [x] `flutter pub outdated` — all direct deps current; minor transitive lag (see Appendix B)
- [x] `flutter pub deps` reviewed for unexpected crates — none

### 3. Repository hygiene

- [x] `.gitignore` review — `key.properties`, `**/*.keystore`, `**/*.jks` all excluded
- [x] `git check-ignore -v` confirms `android/key.properties` and `android/app/gabbro-upload.jks` are ignored
- [x] `git log --all -p` grep for `BEGIN PRIVATE KEY` / `storePassword` / `keyPassword` — **no actual secrets ever committed** (matches are placeholder template text and code that *reads* properties)
- [x] Source-tree grep for `password|secret|api_key|token = "…"` patterns — **no hardcoded credentials**
- [x] No `unsafe`, `transmute`, `asm!` blocks in `rust/src/crypto/` or `rust/src/vault/`
- [x] No `println!` / `eprintln!` / `dbg!` / `log::` calls in scope (no risk of debug-leak of secrets)

### 4. Cryptographic primitive review

- [x] **Argon2id** parameters vs RFC 9106 / OWASP recommendations
- [x] **X25519** keypair derivation path
- [x] **ML-KEM-1024** keypair derivation vs FIPS 203 (NIST PQC)
- [x] **HKDF-SHA256** combiner construction vs draft-ietf-pquip-pqt-hybrid-terminology and X-Wing
- [x] **AES-256-GCM** nonce generation (OsRng), tag handling, AAD usage
- [x] **`vault_key_master` reuse** across CRUD saves (multi-key vaults) — nonce-collision analysis
- [x] **Key zeroization** — `Zeroize` / `ZeroizeOnDrop` coverage of entry types and session state
- [x] **Multi-key vault** passphrase change correctness (key_blobs invariance)

### 5. External references consulted

- [x] OWASP Secure Code Review Cheat Sheet (categories mapped to gabbro — see § "OWASP mapping")
- [x] NIST CSRC Cryptographic Standards (see § "NIST alignment")
- [x] RFC 9106 (Argon2), RFC 5869 (HKDF), RFC 7748 (X25519)
- [x] FIPS 203 (ML-KEM), FIPS 197 (AES), NIST SP 800-38D (GCM)
- [x] Recurity Labs Proton Pass Security Assessment & Retests, project 526.2501, v1.1 (2026-05-07, 57 pages) — read in full from `docs/artefacts/526.2501-Recurity_Labs-Report-Proton_Pass-v1.pdf`. All 8 scored findings + 6 unscored observations mapped to gabbro's posture in the new section "Lessons from Proton Pass audit (Recurity Labs 526.2501)" below.

---

## Findings

Severity scale: **High** = immediate exploitable defect | **Medium** = realistic exposure under plausible threat model | **Low** = hardening / spec alignment / defence in depth | **Info** = informational.

### F-01 (Low) — AES-GCM does not authenticate the vault header (no AAD)

**Status — FIXED (VERSION 7, 2026-06-05).** The architectural incompatibility described in the 2026-06-01 reclassification was resolved by enforcing unlock as a precondition for all header-mutating operations:

- `set_vault_alias` now requires an active (unlocked) session and re-seals the body so the new alias is bound as AAD.
- `add_yubikey_to_vault` / `remove_yubikey_from_vault` call `reseal_vault_body` after modifying the YubiKey records list so the updated header is committed as AAD.
- `change_vault_passphrase_with_keys` re-seals the body with the new header material.

The `header_aad()` function in `vault/file_format.rs` now commits every plaintext header field — Argon2id parameters, both salts, ML-KEM ciphertext, X25519 ephemeral public key, all YubiKey records (credential IDs, salts, key blobs), alias, and passphrase_blob — to the AES-GCM authentication tag. Modification of any of these without the vault key causes body decryption to fail. Vaults below VERSION 7 are migrated on first save. YubiKey credential IDs remain visible in the plaintext header by design (needed for key selection at the unlock screen), but can no longer be changed silently.

**Where:** `rust/src/crypto/aes_gcm.rs:27` (`cipher.encrypt(nonce, plaintext)`), `:44` (`cipher.decrypt(nonce, ciphertext)`)

**Detail.** Every AEAD call passes raw plaintext / ciphertext with no AAD. The plaintext `.gabbro` header — magic, version, Argon2 params, both salts, both nonces, ML-KEM ciphertext, X25519 ephemeral pubkey, YubiKey records, alias, `passphrase_blob` — is therefore outside the GCM authentication scope.

**Why this is mostly safe.** Every header value that *feeds* key derivation (Argon2 params, salts, ML-KEM ciphertext, X25519 ephemeral pubkey) causes the derived AES key to differ when modified, so AES-GCM authentication fails closed on tamper. A modified header produces "decryption failed" — no plaintext leakage.

**Residual exposure.**
- **`alias` (VERSION 5+, plaintext metadata):** an attacker with file-system access can rewrite the vault's display name without detection. Pure metadata; no credential compromise.
- **`credential_id`** in `YubiKeyRecord`: not key-binding; observable to anyone with file access (this is already by design — needed for key-selection at unlock).
- **Record-ordering / record-deletion** of `yubikey_records`: removing a record makes that key unable to unlock, but the remaining records still decrypt. Equivalent to a denial-of-access for one key, not a key disclosure.

**Recommendation (defence in depth).** Pass the serialised header (everything before the body length prefix) as AAD to `cipher.encrypt` / `cipher.decrypt`. This binds every header byte to the tag and detects metadata-tier tampering. Bump file VERSION on rollout and migrate on first save.

---

### F-02 (Low) — ML-KEM-1024 KeyGen deviates from FIPS 203 (uses ChaCha-PRNG indirection)

**Status — REMEDIATED (2026-06-01, VERSION 6).** Implemented recommendation (a): `ml-kem` 0.2.3 already exposes `KemCore::generate_deterministic(d, z)` behind its no-dependency `deterministic` feature, so **no version bump of `ml-kem` and no `rand` migration were needed**. `MlKemKeypair::from_kdf_output_fips` now feeds `d = kdf[32..64]`, `z = kdf[64..96]` directly into FIPS 203 §7.1 KeyGen, consuming all 64 bytes. The legacy `StdRng` path is retained as `from_kdf_output_legacy` for VERSION ≤5 vaults and dispatched on the file's version byte (`ml_kem_keypair_for_version` in `vault_crypto.rs`). The X25519 sibling observation below was deliberately **not** changed — clamping a uniform seed is standard, not a FIPS conformance gap. Verified by `crypto::ml_kem` tests (determinism, `z`-byte consumption, FIPS≠legacy) and a `legacy_version_5_vault_still_opens` regression.

**Where:** `rust/src/crypto/ml_kem.rs:23–34`

**Detail.** FIPS 203 §7.1 specifies `ML-KEM.KeyGen(d, z)` where `d, z ∈ {0,1}^256` are sampled from a uniform RBG. The current implementation:

```rust
let seed: Zeroizing<[u8; 32]> = Zeroizing::new(kdf_output[32..64].try_into().unwrap());
let mut rng = StdRng::from_seed(*seed);
let (decapsulation_key, encapsulation_key) = MlKem1024::generate(&mut rng);
```

- Uses only the first 32 bytes of the 64-byte ML-KEM portion of KDF output (`[32..64]`); bytes `[64..96]` are unused.
- Routes the seed through `StdRng` (ChaCha12) to materialise `(d, z)`, rather than feeding the seed bytes directly into `KeyGen(d, z)`.

**Why this is mostly safe.** `StdRng` is a cryptographic PRNG seeded with 256 bits of Argon2-derived material; the resulting `(d, z)` pair is uniquely determined by the passphrase and salt and is computationally indistinguishable from a fresh RBG sample. Security level of the keypair is still 256-bit (matches ML-KEM-1024 target). No exploitable weakness.

**Why it still matters.**
- Not FIPS-203-conformant if the project ever needs to claim FIPS compliance.
- The unused 32 bytes are silently discarded — confusing to readers (the doc-comment on `kdf.rs:31–37` claims the 64 bytes are split into `d, z`, which is **factually inaccurate**).
- If a future reviewer maps gabbro's keypair to a FIPS test vector, it won't match.

**Recommendation.** Either:
- (a) Use the deterministic `KeyGen(d, z)` API directly with `d = kdf[32..64]`, `z = kdf[64..96]` — restores FIPS 203 alignment and uses all 64 bytes. Requires verifying ml-kem 0.2.3 exposes a path to this (or upgrading to 0.3.x — see Appendix B).
- (b) Keep the PRNG approach and **update the doc-comment in `kdf.rs:33–37`** to state that 32 bytes are used as the ML-KEM RNG seed and the trailing 32 bytes are reserved. Also consider shrinking the KDF output to 64 bytes to remove the dead bytes.

Same observation applies to **`X25519Keypair::from_kdf_output`** (`keypair.rs:23–33`) — it routes the 32-byte seed through `StdRng` before clamping. Cryptographically equivalent to clamping the seed directly; just an unnecessary level of indirection.

---

### F-03 (Low) — Hybrid KEM combiner does not bind to public values

**Where:** `rust/src/crypto/hkdf.rs:21–37`

**Detail.** The combiner is `HKDF-SHA256(salt, ml_kem_ss ∥ x25519_ss, info="gabbro-hybrid-kex-v1") → 32 bytes`.

Modern hybrid PQ-KEM constructions (X-Wing, `draft-ietf-tls-hybrid-design`) additionally include the **KEM ciphertext** and the **public keys** in the combiner input, e.g.

```
ikm = ml_kem_ss ∥ x25519_ss ∥ ml_kem_ct ∥ x25519_ephemeral_pk ∥ x25519_static_pk
```

Including these values is what gives the combiner "binding to the transcript" and proven IND-CCA security in the hybrid setting even if one component degrades.

**Why this is mostly safe.** ML-KEM-1024 is itself IND-CCA secure and X25519 with `ReusableSecret` ECDH is well-studied. Gabbro is already using a contributory salt (32-byte random per seal) inside HKDF, which gives strong randomness binding. No concrete attack is known against concat-then-KDF combiners that use IND-CCA components.

**Recommendation.** When formal cryptographic audit lands (pre-v1 gate), discuss with the reviewer whether to migrate to an X-Wing-style transcript-binding combiner. If yes, this is a file-format-incompatible change (VERSION bump) and should land before v1.0.0.

---

### F-04 (Low) — Long-lived secrets in `VaultSession` are not `Zeroizing<T>`

**Where:** `rust/src/vault/session.rs:54` (`pub passphrase: Vec<u8>`), `:41` (`pub hmac_secret: Vec<u8>` inside `YubikeyMaterial`).

**Detail.** `lock_vault` (`session.rs:159–179`) explicitly calls `.zeroize()` on both fields before dropping the session, so the **normal path is covered**. However:

- A panic during a CRUD operation that unwinds past `lock_vault` (e.g. inside `do_save`) leaves the passphrase in memory until `Drop` runs on the `VaultSession` — which itself does **not** zeroize (the fields are plain `Vec<u8>`, not `Zeroizing<Vec<u8>>`).
- A SIGKILL / OOM-kill / unexpected process exit skips `lock_vault` entirely.
- An async-aborted task between unlock and lock could leak.

**Why this is mostly safe.** Rust's panic unwinding will still run `Drop` for everything on the stack — but plain `Vec<u8>` drop just frees the heap allocation without zeroing it. The allocator may reuse the pages immediately, but in pathological cases (suspend-to-disk, core dump, swap, memory dump) the bytes survive.

**Recommendation.** Change the field types:

```rust
pub struct VaultSession {
    ...
    pub passphrase: zeroize::Zeroizing<Vec<u8>>,
    pub yubikey: Option<YubikeyMaterial>,
    ...
}

pub struct YubikeyMaterial {
    pub hmac_secret: zeroize::Zeroizing<[u8; 32]>,   // also fix type: was Vec<u8> with runtime length check
    ...
}
```

The `vault_key_master` and `wrapping_key` fields are already `Option<Zeroizing<[u8; 32]>>`. The passphrase and hmac_secret fields are inconsistent with that pattern.

Also: `LoginAutofillSummary` (`session.rs:706–710`) and the JSON returned by `get_entry_for_autofill` (`session.rs:756–769`) contain plaintext passwords / usernames in plain `String`. These cross the JNI boundary into Kotlin, where Rust cannot zeroize them. This is documented as accepted in the function doc-comment (the password is only transferred at the moment the user has explicitly selected an entry). Acceptable for v1; revisit in v2 with passkey support.

---

### F-05 (Info) — `serde_json::to_string_pretty` for plaintext export writes secrets in clear

**Where:** `rust/src/vault/session.rs:676–698` (`session_export_vault_json`)

**Detail.** This is an explicitly user-initiated flow gated by a Flutter-side warning (per ARCHITECTURE.md "Export" feature line). The Rust code itself does what it says on the tin. No defect.

**Note for future hardening.** The temporary `json` `String` in Rust is not zeroized after `fs::write` completes. The export file on disk is plaintext by design. Acceptable.

---

### F-06 (Info) — `unwrap()` calls on `try_into` of length-checked slices

**Where:** `rust/src/crypto/vault_crypto.rs:423, 440, 592`

```rust
let pb_nonce: [u8; 12] = sealed.passphrase_blob[..12].try_into().unwrap();
```

Each of these is preceded by an explicit `len == 60` (or similar) length check, so the `unwrap` is provably unreachable. CLAUDE.md style guide says "no `unwrap()` in non-test code"; the call sites are safe but could be `.expect("length checked above")` for grep-clean compliance. Pure style.

---

### F-07 (Info) — Documentation drift between `kdf.rs` comment and `ml_kem.rs` implementation

**Status — FIXED (2026-06-01).** The `kdf.rs` doc-comment now states `[32..64] = d`, `[64..96] = z` for the FIPS path and explicitly documents the legacy path's dead-bytes behaviour. Fixed together with F-02.

**Where:** `rust/src/crypto/kdf.rs:33–37` (doc-comment) vs `rust/src/crypto/ml_kem.rs:23–35` (implementation).

The doc-comment claims:

> bytes [0..32] → X25519 private key
> bytes [32..96] → ML-KEM-1024 private key seed

Implementation actually uses bytes `[32..64]` only (one 32-byte seed for `StdRng`). Linked to F-02 above; fix together.

---

### F-08 (Low) — Vault files written without explicit user-only (0600) permissions

**Where:**
- `rust/src/vault/io.rs:20`           `fs::write(path, bytes)` (sealed `.gabbro` body)
- `rust/src/api/vault.rs:815`         `fs::write(export_path, &vault_bytes)` (vault export)
- `rust/src/api/vault.rs:836`         `fs::write(&hash_path, hash_hex)` (sidecar `.gabbro.sha256`)
- `rust/src/vault/session.rs:696`     `fs::write(&export_path, json.as_bytes())` (plaintext JSON export)

**Detail.** Every vault-file write uses `std::fs::write` (or the test-only `tokio::fs::write` analogue), which creates the file with `0o666 & ~umask`. Most Linux distributions default to umask `022`, so vault files land at mode `0644` (world-readable). The vault body is AES-GCM encrypted and therefore safe, but the plaintext header (magic, version, Argon2 params, salts, ML-KEM ciphertext, X25519 ephemeral pubkey, YubiKey credential IDs, alias) is exposed to any local user.

**This is the lesson from Recurity Labs finding 526.2501.002** ("Insecure Permissions on Session Token Files"): even when the file is encrypted at rest, a defence-in-depth posture sets `0600` so that file metadata, schema fingerprints, and YubiKey credential IDs aren't observable to siblings on the host.

**Recommendation.** Replace bare `fs::write` with an explicit-mode atomic write. The Proton audit (526.2501.003) showed that `OpenOptions::new().write(true).create_new(true).mode(0o600)` is incomplete because it no-ops on existing files (the mode bits are not adjusted on truncate). The robust pattern, recommended by Recurity Labs at the end of 526.2501.002, is:

```rust
// pseudo-code; needs unix-only cfg
use std::os::unix::fs::OpenOptionsExt;
let tmp = path.with_extension("gabbro.tmp");
let mut f = OpenOptions::new()
    .write(true).create(true).truncate(true)
    .mode(0o600)
    .open(&tmp)?;
f.write_all(&bytes)?;
f.sync_all()?;
drop(f);
fs::rename(&tmp, path)?;   // atomic on POSIX
```

Windows path can stay on `fs::write` since file-level ACLs are different there.

---

### F-09 (Low) — No symlink validation on vault read/write paths

**Where:** `rust/src/vault/io.rs:18–30` (`write_vault`, `read_vault`).

**Detail.** Both functions accept a `&Path` from the caller and feed it directly to `fs::write` / `fs::read`. Neither calls `symlink_metadata` first. If an attacker with write access to the parent directory replaces the vault path with a symlink before the user saves, the write follows the symlink and overwrites the symlink's target. Likely targets: another vault (data destruction), a system config file the user can write (denial-of-service), or — if the vault sits in a directory that another user can mutate — a file the attacker chose.

**This is the lesson from Recurity Labs finding 526.2501.001** ("Lack of Symlink Validation") on `pass-cli/src/store.rs`. Proton fixed it by inserting `match std::fs::symlink_metadata(&file_path) { Ok(m) if m.is_symlink() => Err(...), ... }` before opening — same fix applies here.

**Recommendation.** Reject symlinks at both read and write time:

```rust
if path.exists() {
    let m = std::fs::symlink_metadata(path)?;
    if m.file_type().is_symlink() {
        return Err("Vault path is a symlink — refusing for security reasons".into());
    }
}
```

The temp-file-then-rename pattern from F-08 already mitigates the write-time race against pre-creation symlink attacks; F-09 handles the case where the *destination* path is itself a symlink.

---

### F-10 (Info) — Android autofill uses eTLD+1 (registrable domain) matching, not strict FQDN

**Where:**
- `android/app/src/main/kotlin/app/gabbro/gabbro/UnlockActivity.kt:90, :167`
- `android/app/src/main/kotlin/app/gabbro/gabbro/GabbroAutofillService.kt:68`

**Detail.** Per ARCHITECTURE.md ("eTLD+1 domain matching; Chromium/Brave compatible"), credentials stored for `foo.example.com` will be offered when the user lands on `bar.example.com`. This is a deliberate UX choice that matches the behaviour of every major password manager, including Proton Pass.

**This is the lesson from Recurity Labs finding 526.2501.201** ("Missing FQDN Match may leak Credentials on Subdomains"). Recurity Labs flagged it as an observation rather than a vulnerability — and on retest acknowledged it as "a UX tradeoff made by most applications operating in the same space" — but documented it because a security-first default would require exact FQDN matching.

**Recommendation (post-v1).** Add a user-facing toggle in Settings → Security: "Strict FQDN matching for autofill (recommended for high-security profiles)". Default off (preserves current UX); when on, the matcher must compare the full host, not the registrable domain. Bikeshed candidate, not a release-blocker.

---

### F-11 (Low) — Decrypted/serialized vault body lingered in non-zeroized heap

**Status — FIXED (2026-06-01).** Surfaced by the new memory-forensics self-test (Appendix C item 6), not by static review — a worked example of why dynamic testing complements code review.

**Where:** `rust/src/api/vault.rs` — `load_vault` / `load_vault_with_yubikey` / `load_vault_with_key_record` (decrypt → `Vec<u8>` plaintext JSON → deserialize) and the five `serialize_vault_body` save sites.

**Detail.** `open_vault*` returns the decrypted vault body as a plain `Vec<u8>` holding every entry's password in cleartext JSON. Although each `VaultEntry` is `ZeroizeOnDrop` (so the parsed copy is scrubbed by `lock_vault`'s `entries.clear()`), the raw decrypted-JSON buffer was dropped without zeroizing. A `gcore` dump taken *after* lock still contained an entry password on 12/12 runs, while the master passphrase — `Zeroizing` end-to-end — was correctly absent.

**Fix.** Wrap the decrypted/serialized body in `Zeroizing<Vec<u8>>` at all load and save sites so it is scrubbed on drop. Verified empirically: post-fix, 12/12 `gcore` runs show both the passphrase and the entry password absent from the locked dump.

---

## Lessons from Proton Pass audit (Recurity Labs 526.2501)

This section maps each finding in the **Recurity Labs Proton Pass Security Assessment & Retests** (project 526.2501, v1.1, 2026-05-07, 57 pages — available at `docs/artefacts/526.2501-Recurity_Labs-Report-Proton_Pass-v1.pdf`) to gabbro's posture. Proton Pass is a fundamentally different stack (Electron / V8 / backend API / multi-account / SQLite-on-Android) so many findings don't apply directly — but the lessons generalise.

The Proton report scored **8 findings** (1 medium, 7 low) and recorded **6 unscored observations**. Recurity Labs' rating scale: 0.0 = None, 0.1–3.9 = Low, 4.0–6.9 = Medium, 7.0–8.9 = High, 9.0–10.0 = Critical (CVSSv3.1).

### Scored findings

| Proton ID         | Description                                              | CVSS | Applicable to gabbro? | Gabbro action                                                          |
|-------------------|----------------------------------------------------------|------|-----------------------|-------------------------------------------------------------------------|
| 526.2501.001      | Lack of Symlink Validation (`pass-cli/src/store.rs`)     | 2.8  | **Yes**               | New finding **F-09** above. Same fix pattern as Proton's patch.        |
| 526.2501.002      | Insecure Permissions on Session Token Files              | 3.3  | **Yes**               | New finding **F-08** above. Vault file is encrypted; header is plaintext. |
| 526.2501.003      | Non-atomic Permission Setting may Enable Race Conditions | 3.3  | **Yes**               | Covered by **F-08** recommendation (temp-file + atomic rename).        |
| 526.2501.004      | TOCTOU in Process Termination Logic (`kill_process_by_pid`) | 3.2 | No                | Gabbro does not kill external processes. `unsafe { libc::kill }` is not present in scope. |
| 526.2501.101      | Username Appears In Device Storage (Android Pass app)    | 2.3  | **Mostly no**         | Gabbro has no account / email / sign-in. Vault alias is visible in the plaintext header (by design; see F-01 — fixed in VERSION 7, alias integrity now enforced via AAD). No log files. No SQLite. |
| 526.2501.102      | Inconsistent User Data Removal (SQLite WAL retention)    | 4.4  | No                    | Gabbro is single-file (`.gabbro`) — not SQLite. Deletion is `fs::remove_file`. **Architectural choice that avoids this entire bug class.** |
| 526.2501.301      | iOS Weak Keychain Protection Class                       | 1.9  | **Not yet**           | iOS port is v2+. **Bikeshed entry recommended** — when iOS lands, use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for any Keychain-stored secret (probably none, since gabbro doesn't store the master passphrase). |
| 526.2501.201      | Missing FQDN Match may leak Credentials on Subdomains    | N/A  | **Yes**               | New finding **F-10** above. Same eTLD+1 default as Proton; same defensible UX tradeoff. |

### Unscored observations

| Proton ID         | Description                                              | Applicable to gabbro? | Gabbro action                                                          |
|-------------------|----------------------------------------------------------|-----------------------|-------------------------------------------------------------------------|
| 526.2501.901      | Cipher Suite (`TLS_AES_128_CCM_SHA256`) not aligned with TLS 1.3 best practice | No | Gabbro is local-first; no backend, no TLS endpoint. **Architectural choice.** |
| 526.2501.905      | Insecure Volatile Secret Obfuscation (single-byte XOR of key in memory, CLI) | **Cautionary** | Gabbro does **not** currently obfuscate secrets in memory — relies on `Zeroize` + minimal lifetime. The Proton case is a worked example of why naive XOR-in-process-memory is worse than no obfuscation. **L-1: don't add this as a "quick fix" later** — if memory hardening is needed, offload to OS keyring (Linux `secret-service`, Android `Keystore`), not in-process XOR. |
| 526.2501.906      | Credentials Recoverable from Memory (Desktop, V8 strings + XOR pairs) | **Partial — generalised** | Gabbro's secrets live in Rust with `Zeroizing<T>` — the V8 string-immutability problem doesn't apply. **However**, `LoginAutofillSummary` and `get_entry_for_autofill` cross JNI as plaintext `String`. Already noted in **F-04**; this audit confirms the generic risk. **L-2: minimise plaintext-secret lifetime at the FFI boundary; prefer `&[u8]` over `String` where the API allows.** |
| 526.2501.907      | Secret Cache Persists Upon Lock/Logout                   | **Yes — verify**      | Gabbro's `lock_vault` (`session.rs:159`) explicitly zeroizes `passphrase`, `hmac_secret`, `vault_key_master`, `wrapping_key` and `entries.clear()`. **Verified.** Linked to **F-04** for the residual Zeroize-typing gap. |
| 526.2501.908      | Unsafe Secret Types Enable Secret Enumeration (JS immutable strings) | No (Rust-specific advantage) | Rust `String` is mutable; `Zeroize` can clear it. Gabbro's `VaultEntry` types `#[derive(Zeroize, ZeroizeOnDrop)]`. **Architectural advantage** of Rust over Electron for this class of attack. |
| 526.2501.909      | Indefinite Cache Lifetime (no auto-lock initially)       | **Yes — present**     | Gabbro has foreground + background auto-lock timeouts (Settings → Security). Documented in ARCHITECTURE.md ("Auto-lock: 30s default, configurable"). **Confirmed gabbro is in line with Proton's mitigated state.** |
| 526.2501.913      | Insecure Obfuscation (hardcoded `0xDE` XOR key, Android Pass) | **Cautionary**   | Same lesson as 905. Gabbro does not currently do this. **L-1 applies.** |

### Lessons captured (informational)

- **L-1 (from 905, 913):** Naive XOR-in-process-memory obfuscation is anti-defence — the key sits next to the ciphertext. If gabbro ever needs in-memory hardening beyond `Zeroize`, the correct answer is OS keyring offload (Linux `libsecret`, Android `Keystore`), not in-process XOR.
- **L-2 (from 906, 907, 908):** Plaintext secrets crossing FFI boundaries (gabbro: Rust → JNI → Kotlin → Android Autofill) cannot be zeroized by the originating language. Minimise the lifetime of such strings — release them on the Kotlin side immediately after `FillResponse` is built.
- **L-3 (from 301):** For the iOS port (V2+), use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for any Keychain-stored secret. Add to ARCHITECTURE.md Bikeshed when iOS work starts.
- **L-4 (from 102):** Gabbro's choice of a single binary `.gabbro` file (no SQLite, no WAL) avoids an entire class of "deleted user data lingers" bugs. Worth keeping in `LEARNINGS.md` as a *positive* architectural decision that paid off.
- **L-5 (from 901):** Gabbro's "no backend, no sync server" choice avoids the entire TLS-cipher-suite review surface. Also worth a `LEARNINGS.md` note.
- **L-6 (general):** Recurity Labs' methodology was code-review + dynamic testing + memory forensics (Frida, Burp, MobSF, core-dump parsing). Gabbro now runs a `gcore` memory-forensics self-test (Appendix C item 6) — it immediately surfaced F-11, vindicating the "dynamic testing finds what code review misses" lesson. Extending it (YubiKey path, GUI process) remains a pre-v1 task.

---

## Supply-chain audit — Track A Phase 1 (2026-06-01)

**Performed by:** Claude Sonnet 4.6  
**Scope:** dependency trees, IDE extensions, CI configuration.

### Rust — `cargo audit`

Re-run against current Cargo.lock (211 crates, advisory DB 1100 advisories). **No new findings since 2026-05-31.** Same 4 warnings:

| ID                 | Crate              | Class        | Exploitable in gabbro? | Action                                                    |
|--------------------|--------------------|--------------|------------------------|-----------------------------------------------------------|
| RUSTSEC-2025-0056  | `adler 1.0.2`      | unmaintained | No                     | Transitive via `miniz_oxide → backtrace → tokio`. Upstream fix.   |
| RUSTSEC-2026-0097  | `rand 0.8.5`       | unsound      | No                     | Triggered only by a custom logger calling `rand::rng()` / `thread_rng()` during panic. Gabbro uses no custom logger. Gabbro uses `OsRng` for all crypto material; `thread_rng()` is used only in password/passphrase generators and FIDO client-data-hash generation — non-exploitable. Clear by upgrading to `rand 0.9` when `flutter_rust_bridge` allows. |
| RUSTSEC-2025-0023  | `tokio 1.34.0`     | unsound      | No                     | Broadcast channel `Sync` unsoundness. Gabbro does not use `tokio::sync::broadcast`. Transitive via `flutter_rust_bridge 2.12.0`; fix gated on FRB upgrade. |
| —                  | `futures-util 0.3.29` | yanked    | No                     | Still functional. Transitive via `serial_test` (dev) + `flutter_rust_bridge`. |

**Correction to original Appendix A:** that entry stated "Gabbro uses `OsRng` directly — not affected" for RUSTSEC-2026-0097. This was incomplete: `rand::thread_rng()` is also called in `password_generator.rs:65`, `passphrase_generator.rs:72`, and `fido/device.rs:34,125,155,270`. The assessment (not exploitable without a custom logger) stands; the description is updated above.

### Flutter/Dart — dependency audit

`flutter pub audit` and `dart pub audit` do not exist. No Pub-side equivalent of `cargo audit` or `npm audit` is available in the Dart SDK as of 2026-06-01. Checked instead with:

- `flutter pub outdated`: all **direct** and **dev** dependencies up-to-date. Five transitive deps (code_assets, hooks, meta, vector_math, win32) have minor version bumps available; none have known security advisories.
- OSV Scanner (`osv-scanner`) not installed. Install and run against `pubspec.lock` before v1 if a Pub-side vulnerability is reported.

**Recommendation:** add `osv-scanner --lockfile pubspec.lock` to the pre-release checklist once CI exists.

### IDE extensions

Three extensions installed in VS Code:

| Extension ID                | Publisher         | Purpose                 | Trust |
|-----------------------------|-------------------|-------------------------|-------|
| `dart-code.dart-code`       | Dart Code team    | Dart language support   | ✓ Official |
| `dart-code.flutter`         | Dart Code team    | Flutter tooling         | ✓ Official |
| `rust-lang.rust-analyzer`   | rust-lang org     | Rust language server    | ✓ Official |

All three are maintained by their respective official organisations. No third-party or community extensions in the IDE that could intercept secrets or inject build steps. **No action required.**

### CI GitHub Actions — SHA pinning

No CI workflows exist yet (`.github/` contains only `FUNDING.yml`). When CI is added:

- Pin every `uses: owner/action@version` to a full commit SHA (`uses: owner/action@<sha>`) and keep the tag as a comment.
- Example: `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2`
- Add `cargo audit` and `osv-scanner` steps to the CI matrix.

**Add to Bikeshed:** "Pin CI Actions to commit SHAs; add `cargo audit` + `osv-scanner` steps (once CI exists)."

---

## NIST alignment

| Component                | Standard                  | Conformance                                              |
|--------------------------|---------------------------|----------------------------------------------------------|
| AES-256-GCM              | FIPS 197, NIST SP 800-38D | ✓ Standard. 12-byte random nonce ≤ 2³² invocations safe. |
| Argon2id                 | RFC 9106, OWASP           | ✓ Exceeds recommended minimums (m=64 MiB / t=25 / p=4). |
| HKDF-SHA256              | RFC 5869 / NIST SP 800-56C | ✓ Standard salt + info usage; domain separation present. |
| X25519                   | RFC 7748, FIPS 186-5      | ✓ Standard ECDH; ephemeral on sealer side.              |
| ML-KEM-1024              | FIPS 203                  | ✓ `KeyGen(d, z)` as of VERSION 6 (F-02 remediated 2026-06-01); legacy path retained to read VERSION ≤5 vaults. |
| Hybrid combiner          | (no FIPS, IETF drafts)    | ⚠ Two-step: Phase 1 `HKDF(hkdf_salt, ml_kem_ss ∥ x25519_ss, "gabbro-hybrid-kex-v1")` → `intermediate_key`; YubiKey mode adds Phase 2 `HKDF(yubikey_salt, intermediate_key ∥ hmac_secret, "gabbro-yubikey-v1")` → `vault_key`. Phase 1 is a concat-then-KDF without transcript binding — see F-03. |
| FIDO2 / hmac-secret      | CTAP 2.1, FIDO Alliance   | ✓ Out of scope for this audit (see ADR-010).             |
| RBG / RNG                | NIST SP 800-90A           | ✓ `OsRng` for all fresh material (Linux `getrandom`).    |

**Argon2id parameter justification.** RFC 9106 second-recommended profile is `m=64 MiB, t=3, p=4`. Gabbro uses `t=25`, which is ~8× the RFC time cost. This was tuned via `bin/bench_kdf.rs` to target ~667ms on the user's hardware (ARCHITECTURE.md line 70 comment). At m=64 MiB the memory cost matches the RFC; the elevated time cost is a defensible conservative choice for an offline vault that is unlocked at most a few times per day per device.

---

## OWASP mapping (Secure Code Review Cheat Sheet)

| Category                              | Gabbro stance                                                                          |
|---------------------------------------|----------------------------------------------------------------------------------------|
| Input validation                      | CardEntry length validation present; binary header parser bounds-checks every field.   |
| Injection (SQL/NoSQL)                 | N/A — no database. JSON serialization is via `serde_json`, no string concatenation.    |
| Authentication / session              | Argon2id + FIDO2 hmac-secret; min 2 keys (ADR-010). Master key never crosses bridge.   |
| Access control                        | Single-user local app; vault-level access only.                                        |
| Cryptography                          | See NIST alignment table; F-01 fixed (VERSION 7); F-03 open (transcript binding, human reviewer).  |
| Data flow                             | Secrets live in Rust; Flutter receives `EntrySummaryData` (no passwords) for list view. Autofill JSON is a documented, narrowly-scoped exception (F-04). |
| Business logic                        | Multi-key invariant (≥2 keys); passphrase change preserves all key_blobs; legacy V2 path explicit. |
| Configuration / deployment            | Keystore + key.properties git-ignored and verified absent from history.                |
| Security monitoring                   | No logging of secrets (zero `println!` / `log::` in crypto/vault). Acceptable for a local vault. |

---

## Appendix A — `cargo audit` output (2026-05-31)

Database: RustSec advisory-db, 1099 advisories.
Crates scanned: 211. **CVEs / RUSTSEC vulnerabilities: 0.** Warnings: 4 (informational).

| ID                 | Crate            | Class          | Notes                                                                          |
|--------------------|------------------|----------------|--------------------------------------------------------------------------------|
| RUSTSEC-2025-0056  | `adler 1.0.2`    | unmaintained   | Transitive via `miniz_oxide → backtrace → tokio` & `allo-isolate`. Use `adler2` upstream. |
| RUSTSEC-2026-0097  | `rand 0.8.5`     | unsound        | Affects `rand::rng()` with custom logger. Gabbro uses `OsRng` directly — not affected. Upgrade to `rand 0.9` or `0.10` recommended. |
| RUSTSEC-2025-0023  | `tokio 1.34.0`   | unsound        | Broadcast channel `Sync` issue. Gabbro does not use `tokio::sync::broadcast`. Old version pulled by `flutter_rust_bridge 2.12.0`. |
| —                  | `futures-util 0.3.29` | yanked    | Yanked by upstream; transitive via `serial_test` (dev) + `flutter_rust_bridge`. Still functional. |

**Action:** None of these are exploitable in gabbro's call patterns. Schedule a tokio + rand + futures bump when `flutter_rust_bridge` releases an update that doesn't pin tokio 1.34.

---

## Appendix B — Dependency version currency (2026-05-31)

| Crate / package        | Gabbro     | Latest stable      | Notes                                          |
|------------------------|------------|--------------------|------------------------------------------------|
| `aes-gcm`              | 0.10.3     | 0.10.3 (0.11.0-rc) | ✓ Current stable.                              |
| `argon2`               | 0.5.3      | 0.5.3 (0.6.0-rc)   | ✓ Current stable.                              |
| `x25519-dalek`         | 2.0.1      | 2.0.1 (3.0.0-rc)   | ✓ Current stable.                              |
| `ml-kem`               | 0.2.3      | **0.3.2**          | ⚠ One minor behind. Worth reviewing changelog (see F-02 — 0.3.x may expose a deterministic KeyGen path). |
| `hkdf`                 | 0.13.0     | 0.13.0             | ✓                                              |
| `sha2`                 | 0.11.0     | 0.11.0             | ✓                                              |
| `rand`                 | 0.8.5      | 0.10.1             | Two majors behind. RUSTSEC-2026-0097 advisory does not affect gabbro. Upgrade to align with ecosystem and clear the advisory. |
| `zeroize`              | 1.8.2      | 1.8.2              | ✓                                              |
| `uuid`                 | 1.23.0     | 1.23.2             | ✓ Effectively current.                         |
| `serde`                | 1.0.228    | 1.x                | ✓ Current.                                     |
| `serde_json`           | 1.0.149    | 1.x                | ✓ Current.                                     |
| `base64`               | 0.22.1     | 0.22.1             | ✓                                              |
| `once_cell`            | 1.x        | 1.21.4             | ✓ semver flex.                                 |
| `libfido2-sys`         | 0.5.1      | 0.5.1              | ✓                                              |
| `flutter_rust_bridge`  | =2.12.0    | (pinned)           | Pinned per project policy. Pulls older tokio/futures. |
| `jni` (rust)           | 0.21       | 0.21               | ✓                                              |
| **Flutter direct deps**| —          | —                  | `flutter pub outdated` — **all direct deps up-to-date**. Three transitive deps lag (meta, vector_math, win32) — non-security. |

**Conclusion.** No deprecated or AI-hallucinated crates. No mis-named look-alikes. All dependencies resolve to crates.io entries that match their stated purpose. The two version-currency items worth scheduling are `ml-kem 0.3.x` (linked to F-02) and `rand 0.9/0.10` (clears one advisory).

---

## Appendix C — Items deferred to human cryptography review

This AI audit is informational. The Bikeshed pre-v1 gate still requires:

1. **Academic / RustCrypto-maintainer review** of the hybrid construction in `vault_crypto.rs`. F-03 (transcript-binding combiner) is the primary open question. F-01 and F-02 are fixed; the reviewer should verify the implementations but no design questions remain for those.
2. **Side-channel analysis** of the Argon2id / X25519 / ML-KEM call sites against the chosen target hardware. AI cannot reason about timing/cache leakage at compiled-code level.
3. **Formal model** of the multi-key vault state machine (`seal_vault_with_keys`, `add_key_to_sealed`, `remove_key_from_sealed`, `change_vault_passphrase_with_keys`) to verify the invariant "any single registered key unlocks; passphrase change does not invalidate any key_blob".
4. **External cryptographic audit** as listed in ARCHITECTURE.md → Bikeshed → "Security (pre-v1 gates)".
5. **Hardware-attested testing** on de-Googled Android (GrapheneOS / CalyxOS) for the FIDO2 hmac-secret path. Out of scope of this static review.
6. **Memory-forensics testing of gabbro itself** — **DONE (2026-06-01).** Implemented as a reproducible self-test: `rust/scripts/mem_forensics.sh` + the `--features forensics` harness (`rust/src/bin/mem_forensics.rs`). It seals a vault with two distinct high-entropy canaries (master passphrase + a Login entry's password), takes a `gcore` dump while unlocked (canaries present) and after lock (must be absent), and reports PASS/FAIL. The first run surfaced **F-11** (entry password lingered in the decrypted-body buffer); after the fix, 12/12 runs PASS. Reviewers can reproduce it. Still recommended before v1: extend to the YubiKey-unlock path and run under the real GUI process.

---

## Appendix D — Threat model notes (informational)

This audit assumed the standard local-storage threat model for a password manager:

- **In scope.** Tampered vault files; offline brute force of passphrase; file disclosure / theft; partial memory disclosure of an unlocked process; a malicious app trying to read another app's vault; supply-chain compromise via dependencies.
- **Out of scope.** Compromised target OS / root user; compromised YubiKey hardware; coercion; side-channels at the silicon level; physical extraction of unlocked-process RAM.

Findings are calibrated to the in-scope threat model. The "Low" severity ratings are not a claim that issues are unimportant — they are a claim that under the in-scope threat model no concrete exploit path was identified during this read.
