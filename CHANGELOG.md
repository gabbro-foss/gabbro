# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-alpha.6] – YYYY-MM-DD

### Security
- **Vault export no longer strips YubiKey protection (ADR-013).** Exporting a vault protected with passphrase + YubiKey(s) previously re-sealed the copy *passphrase-only*, so anyone who knew the passphrase could open or sync that exported file with no YubiKey — silently defeating the second factor the user had chosen. Export now preserves the source vault's protection by copying the sealed file byte-for-byte: a key-protected vault stays key-protected, and syncing from it requires the passphrase **and** a registered YubiKey. Passphrase-only vaults are unchanged. A deliberate, opt-in passphrase-only export (an explicit downgrade) remains available and never alters the original vault. The export screen shows each vault's protection and offers the opt-in downgrade toggle (default off); the import screen detects a key-protected source and prompts for a registered YubiKey (with a "tap your key now" cue) before syncing. Found by hardware test 2026-06-10; the full export → key-protected sync flow is verified on Linux and Android (USB + NFC). Rust core, bridge, and both UI halves landed with unit + widget tests.
- **Vault-deletion privacy fix (ADR-012).** When the privacy setting *Show vault list* is off (the default), deleting the vault you were using could briefly reveal another vault's name on the unlock screen, and could leave your other vaults hard to reach. Deletion now works only from a *different* vault's unlocked session (you stay in that session afterwards); the vault you are currently in can be deleted only when it is the last one, after which the app returns to onboarding. YubiKey-protected vaults still require a registered key to delete. Removes a dead, leak-prone code path; YubiKey-required-to-delete is covered by an automated test.
- Vault-format backward-compatibility harness (`rust/tests/vault_backward_compat.rs`): the safety net for the 2026-06-08 vault-brick class. Loads **frozen golden `.gabbro` vaults committed to git** (one set per format VERSION, sealed by the build that shipped it) and proves the current code can still read every v6+ vault (passphrase-only and YubiKey multi-key), migrate it to the current VERSION on re-seal, and survive the full YubiKey loss/rotation journey (create with two keys → lose one/add a replacement, twice → still unlockable, floor of one key) starting from both v6 and v7. Extended with passphrase-change coverage — passphrase-only change, and a passphrase change interleaved with the YubiKey rotation journey, plus a wrong-old-passphrase guard — and an opt-in seeded-`rand` state-machine fuzzer (`vault_state_machine_fuzz.rs`) that randomises the order of {change_passphrase, add/remove key}. Unlike a round-trip test, frozen old bytes catch a breaking seal/open change before it ships. Net-new tests; no production code change. Generation recipe and the per-VERSION release gate are in `rust/tests/fixtures/FIXTURES.md`; the gate (run `--release`) is wired into the Release Process pre-flight. 10 gate tests.

