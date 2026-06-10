# ADR-013: Vault Export Security Posture and Informed Downgrade

## Status
Accepted

## Date
2026-06-10

## Context

A vault created with passphrase + YubiKey(s) layers the hardware key *on top of*
the passphrase: neither factor alone reconstructs the vault key (ADR-010). The
whole point of choosing hardware protection is that **knowing the passphrase is
not enough** — a stolen `.gabbro` file plus a known passphrase still cannot be
opened without a registered key.

Export silently broke that guarantee. `export_vault` always re-sealed the body
**passphrase-only** (`seal_vault(passphrase, …)`, no key records), so exporting a
key-protected vault produced an artifact openable by the passphrase *alone*. The
import/sync path (`import_from_gabbro` → `load_vault(passphrase, …)`) then opened
that artifact with no key required.

Discovered 2026-06-10 by hardware test on Linux: a vault protected with
passphrase + YubiKeys was exported to `vaultA.gabbro`; a second, yubikeyless
vault then **synced** from it supplying only the passphrase — gaining full access
to data the first user had deliberately put behind hardware. An attacker who
learns the passphrase and obtains the exported file completely bypasses the
second factor the user chose. This is a secure-by-default violation: the export
weakened the user's protection without their consent or knowledge.

This concern was foreseen. ADR-002's alternatives table noted *"Sign the export
with the user's YubiKey — interesting for v2"* and deferred it. This ADR resolves
the underlying issue now, but **not** via the deferred signing idea: rather than
add a signature, we **preserve the existing hmac-secret keyslot** so a registered
key remains required to open an exported key-protected vault. Signing the export
remains a separate, still-deferred v2 idea.

Threat model (unchanged from ADR-010/012): one user per device; the YubiKey is a
real second factor whose value is that the passphrase alone is insufficient.

## Decision

Export and import **respect the source vault's protection, and never weaken it
without an explicit, informed user action.** Concretely:

1. **Export preserves protection by default.** Exporting a key-protected vault
   produces a key-protected artifact (the registered keyslots are retained);
   exporting a passphrase-only vault produces a passphrase-only artifact. The copy
   is no weaker than the original.

   **Mechanism — byte-for-byte copy of the sealed file.** The default export
   copies the encrypted vault on disk verbatim to the destination (plus its
   detached `.sha256`, per ADR-002). The on-disk file already carries the
   registered keyslots, so the copy is provably no weaker than the original — the
   simplest construction that cannot accidentally drop a factor (no re-seal, no
   fresh crypto). **The vault alias is preserved in the copy** — it is a harmless
   local label and there is no reason to strip it. (Only the *opt-in
   passphrase-only* export decrypts and re-seals; the default never does.)

2. **Import/sync enforces the source's protection.** Syncing from a key-protected
   export requires the source passphrase **and** a registered YubiKey. Passphrase
   alone is refused, with a message stating a key is required (l10n).

3. **Protection class is immutable in place.** A vault created with YubiKeys
   always requires ≥1 YubiKey; a vault created passphrase-only stays
   passphrase-only. The class never changes in place, in *either* direction — no
   in-place downgrade (drop the last key) and no in-place upgrade (add a first key
   to a passphrase-only vault). To change class, create a new vault and import.
   Within the key-protected class, keys may still be rotated/added/removed down to
   the ADR-010 floor of one; the passphrase may always be rotated. (Rotation
   changes the *material*, not the *class*.)

4. **The user may export a passphrase-only copy on purpose.** The export screen
   offers a toggle to export a key-protected vault *without* its YubiKey
   protection — a passphrase-only artifact. This empowers the user to make a
   deliberate, convenient copy (e.g. for unattended sync) without ever mutating
   the original vault, which stays key-protected exactly as created.

### Toggle behaviour (secure by default)

- **Key-protected vault:** the "export passphrase-only" toggle is shown and
  defaults **OFF** — the export keeps YubiKey protection. The user must actively
  turn it ON to strip it.
- **Passphrase-only vault:** there is nothing to strip; the toggle is hidden /
  disabled.
- **The vault's protection type is always visible to the user in the export
  flow** (which kind of vault they are exporting, and what the toggle will do),
  fully localised. The user never strips a factor without being told.

**Mechanism — the toggle threads through the bridge.** The toggle is a UI choice,
but the file is written in Rust. The boolean ("export passphrase-only?") is passed
from the export screen → the `exportVault` bridge call → `session_export_vault` →
`export_vault`, so the byte-writing code knows whether to copy the sealed file
verbatim (OFF, default) or decrypt and re-seal passphrase-only (ON). It is the
only new value threaded through.

### Authorizing the downgrade (auth already scales with protection)

Turning the toggle ON requires only the **already-authenticated session** plus a
clear warning — no fresh YubiKey tap. The user necessarily tapped a registered
key to unlock the key-protected vault in this session, so possession is already
proven. If the toggle is flipped by mistake the user can cancel before writing,
or delete the resulting file afterwards — no harm, no foul, and responsibility
stays with the user. This mirrors ADR-012's principle that authorization scales
with the protection the user chose, and the existing precedent of the
fully-plaintext JSON export living behind a visible warning rather than a second
hardware gate.

**Invariant (must not regress; is tested):**
- Exporting a key-protected vault with the toggle **OFF** yields an artifact that
  **cannot** be opened or synced by passphrase alone — a registered YubiKey is
  required.
- Syncing such an artifact **with** a registered key (and the source passphrase)
  succeeds.
