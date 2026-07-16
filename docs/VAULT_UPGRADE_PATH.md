# Vault Upgrade Path (VERSION 11)

Why a stepping-stone release exists, and how to upgrade safely.

## Got "file version not supported"?

Your vault is in a format older than v11. Gabbro alpha.15 and later cannot open it.
**Your vault file has not been changed** — it is intact and recoverable:

1. Install **alpha.14** —
   [releases](https://github.com/gabbro-foss/gabbro/releases/tag/v0.1.0-alpha.14).
2. Open every vault once. Unlocking is enough; each upgrades itself to v11 in place.
3. Install alpha.15 or later and carry on.

Do not skip step 2 — installing a release does not upgrade files on its own; a vault
stays at its old version until something opens it.

## Background

Vaults ≤ v10 carry an X25519 + ML-KEM-1024 hybrid key-exchange layer that is
**not load-bearing** (ADR-018): both keypairs derive from the same Argon2id output,
so vault security rests on Argon2id + AES-256-GCM regardless. The layer is dead weight
and the only user of the `ml-kem` and `x25519-dalek` crates (supply-chain surface).
VERSION 11 removes it — the vault key derives straight from the Argon2id output via
HKDF. Old vaults upgrade to v11 automatically the first time they are opened or saved.

## The two releases

- **Release N — alpha.14 (interim):** opens v2–v10 **and** v11. Auto-migrates any ≤v10
  vault to v11 on first unlock/lock (also on passphrase change / CRUD save). The
  hybrid-KEM derivation code stays, read-only, to open older vaults.
- **Release N+1 — alpha.15 (RT-3):** opens **v11 only**. The legacy derivation code is
  removed and the `ml-kem` + `x25519-dalek` crates are dropped. A ≤v10 file is rejected
  with `file version not supported`, linking here. The file is never modified.

## How to upgrade (mandatory order)

1. Install **alpha.14**.
2. Open every vault once (unlock is enough) → each becomes v11 in place
   (atomic write + `.bak`, no export/reimport, no extra YubiKey tap).
3. Confirm no ≤v10 vault remains.
4. Install **alpha.15+** and continue from there.

## Caveat — do not skip alpha.14

alpha.14 is a **mandatory stepping stone**. Installing alpha.15+ with a vault still
≤ v10 leaves that vault unopenable by the new build — but never damaged: the recovery
is to reinstall alpha.14, open the vault to migrate it, then move on. A vault sitting
untouched on disk stays at its old version until something opens it — installing a
release does not migrate files on its own.

alpha.14 stays available permanently: the repo has GitHub immutable releases enabled,
so its tag and assets can never be replaced or removed.