### Added
- Vault management: a *Backups & emergency wipe* info dialog (info icon in the app bar). Explains that Gabbro does not back up vaults — keep a copy on another device (3-2-1) — and documents the out-of-band emergency wipe (total, unauthenticated, irreversible): on Android, Settings → Clear data; on Linux, the two folder-delete commands shown verbatim, with a reminder that vaults saved to custom locations must be removed separately. New strings translated across all UI locales (best-effort for some; community refinement welcome).
- Tablet / landscape two-pane layout: list pane width is now user-adjustable via a draggable divider. A grip badge (rotated `drag_handle` icon on a tinted pill) is always visible as a touch affordance. Width is persisted in `settings.jsonc` as `tablet_list_pane_width` (stored range 180–900 dp; effective max clamped to `screen_width − 300 dp` at runtime so the detail pane always has at least ~200 dp). Resize cursor shown on Linux/desktop hover. Works on Linux (mouse drag) and Android landscape (touch drag). 9 new widget tests.
- Import: Google Password Manager CSV importer (`rust/src/import/google_pm.rs`). Fixed-schema CSV from passwords.google.com (`name,url,username,password,note`). Extra columns become custom fields. Bridge function `import_from_google_pm`. UI section added to Import screen (position 3).
- Import: Dashlane credentials CSV importer (`rust/src/import/dashlane.rs`). Credentials CSV from Dashlane export (`username,username2,username3,url,category,note,password,title`). Alternate usernames become custom fields; `category` dropped. Bridge function `import_from_dashlane`. UI section added to Import screen (position 4).
- Import screen: section order revised — Gabbro, CSV, Google PM, Dashlane, Enpass, Bitwarden.
- l10n: `importGooglePmSubtitle` and `importDashlaneSubtitle` added to all 35 locale ARB files.
- Help carousel: 13th slide added for the encrypted vault sync process (`help_012_vault_sync.png`). Caption `helpCaptionVaultSync` translated in all 36 locales.
- Passphrase generator: Croatian, Lithuanian, Latvian, and Kazakh added as generator languages (`Language::Croatian/Lithuanian/Latvian/Kazakh`). Croatian, Lithuanian, and Latvian each use a 7,776-word list curated from hermitdave/FrequencyWords (CC-BY-SA 4.0) with explicit per-language character-class filters. Kazakh uses all 4,311 available words from the same corpus (limited corpus; Cyrillic script). System locale codes `hr`/`lt`/`lv`/`kk` auto-resolve to the matching wordlist; app language choices `LanguageChoice.hr/lt/lv/kk` map to the new variants. 4 new Rust entropy tests, 4 new Flutter widget tests.
- About screen: BIP-39 wordlists (ja/ko/zh-TW, MIT), ChineseWordDiceware (zh-CN, CC-BY-4.0), and FrequencyWords (hr/lt/lv/kk, CC-BY-SA 4.0) attribution entries added. `Diceware-word-lists` entry updated to cover both `et` and `uk`.
- Passphrase generator: CJK languages now have real wordlists instead of falling back to English. Japanese and Korean use the BIP-39 mnemonic lists (MIT, 2,048 words each); Chinese Simplified uses the cfbao diceware list (CC-BY 4.0, 7,776 words); Chinese Traditional uses the BIP-39 Traditional list (MIT, 2,048 words). `_hasPassphraseWordlist` simplified to always return true. 4 new Rust entropy tests.
- Passphrase generator: Dutch added as a generator language (`Language::Dutch`, 7,776-word diceware list, CC-BY, source: mko.re). Dutch device users are auto-resolved via system locale. `langDutch` translation key added to all 36 ARB files. 1 new Flutter test.
- UI locale: Dutch (`nl`) added. `app_nl.arb` (machine-translated). `LanguageChoice.nl` added to the enum; `langDutch` label wired in `language_screen.dart`.
- Generator: `LanguageChoice.nl` now maps to `Language.dutch` in `_languageChoiceToLanguage` so the passphrase wordlist follows the UI language. 31-case parameterised regression test added to guard all `LanguageChoice → Language` mappings.

### Fixed
- `langDutch` was machine-translated into each locale's own exonym (e.g. `"Holland"` in `app_hu.arb`, `"Hollandi"` in `app_et.arb`, `"Nederländska"` in `app_sv.arb`), so the language menu showed Dutch inconsistently depending on the UI language. Corrected to the Dutch endonym `"Nederlands"` across all 37 ARB files, matching the endonym convention already used for every other language label (e.g. `Deutsch`, `Français`). Generated localizations regenerated. A self-maintaining guard test (`test/l10n_test.dart`) now asserts every `lang*` label (excluding `langSystem`) is identical across all locale ARBs, so any future language or locale that breaks the endonym convention fails CI — 38 new Flutter tests (one per ARB plus a matcher sanity check).
- `langDutch` in `app_en.arb` corrected from exonym `"Dutch"` to endonym `"Nederlands"`, consistent with the convention used for all other language labels in the English ARB.
- Slovenian wordlist (`wordlist_sl.txt`) regenerated with an explicit Slovenian character class (`[abcčdefghijklmnoprsštuvzž]`), removing 68 contaminated words that were derivatives of foreign proper nouns (e.g. "andyjevimi", "auschwičani") introduced by the aspell-sl dictionary. Croatian, Lithuanian, and Latvian wordlists also use explicit character classes to prevent the same class of contamination.
- Password breakdown sheet: non-Latin letters (Greek, Cyrillic, etc.) were misclassified as symbols because `_classify` used ASCII-only regex (`[A-Z]`/`[a-z]`). Replaced with Unicode property escapes (`\p{Lu}`, `\p{Ll}`, `\p{Nd}`) using `unicode: true`. CJK and other scripts without case (Unicode category Lo) now show as a new ◆ **Letter** type (teal) rather than ■ Symbol. `charTypeLetter` translation key added to all 36 ARB files. 2 new TDD tests.

## [0.1.0-alpha.5] – 2026-06-06