- Exporting with the toggle **ON** yields a passphrase-only artifact that *is*
  openable by passphrase alone (the intended, opt-in downgrade).

These are pinned by automated Rust tests using fake key records (the
`vault_backward_compat` / `setup_multi_key_vault` pattern — no hardware needed);
the Flutter export/import UI prompts are device-tested in Phase 2.

### Implementation note — two front-ends, both enforced (2026-06-10)

"Import/sync" (decision §2) is **two distinct Gabbro→Gabbro front-ends** over the
same merge core, and they were fixed in two steps:

- **Import entries** (`import_from_gabbro` / `_with_key`, the Import screen) — wired
  to the key-protected path first.
- **Sync from file** (`merge_vault_from_file`, the vault menu's "Sync from file") —
  initially still passphrase-only. A key-protected source was correctly *refused* by
  the crypto (the invariant held — no bypass), but the path never offered the key, so
  it surfaced the misleading "different passphrase" error and could not sync at all.

Found the same day by hardware test (Linux export → Android sync). Closed by
`merge_vault_from_file_with_key`, the exact mirror of `import_from_gabbro_with_key`:
the sync UI now reads the source header, prompts for a registered YubiKey (PIN +
USB/NFC transport on Android), and opens with passphrase **+** key. Both front-ends
reuse the same l10n and the shared `getAnyYubikeyHmacSecret` tap helper (DRY). The
invariant above is now pinned for the sync path too
(`merge_vault_from_file_with_key_syncs_keyprotected_source` and the passphrase-alone
refusal test in `vault_bridge.rs`).

### Implementation note — Android export writes via SAF (2026-06-10)

The default export (§1) writes a `.gabbro` + `.gabbro.sha256` into a user-chosen
folder. On Android this folder is shared storage. The original implementation
wrote via a raw POSIX path (temp file + `fs::rename`), which fails with `EPERM`
when the destination already exists and was created by **another app** — exactly
the case when exporting into a folder a NAS/sync client populated. Under scoped
storage (targetSdk ≥ 30, and Gabbro requests **no** `MANAGE_EXTERNAL_STORAGE`), an
app may create a new file in a shared folder but may not replace another app's
file via raw paths. Found 2026-06-10 by hardware test (`Operation not permitted`
on re-export over a synced `Gabbro.gabbro`).

Fix: Android `.gabbro` export goes through the **Storage Access Framework**. The
user already grants a directory tree via the folder picker
(`ACTION_OPEN_DOCUMENT_TREE`); a SAF tree grant permits overwriting *any* file in
the tree regardless of creator. So:

- **No new manifest permission** — the grant is scoped to the one folder the user
  picks, is persisted (`takePersistableUriPermission`, remembered in
  `androidExportFolderUri`), and is revocable in Android Settings. This is the
  least-privilege option and aligns with the app's security posture; All-Files
  Access was explicitly rejected.
- **Split build from write:** Rust produces the export **ciphertext** bytes +
  SHA-256 line (`build_export_bytes` / `build_export_passphrase_only_bytes`,
  sharing the helpers with the Linux path-write so neither drifts); Kotlin writes
  them into the granted tree via `DocumentFile` (`app.gabbro.gabbro/export`
  channel). Only ciphertext crosses the bridge — no plaintext secret.
- **Find-then-overwrite:** the SAF writer looks up the existing child by name and
  overwrites it in place (`openOutputStream(uri, "wt")`), never blind-creating —
  which would trip SAF's `Name (1).gabbro` de-duplication and break a fixed-name
  sync target.
- **Linux unchanged** (raw-path write keeps its 0600 + atomic-rename semantics).
- **Plaintext JSON export is deliberately excluded** from SAF: routing it would
  force plaintext secrets across the Flutter/Rust bridge (forbidden). JSON keeps
  its raw-path write; overwriting a non-owned JSON in shared storage still fails
  (a documented, low-impact limitation — JSON is a one-off migration export, not a
  sync target).

## Consequences

### Positive
- Closes the silent second-factor bypass: a key-protected vault's data stays
  behind hardware through export and sync.
- Secure by default, with an explicit, informed, reversible downgrade — "inform
  but empower."
- The vault's protection class is a stable, predictable property: what you
  created is what you keep.
- No new vault format VERSION: a key-protected export is the same existing
  multi-key format, so no new golden fixtures are required.

### Negative / Tradeoffs
- **Key-protected exports cannot be synced unattended.** Importing one requires a
  YubiKey tap, so it cannot be automated. Gabbro ships no built-in sync today; the
  practical impact is that a user wiring up their own backup/sync (e.g. `rsync`
  via `cron` to a NAS) of a *key-protected* export will need to be present to tap
  a key on restore. A user who wants hands-off sync can deliberately export
  passphrase-only (toggle ON) and accept the weaker protection — exactly the
  choice this ADR makes explicit.
- Import/sync gains a YubiKey code path and an additional UI prompt (source vault
  is key-protected → ask for a key).
- The export screen gains a toggle, an always-visible protection-type indicator,
  and new localised strings.

## References
- ADR-002 (Detached SHA-256 hash on export) — flagged and deferred the
  "sign the export with the YubiKey" idea to v2; this ADR addresses export
  security via keyslot preservation instead, leaving signing deferred.
- ADR-010 (YubiKey FIDO2 hmac-secret authentication) — the layered
  passphrase+key model and the minimum-one-key floor this ADR upholds.
- ADR-012 (Vault deletion and privacy-mode access) — "authorization scales with
  the protection the user chose"; the precedent reused here for the downgrade
  gate and the 3-2-1 backup responsibility.
