# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Security settings: foreground + background lock timeouts; copy/paste blocking on passphrase fields
- Android screenshot prevention and app-switcher blur (`FLAG_SECURE`)
- Dark and light mode; WCAG AA colour scheme

[Unreleased]: https://github.com/Zabamund/gabbro/compare/v0.1.0...HEAD