### Security
- **Header integrity (F-01 / VERSION 7)**: the AES-256-GCM body is now sealed with the serialised plaintext header as additional authenticated data (AAD). Every plaintext header field — Argon2id parameters, salts, ML-KEM ciphertext, X25519 public key, YubiKey records, alias, passphrase_blob — is committed to the authentication tag. Any modification to the header without the vault key causes body decryption to fail immediately. The nonce is excluded from AAD because AES-GCM authenticates it implicitly.
- **Rename-requires-login**: `set_vault_alias` now requires an active (unlocked) session. The body is re-sealed with the new alias as AAD so the alias change is cryptographically binding.
- **Re-seal on all header mutations**: add-YubiKey, remove-YubiKey, and passphrase-change for multi-key vaults now all re-seal the body so the updated header is committed as AAD.
- **Alias preservation**: `save_vault` and `save_vault_with_yubikey` now read and preserve the existing alias from disk before a full re-seal, preventing CRUD saves from silently clearing an alias set at vault creation.
- **Flutter rename flow**: `onRename` in `main.dart` now calls `setVaultAlias` for the currently active vault, keeping the file-header alias in sync with the registry alias.
- **Alias bound to body at seal time**: `seal_vault`, `seal_vault_with_yubikey`, and `seal_vault_with_keys` now accept an `alias` parameter so the alias is part of the partial `SealedVault` before `header_aad()` is computed. Previously the alias was set on the returned struct after sealing, causing an AAD mismatch on every open.
- **Vault-list AppBar reflects rename immediately**: `VaultListScreen` now reads the active vault alias from `GabbroApp.registry` at build time rather than from the frozen `vaultAlias` prop set at unlock, so the AppBar title updates as soon as the user navigates back from Manage Vaults without requiring a lock/unlock cycle.
- **V6 multi-key vaults migrate to V7 on first CRUD save**: `reseal_vault_body` now bumps `sealed.version` to `VERSION` (7) before computing AAD, so passphrase+YubiKey vaults (and any other multi-key V6 vault) are transparently upgraded on the next re-seal operation.

### Fixed
- Classic password generator now uses the correct script on first render when the app language maps to Greek or Cyrillic. Previously the initial password was always Latin; only the first char-set toggle would trigger the right script. Root cause: `didChangeDependencies` set `_language` via `setState` but never called `_generate()`. Three TDD tests added (`Greek app language: initial classic password uses Greek script immediately`, `Russian app language: initial classic password uses Cyrillic immediately`, `Greek: toggling a char set keeps Greek script`).
- `_FallbackMaterialLocalizationsDelegate` in `main.dart`: `GlobalMaterialLocalizations` does not cover all BCP-47 tags (e.g. `yo` Yoruba, `nn` Norwegian Nynorsk). Selecting an unsupported locale caused a null-crash in `MaterialLocalizations.of()` — `BackButton` tooltip and any other Material widget that uses the `!` accessor. Fix: a custom `LocalizationsDelegate<MaterialLocalizations>` that returns `true` from `isSupported()` for every locale and loads English Material strings as a fallback for unsupported ones; ARB translations still load in the correct language.
- `docs/AI_SECURITY_AUDIT.md`: F-01 status corrected from "Reclassified" to "Fixed (VERSION 7)". The architectural incompatibilities cited in the reclassification (alias rename without unlock, key management without reseal) were resolved as part of the VERSION 7 work; the finding is fully addressed. Updated remediation table, "Still open" summary line, and the finding section text.
- `docs/SECURITY.md`: F-01 "Known limitations" section updated to reflect VERSION 7 header-integrity guarantee; stale "planned for a future version" text removed.

### Changed
- Dependency surface audit (Phase 1): replaced `once_cell::sync::Lazy` with `std::sync::LazyLock` (stabilised in Rust 1.80) in `vault/session.rs`; removed `once_cell` as a direct dependency.
- Dependency licence audit (Phase 2): ran `cargo update` (65 Cargo.lock entries updated within SemVer ranges; no `Cargo.toml` version bumps required). All Flutter direct deps already current per `flutter pub outdated`. Added missing `intl`, `jni`, and `libfido2-sys` to the Open Source Components list in About screen.

