# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Background lock is now reliable on Android (Doze mode) and Linux with any WM or display server (X11/Wayland). The previous `dart:async Timer`-based background lock was replaced with a dual strategy:
  - **Timestamp approach** (Android + Linux workspace-switch): record the time the app backgrounds (`hidden`/`paused` on Android; `inactive` on desktop); on `resumed`, lock if the elapsed time exceeds the configured timeout. Reliable regardless of OS process scheduling.
  - **Timer approach** (Linux focus-switch, app still visible): when `inactive` fires on desktop the process is still alive, so a real `Timer` is also started. This locks the vault after the timeout even if the user never returns focus to Gabbro — preventing the vault from staying visibly unlocked on a tiling WM while another window is active.

### Fixed
- Passphrase generator: digit insertion now picks from valid UTF-8 char-boundary offsets, preventing `insert_str` panics on multi-byte codepoints in non-English wordlists (FR/DE/ES/IT).
- Tests: three passphrase tests were flaky because four words in `wordlist_en.txt` contain hyphens (`drop-down`, `felt-tip`, `t-shirt`, `yo-yo`). Tests that split on `"-"` or asserted its absence hit these words ~10 % of the time over 50 iterations. Fixed by using `"|"` as the test separator and dropping the unreliable token-count assertion from `test_append_number`.

## [0.1.0-alpha.3] – 2026-06-02

### Fixed
- Android: cursor handle (teardrop) could not be dragged in any text field. Root cause: the app-wide inactivity-timer `GestureDetector` registered a `PanGestureRecognizer` that competed in Flutter's gesture arena against the text-handle's own recognizer and won. Replaced with a `Listener` (raw pointer events, no arena participation); `onPointerDown` preserves the same timer-reset semantics.
- l10n: font-size preview text in Appearance screen is now translated (was hard-coded English in all locales).
- l10n: all entry-form field labels, validator messages, and tooltips in the create/edit screen now use ARB keys (17 new keys across 5 locales). Card status ('active'/'lapsed'/'inactive') is stored as a stable English identifier and translated at display time.
- l10n: CSV-imported entries no longer land in a hard-coded English "Personal" folder — they are now unfoldered.

### Added
- Export screen: "Include date in filename" toggle. When off, the exported filename is `alias.gabbro` / `alias.json` (stable name for rsync/file-sync workflows). Default: on. Available on both Linux and Android.
- Crack-me vault challenge: `challenge/decryptMe_2026-06-01.gabbro` — a real vault sealed with a 256-char random passphrase and two YubiKeys, published for public security testing. Proof of crack = vault note contents + passphrase + method; reward is two YubiKey keys. See `challenge/README.md`.
- `docs/SECURITY.md`: user-facing security overview covering both auth modes, encryption scheme, local-first argument, verified claims, known limitations (F-01, F-03), threat model, and two comparison tables.
- Supply-chain audit (Track A Phase 1): `cargo audit` (4 warnings, none exploitable), `flutter pub outdated` (all direct deps current), VS Code extensions reviewed (3 official). Results recorded in `docs/AI_SECURITY_AUDIT.md`.

