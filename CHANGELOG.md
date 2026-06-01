# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Vault file format **VERSION 6**: the ML-KEM-1024 keypair is now derived via FIPS 203 `ML-KEM.KeyGen(d, z)` directly from the KDF output (`d = bytes[32..64]`, `z = bytes[64..96]`), replacing the `StdRng`-seeded indirection that consumed only 32 of the 64 ML-KEM seed bytes (audit findings F-02 and F-07). New vaults are written as VERSION 6.
- Backward compatible: existing VERSION 2–5 vaults remain fully readable. The keygen is dispatched on the file's version byte (legacy `StdRng` path for ≤5, FIPS path for 6), so no re-import is required.

## [0.1.0-alpha.2] – 2026-05-31

### Fixed
- Foreground lock fired while typing: keyboard events now reset the inactivity timer (previously only pointer events did).
- Background lock did not fire on desktop Linux tiling WMs (e.g. Qtile on Arch): `AppLifecycleState.hidden` (window minimised / workspace switch) now starts the background timer alongside `paused`.

## [0.1.0-alpha.1] – 2026-05-30

### Added
- Post-quantum vault encryption: Argon2id KDF → X25519 + ML-KEM-1024 hybrid → HKDF-SHA256 → AES-256-GCM
- 6 entry types: Login (Password), Note, Identity, Card, File, Custom; all with custom fields
- Entry create, edit, delete with safe-edit diff review and password history / revert
- FIDO2/WebAuthn authentication via YubiKey: Android (USB + NFC) and Linux (USB via libfido2)
- Minimum-2-keys enforcement; manage YubiKeys screen (add, remove, alias)
- Password generator: classic (32–256 chars) and passphrase (4–20 words, 5 languages, EFF wordlists)
- Password breakdown sheet (colour + symbol encoding per ADR-003)
- Vault list search: title-only (default) or full-field toggle
- Alphabet index bar (height-adaptive, configurable left/right)
- Tablet two-pane layout (≥600dp): NavigationRail + list + detail pane
- Folder management: create, rename, delete, reassign; folder filter on vault list
- Multi-select assign-to-folder on vault list
- Export: `.gabbro` + `.gabbro.sha256`; plaintext JSON with unencrypted warning
- Import: Gabbro vault, Enpass JSON, Bitwarden JSON, generic CSV (with column-mapping UI)
- Import validation failures surfaced via dialog (Skip / Edit)
- Android autofill service (fill path; eTLD+1 domain matching; Chromium/Brave compatible)
- Appearance settings: theme (system/light/dark), text size, high-contrast, alphabet bar position
- Language settings: dedicated Language screen (Settings → Language); language picker on onboarding screen for first-time users; overrides system locale
- Security settings: foreground + background lock timeouts; copy/paste blocking on passphrase fields
- Android screenshot prevention and app-switcher blur (`FLAG_SECURE`)
- Dark and light mode; WCAG AA colour scheme
- App localisation: UI in English, French, German, Italian, and Spanish; follows system locale by default
- Locale-aware date formatting via `package:intl` `DateFormat`

### Fixed
- YubiKey OTP NDEF URI no longer opens a browser tab during NFC unlock; `skipNdefCheck` and re-armed foreground dispatch suppress NDEF dispatch while the app is foreground — `ykman config nfc --disable OTP` is no longer required

[Unreleased]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.1...HEAD
[0.1.0-alpha.1]: https://github.com/Zabamund/gabbro/releases/tag/v0.1.0-alpha.1