### Added
- Classic password generator: CJK character pools added — Japanese uppercase → Katakana (46 chars), lowercase → Hiragana (46 chars); Korean → combined Hangul syllables U+AC00–U+B52D (2350 chars); Chinese Simplified + Traditional → combined CJK Unified Ideographs U+4E00–U+5CAA (3755 chars, same pool for both). `Language` enum extended from 20 to 24 variants. In passphrase mode, CJK languages fall back to the English wordlist (honoring the existing "Using English" message) while classic mode continues to use the selected script. Manually picking a CJK language from the picker now correctly sets the `passphraseNoWordlist` info flag. `_hasPassphraseWordlist()` helper added to `generator_widget.dart`. 6 new Rust tests, 3 new Dart tests.
- Passphrase generator expanded from 5 to 20 languages. New wordlists: Swedish, Danish, Norwegian (covers nb+nn), Finnish, Slovenian, Polish, Russian, Hungarian, Czech, Greek, Portuguese (covers pt_PT+pt_BR), Estonian (7052 words, CC-BY-4.0), Slovak, Bulgarian (7527 words, CC-BY-4.0), Ukrainian. `Language` enum lives in `rust/src/api/types.rs`. `passphrase_entropy_bits()` uses the actual wordlist size so the entropy display is always accurate.
- Classic password generator is now script-aware: selecting Greek uses a 24-letter Greek alphabet pool; Russian and Ukrainian use a 33-letter Cyrillic pool; Bulgarian uses 30-letter Cyrillic. All Latin-script languages are unchanged. `exclude_ambiguous` remains Latin-only.
- Language picker moved to shared area of the generator widget — always visible regardless of whether Classic or Passphrase mode is active. Initial language resolved automatically from app settings / system locale via `didChangeDependencies`. The same selection drives both the passphrase wordlist and the classic character pool.
- Info message (`passphraseNoWordlist`) shown when the app language has no passphrase wordlist — translated in all 34 locales. Covers explicit language choices and the System locale.
- Manage Folders screen: info note explaining that default folders are placeholders and can be renamed or deleted — translated in all 34 locales.
- CC-BY-4.0 attribution for Estonian (`agreinhold/Diceware-word-lists`) and Bulgarian (`assenv/diceware-wordlist-bg`) wordlist sources added to About screen.
- Multi-language expansion — all 34 enum values complete. Language picker refactored from chips to scrollable sorted list (both Settings and onboarding). ARB files added for all 33 user-facing locales: pt_PT, pt_BR, da, nb, nn, sv, fi, et, hu, lt, lv, ru, uk, bg, pl, cs, sk, hr, sl, sr_Latn (+ sr fallback), el, ja, ko, zh_CN, zh_TW (+ zh fallback), kk, eu, yo. `LanguageChoice` enum: 33 user-facing + system = 34 total; `_localeFor()` handles complex BCP-47 tags. Note: kk (Kazakh) is AI-translated and recommended for native review before v1.
- In-app help screen: carousel of 12 annotated screenshots accessible from the main menu (Menu → Help). Swipeable `PageView` with per-slide localised captions and dot-indicator navigation. All 14 l10n keys translated across 5 languages (EN/DE/ES/FR/IT). Help images normalised: Flameshot border artefacts trimmed, uniform 8 px `#5C7A3E` padding applied to all 12 assets. Help is fully offline — no network request, no link to an external website or social media.
- `docs/SECURITY.md`: in-app offline help added to the competitor comparison table as a differentiator. Gabbro's help carousel requires no internet connection and makes no external calls, unlike apps that redirect users to company websites or social media for support.

## [0.1.0-alpha.4] – 2026-06-03

### Added
- Biometric unlock on Android (ADR-011, opt-in, default off):
  - Toggle in Settings → Security (Android only; hidden on Linux)
  - Passphrase encrypted with AndroidKeyStore AES-256-GCM key (`setUserAuthenticationRequired(true)`, `setInvalidatedByBiometricEnrollment(true)`); decrypted transiently at unlock, never held in Dart memory
  - Enrollment is per-vault: biometric enrolled for Vault A does not appear on Vault B's unlock screen
  - Key auto-invalidated and setting auto-disabled if any new biometric (including a second fingerprint) is enrolled at OS level
  - Passphrase field always co-present — biometrics are an option, not the only path
  - Clear user-facing dialogs explain what is stored, the all-enrolled-biometrics constraint, and the invalidation behaviour
  - 16 new l10n keys across 5 languages; 492 Flutter tests (+21); 8 new Kotlin tests (all `@Ignore`, hardware-required)

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

[0.1.0-alpha.5]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.4...v0.1.0-alpha.5
[0.1.0-alpha.4]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.3...v0.1.0-alpha.4
[0.1.0-alpha.3]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.2...v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/Zabamund/gabbro/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/Zabamund/gabbro/releases/tag/v0.1.0-alpha.1