### Fixed
- Doctest parse errors in `rust/src/api/entropy.rs`: bare indented code blocks containing Unicode characters (`×`, `₂`) were compiled by rustdoc and failed to parse. Wrapped with ` ```text ` fences.

### Security
- Vault file format **VERSION 6**: the ML-KEM-1024 keypair is now derived via FIPS 203 `ML-KEM.KeyGen(d, z)` directly from the KDF output (`d = bytes[32..64]`, `z = bytes[64..96]`), replacing the `StdRng`-seeded indirection that consumed only 32 of the 64 ML-KEM seed bytes (audit findings F-02 and F-07). New vaults are written as VERSION 6.
- Backward compatible: existing VERSION 2–5 vaults remain fully readable. The keygen is dispatched on the file's version byte (legacy `StdRng` path for ≤5, FIPS path for 6), so no re-import is required.
- Cleartext residue fix: decrypted and serialized vault-body buffers are now held in `Zeroizing<Vec<u8>>`, so entry secrets are scrubbed from memory rather than left in freed heap after a vault is locked. Found by a new `gcore` memory-forensics self-test (`rust/scripts/mem_forensics.sh` + `--features forensics` harness; audit L-6) that confirms both the master passphrase and entry passwords are absent from a core dump taken after lock.
- Vault files are now written with user-only `0600` permissions via an atomic temp-file-and-rename, and symlinks at the vault path are rejected on read and write (audit F-08, F-09).
- Long-lived in-memory session secrets (master passphrase, YubiKey hmac-secret, derived keys) are now `Zeroizing`, so they are scrubbed on drop as well as on explicit lock (audit F-04).

## [0.1.0-alpha.2] – 2026-05-31

### Fixed
- Foreground lock fired while typing: keyboard events now reset the inactivity timer (previously only pointer events did).
- Background lock did not fire on desktop Linux tiling WMs (e.g. Qtile on Arch): `AppLifecycleState.hidden` (window minimised / workspace switch) now starts the background timer alongside `paused`.

## [0.1.0-alpha.1] – 2026-05-30

### Added
- Post-quantum vault encryption: Argon2id KDF → X25519 + ML-KEM-1024 hybrid → HKDF-SHA256 → AES-256-GCM (`.gabbro` binary format)
- Vault lifecycle: create, unlock, lock, change passphrase
- 6 entry types: Login (Password), Note, Identity, Card, File, Custom; all with custom fields
- Entry create, edit, delete with safe-edit diff review and password history / revert
- FIDO2/WebAuthn authentication via YubiKey: Android (USB + NFC via yubikit) and Linux (USB via libfido2); hardware-validated on both
- Minimum-2-keys enforcement (ADR-010); multi-key unlock, vault delete, and change-passphrase wiring (CTAP2 one-tap, any registered key); manage YubiKeys screen (add, remove, alias); PIN visibility toggle on PIN fields
- Multiple vaults: registry (`vaults.jsonc`) with per-vault alias and type (passphrase | yubikey); ManageVaultsScreen (add / rename / delete); tiered delete (2-step passphrase, 3-step YubiKey with PIN + tap); high-security login hides the vault list by default
- Password generator: classic (32–256 chars) and passphrase (4–20 words, 5 languages, EFF wordlists); password breakdown sheet (colour + symbol encoding per ADR-003)
- Vault list search: title-only (default) or full-field toggle
- Folders: create, rename, delete, reassign; folder filter on vault list; folder picker on create/detail screens; multi-select assign-to-folder; folder changes shown in the review-diff
- Alphabet index bar (height-adaptive, configurable left/right); tablet two-pane layout (≥600dp): NavigationRail + list + detail pane
- Export: `.gabbro` + `.gabbro.sha256`; plaintext JSON with unencrypted warning; file-entry export via native picker
- Import: Gabbro vault, Enpass JSON, Bitwarden JSON, generic CSV (column-mapping UI); validation failures surfaced via dialog (Skip / Edit)
- Android autofill service (fill path; eTLD+1 domain matching; Chromium/Brave compatible)
- Appearance settings: theme (system/light/dark), text size, high-contrast, alphabet bar position
- Language settings: dedicated Language screen + onboarding picker; UI localised in EN/FR/DE/IT/ES; follows system locale by default; locale-aware dates via `package:intl`
- Security settings: foreground + background lock timeouts; copy/paste blocking on passphrase fields; Android screenshot prevention + app-switcher blur (`FLAG_SECURE`)
- Branding: theme-aware `GabbroLogo` widget (wired into unlock / onboarding / about / splash); Android launcher icons at all mipmap densities
- Dark and light mode; WCAG AA colour scheme (olivine green `#5C7A3E`)

### Fixed
- YubiKey OTP NDEF URI no longer opens a browser tab during NFC unlock; `skipNdefCheck` and re-armed foreground dispatch suppress NDEF dispatch while the app is foreground — `ykman config nfc --disable OTP` is no longer required
- Enpass import: entries land in the "None" folder (the category name was incorrectly used as the folder name)

[Unreleased]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.1...HEAD
[0.1.0-alpha.1]: https://github.com/Zabamund/gabbro/releases/tag/v0.1.0-alpha.1
