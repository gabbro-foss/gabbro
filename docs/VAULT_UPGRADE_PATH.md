# Vault Upgrade Path (VERSION 10)

Why a stepping-stone release exists, and how to upgrade safely.

## Background

Vaults ≤ v9 derive part of their key through an outside library's random-number
helper (`rand::StdRng`), whose output is not guaranteed stable across major
versions — a latent brick risk (RT-3). VERSION 10 removes that dependency and
derives the key directly. Old vaults upgrade to v10 automatically the first time
they are opened or saved.

## The two releases

- **Release N (interim, e.g. alpha.13):** opens v2–9 **and** v10. Auto-migrates
  any ≤v9 vault to v10 on first unlock/lock (also on passphrase change / CRUD save).
- **Release N+1 (e.g. alpha.14):** opens **v10 only**. Legacy derivation code is
  removed. A ≤v9 file is rejected with a clear "unsupported version" error.

## How to upgrade (mandatory order)

1. Install **Release N**.
2. Open every vault once (unlock is enough) → each becomes v10 in place
   (atomic write + `.bak`, no export/reimport, no extra YubiKey tap).
3. Confirm no ≤v9 vault remains.
4. Install **Release N+1** and continue from there.

## Caveat — do not skip Release N

Release N is a **mandatory stepping stone**. Installing Release N+1 with a vault
still ≤ v9 leaves that vault unopenable by the new build; recovery = reinstall
Release N, open the vault to migrate it, then move on. A vault sitting untouched
on disk stays at its old version until something opens it — installing a release
does not migrate files on its own.

All of the above happens before public release; no external user is affected.
