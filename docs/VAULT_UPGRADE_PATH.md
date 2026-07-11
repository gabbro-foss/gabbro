# Vault Upgrade Path (VERSION 11)

Why a stepping-stone release exists, and how to upgrade safely.

## Background

Vaults ≤ v10 carry an X25519 + ML-KEM-1024 hybrid key-exchange layer that is
**not load-bearing** (ADR-018): both keypairs derive from the same Argon2id output,
so vault security rests on Argon2id + AES-256-GCM regardless. The layer is dead weight
and the only user of the `ml-kem` and `x25519-dalek` crates (supply-chain surface).
VERSION 11 removes it — the vault key derives straight from the Argon2id output via
HKDF. Old vaults upgrade to v11 automatically the first time they are opened or saved.

## The two releases

- **Release N (interim):** opens v2–v10 **and** v11. Auto-migrates any ≤v10 vault to
  v11 on first unlock/lock (also on passphrase change / CRUD save). The hybrid-KEM
  derivation code stays, read-only, to open older vaults.
- **Release N+1 (RT-3):** opens **v11 only**. The legacy derivation code is removed and
  the `ml-kem` + `x25519-dalek` crates are dropped. A ≤v10 file is rejected with a clear
  "unsupported version" error.

## How to upgrade (mandatory order)

1. Install **Release N**.
2. Open every vault once (unlock is enough) → each becomes v11 in place
   (atomic write + `.bak`, no export/reimport, no extra YubiKey tap).
3. Confirm no ≤v10 vault remains.
4. Install **Release N+1** and continue from there.

## Caveat — do not skip Release N

Release N is a **mandatory stepping stone**. Installing Release N+1 with a vault
still ≤ v10 leaves that vault unopenable by the new build; recovery = reinstall
Release N, open the vault to migrate it, then move on. A vault sitting untouched
on disk stays at its old version until something opens it — installing a release
does not migrate files on its own.

All of the above happens before public release; no external user is affected.
