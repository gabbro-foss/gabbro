# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Emergency sheet: `docs/EMERGENCY_SHEET.pdf`, a printable one-pager to fill in by hand (vault, passphrase, YubiKeys, folders) and keep on paper.
- Remembered folders. Export and Import entries each get a Remember box (ticked by default): the folder of the file you pick is remembered, the next file dialog opens there, and on Linux the export path is pre-filled so Export is one tap. Sync settings lists the export and import folders read-only. Untick to forget.
- One-click sync. Sync settings (vault menu): an auto-merge switch (off by default) and a remembered sync folder with a Remember box. With both set, Sync from vault opens the file named as this vault exports (`<alias>.gabbro`) in that folder and merges it with no picker, no chooser and no review; a YubiKey-protected file still asks for its tap, and a file your passphrase does not open still asks for one. Linux gains a native folder picker (XDG portal); Android reads the folder through its persisted storage grant.

### Fixed
- Help: all 16 cards re-shot at the current UI, terse captions, larger caption text; three new cards (Sync settings, Export, Import) and the sync diagram redrawn for the one-tap flow.
- Export: the two-files note now names the real file (`<alias>.gabbro`), not `vault.gabbro`.
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- Import screen: one file field and a Source dropdown (Gabbro vault, Generic CSV, Google Password Manager, Dashlane, Enpass, Bitwarden) replace the six stacked sections. Changing the type clears the chosen file.
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- Export: "Include date in filename" now defaults to off, so a repeat export overwrites the previous file instead of adding a dated copy. Turn it on for dated exports.
- flutter_rust_bridge 2.12.0 -> 2.13.0 (bridge regenerated; no behaviour change).

## [0.1.0-alpha.22] – 2026-08-23

### Added
- **Passkey provider.** Website passkeys (WebAuthn) can now live in the vault, so they sync and back up with everything else. Android: Gabbro registers as a credential provider. Linux: while Gabbro runs, browsers see it as a security key (a virtual FIDO2 device); create and sign-in are approved in an in-app dialog. New Passkey entry type and a Passkey filter chip on the vault list. Vault format v12; v11 vaults still open.
- APT repository for Debian/Mint: add it once, later releases arrive via `apt upgrade` / Update Manager.
- The `.deb` and AUR packages now set up `/dev/uhid` access (udev rule + module load), so Linux passkeys work after install without manual steps; the README covers the same setup for tarball users.
- Linux: when the passkey provider cannot start (uhid module missing, no `/dev/uhid` access, or a second Gabbro instance), the vault list now says so and points at the README fix — previously passkeys just silently never appeared in the browser. Dismissible per session or permanently.
- Crack-me challenge refreshed to a new v12 vault; the superseded vault was retired.
- Android: privileged-browser list refreshed from Google's reference list (adds Firefox Beta); now re-checked at every release.
- Android: **App passkeys** toggle (Settings, off by default) lets native apps sign in with passkeys. Turning it on is the informed opt-in to Gabbro's only network use: one fetch per app login of that site's own app-verification file — see the new README section "Verify no telemetry". Off, or with network denied (GrapheneOS), only app sign-ins refuse; browser passkeys never use the network.

*Built with Flutter 3.47.0, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.21] – 2026-08-18

### Added
- **File attachments on every entry type.** Any entry (not just File entries) can now hold up to 3 attached files of up to 25 MB each — add and remove them on the edit screen, save them back to disk from the entry view. Attachments imported from Enpass, previously invisible, now appear and can be recovered; sync names them by filename in every prompt.

### Fixed
- **Editing an entry no longer silently deletes its attachments.** Attachments (today only Enpass imports carry them) were wiped by any edit, and syncing then deleted them on every other device too. They now survive edits untouched.
- **Re-importing a file you have already imported no longer duplicates its entries.** Every import source now compares what an entry contains, instead of an id most export formats do not carry. Entries the vault already holds are listed as skipped, and an import that adds nothing says so rather than leaving the screen unchanged.
- **Serbian: the import screen named a file extension that does not exist.** It read `.габбро` instead of `.gabbro`, so anyone following it looked for the wrong file.

### Removed
- **The "Recently used apps" suggestions under a login's Android app ID (Android).** Filling that field now means typing the package name, or letting Android's save prompt create the entry with it already set. The list of apps you had tried to log into is no longer kept, and any existing one is deleted on first launch.

*Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.20] – 2026-08-11

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **The stored text-scale ceiling now matches what the app can show.** Renders always capped at 2x (phone) / 3x (tablet); the settings file could still hold up to 8.0 from an older design. A hand-edited value above 3.0 now loads as 3.0.

### Fixed
- **Three failure messages could be cut off at the largest text size.** When enabling biometric unlock, exporting a file, or restoring a synced-over value failed, the explanation appeared in a bottom strip that cut long text off with no way to read the rest. All three now open a dialog that scrolls, so the full reason — including the file path involved — is always readable.

*Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.19] – 2026-08-10

### Fixed
- **A link that would not open said nothing, or said the wrong thing.** Opening a URL from an entry gave no message at all when it failed, and at the largest text sizes the message shown elsewhere ran off the bottom of the screen. Both now appear in a dialog that scrolls, and a link that is not a web page says so instead of reporting a failure.
- **An entry in the vault list at the autofill prompt did nothing (Android).** When Gabbro asked for your passphrase to fill or save a login, the list of vaults also offered "Open a vault file…" — tapping it opened nothing and said nothing. It is no longer offered there, and where you have a single vault the list itself is gone, since it could only reselect the vault you were already unlocking. The app's own unlock screen is unchanged.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Links open through Gabbro's own code**, not the `url_launcher` plugin: the desktop's handler on Linux, Android's own on Android. Same system browser as before, never an in-app view, one less third-party dependency. Only `http` and `https` links are opened now — a stored `file://`, `ftp://` or `ssh://` address is refused, since this button means "open a web page".
- **File dialogs now talk to the system directly on both platforms**, instead of going through the `file_picker` plugin: the desktop's file portal on Linux, Android's own picker on Android. Same dialogs, two fewer third-party dependencies in the app.
- **The app now finds its own data folder** instead of asking the `path_provider` plugin — the same folder as before on both platforms, so nothing moves. This also removes the `jni` plugin whose C code newer compilers reject, which had broken fresh Linux builds.
- **Finnish and Russian passphrases draw on new wordlists**, re-sourced for GPL-3.0 compatibility. Both are still 7,776 words, so entropy is unchanged.
- **Portuguese passphrases draw on a new wordlist**, also re-sourced for GPL-3.0 compatibility. It is 7,776 words and carries no accents, so a passphrase types on any keyboard. The generator now labels it Português (BR), which is what the Portuguese list has always been.
- **Passphrases no longer include non-words** — surnames in Slovak and Ukrainian, `Internet` in French. Slovak drops to 6,642 words; add one word to cover the lost entropy.
- **In a sync review, the two options no longer swap places between fields.** A changed password put your own value first, the field below it put the other device's value first, so the option under your thumb kept changing meaning. The other device's value is now always listed first and pre-selected, for every kind of change — including entries and fields it deleted. Stepping through a review without changing anything now does exactly what Merge automatically does. Any choice you make yourself is still honoured, and Cancel still abandons the whole sync.
- **The sync dialog now says what "Merge automatically" does.** It offered the choice without explaining it, so it went unused. It now states that the automatic merge takes the other device's value wherever the two differ, and that reviewing starts from those same answers. The two choices carry the same wording for a screen reader, which on Linux reads only a control's name and never the paragraph.
- **The folder choice no longer says "unfoldered".** In English only, the option to leave an entry out of a folder read "Keep unfoldered" / "Move to unfoldered". It now reads "Keep without folder" / "Move to no folder" — what every other language already said.
- **The About screen did not name everything Gabbro ships.** Four Rust libraries were missing from the open-source list, one licence was wrong, and one entry named a Rust package while showing a different project's licence. Mozilla's Public Suffix List and two wordlist sources were uncredited. All are listed now, and a test refuses any direct dependency added without attribution.
- **The Android app ships two fewer bundled libraries.** Apache Tika and Commons IO came in with the old file-picker and are out of the release build, so the download is smaller and there is less third-party code inside it. No change to how picking a file behaves.

*Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.18] – 2026-08-05

### Fixed
- **Dialogs cut their question short, then put their buttons off the screen.** A dialog gives its buttons a fixed strip and lets the message shrink into whatever is left. On a phone at double text size the message was quietly truncated; at four times it vanished altogether and both buttons sat below the bottom of the screen, so a confirmation could be neither read nor answered. Every dialog now scrolls as a whole, unchanged at normal text size.
- **The vault list showed no entries at all at the largest text sizes.** On a narrow phone the search box grew with its placeholder until it had taken the whole screen, and the A-Z bar drew itself into a space too small to hold it. The placeholder now stays on one line and the A-Z bar steps aside when it cannot fit, so the entries keep their room.
- **Three messages appeared in English whatever your language.** The two file-dialog warnings and the notice that changing your passphrase turned biometric unlock off were never translated, so they arrived in English — at the moment something had just failed or a security setting had changed under you. All three are now translated into every language, and a test refuses any string that ships as English everywhere.
- **Serbian (Cyrillic) was almost entirely written in Latin script.** Choosing Српски gave you the same Latin text as Српски (latinica) — only 85 of 645 strings were actually Cyrillic. All of them are now, so the two Serbian options finally differ. A test refuses any Cyrillic locale that ships Latin-script prose, so this cannot come back.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Starting a vault switch and changing your mind is now one tap.** Picking another vault in Manage vaults opens its unlock screen over the vault you already had open; a Cancel button in the top-left goes back to it. That corner offered Quit before, which was never the action you wanted there — Quit stays in the vault menu, on `Ctrl+Q`, and on the first-run and locked screens.

### Security
- **A vault unlocked through Android autofill never locked itself again (Android).** The auto-lock timeout applied only to the app itself: unlocking at an autofill prompt opened the vault with nothing left running to close it, so it stayed open until Android reclaimed the process — and while it was open, any login field on any app or site was filled without asking. A vault opened by autofill is now locked again as soon as that fill or save finishes. A vault you already had open in the app is untouched, and its own auto-lock still governs it.
- **A copied password stayed on the clipboard for good if you left the entry screen.** The clear timeout only ever ran while that screen stayed open — pressing back, locking or switching vaults cancelled it silently, so the wipe you configured never happened. It now runs to completion wherever you go. An automatic lock (you walked away) wipes it immediately; a lock you ask for yourself leaves it alone, so you can still paste what you just copied. `never` still means never.
- **The vault registry no longer records which vaults need a YubiKey.** `vaults.jsonc` is plain text, so on a shared computer it showed anyone with file access which vaults were passphrase-only. Nothing in the app ever used the value; the line disappears from the file the next time you unlock a vault.
- **A failed auto-type could print one character of a password to the terminal (Linux).** When the X server rejected a keystroke, Gabbro printed the whole error, including the value the server objected to — which for that request came from the password. The message now names the failure and the request that failed, never the value.

*Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.17] – 2026-08-03

### Added
- **Open an exported vault as a vault — no more create-then-import on a second device.** Onboarding and the unlock screen's vault list now offer "Open an existing vault file": pick (or type the path of) a `.gabbro` export, name it, and it appears as a vault of its own, locked until its usual credentials open it. On Android the file is copied into the app's storage; on Linux it is used where it is. A file that is already registered, not a vault, or too old/new for this build is refused with the reason.
- **Sync from file no longer asks for a passphrase when your own opens the file.** The passphrase the vault was unlocked with is tried first; typing returns only when it does not open the file. A key-protected file asks only for its PIN and a tap of the incoming vault's YubiKey — a typed passphrase returns on fallback, without a second tap. Because a matching passphrase cannot prove the file is the same vault, the apply-choice dialog now says so.
- **Desktop keyboard shortcuts (Linux).** `Ctrl+L` locks the vault, `Ctrl+Q` locks and quits (asking first, the same confirm as the menu item), `Ctrl+F` focuses search (`Ctrl+Shift+F` searches all fields), `Ctrl+N` starts a new entry, `Ctrl+M` opens the menu, and `Esc` dismisses dialogs — including a safe cancel (rollback) of the sync review and import-failures flows. A **Keyboard shortcuts** item in the vault menu opens an in-app reference screen (desktop-only; localized across all 37 languages). No copy shortcut by design — copying a secret stays a deliberate, auto-clearing action.

- **Keyboard navigation (Linux).** `Tab` / `Shift+Tab` move between a screen's regions — search, folders, filters, entry list, details — and the arrow keys move within the focused one. `Enter` or `Space` activates, `Esc` steps back out. The focused region is outlined, so it is always visible where the keyboard is.
- **Screen-reader support (Linux, all 37 languages).** Every control now says what it is and what it does — the search box, category chips, folder selector and entry rows, and every icon-only button across the app, all of which a reader previously announced as just "button". Each region is named, and the lock-and-quit confirm reads its question.
- **Actions that change nothing visible are now spoken (Linux).** Copying a secret says so, in the generator and the entry detail pane, including when the clipboard will clear; ticking an entry says how many are selected; deleting the open entry says what replaced it; and `Ctrl+Shift+F`, `Ctrl+M`, `Ctrl+Q` and the new-entry sheet announce themselves.

### Removed
- **The navigation rail on wide windows.** Its Appearance, Security and About destinations are all in the app-bar menu, which is the single route to them now; its "Vault" destination did nothing. The list pane can be dragged wider than before, since the width the rail reserved is free.

### Fixed
- **Switching to another vault left the previous vault's entries one keypress away.** After unlocking a second vault from Manage vaults, pressing Esc went back to the first vault's entry list, which was still on screen with its contents readable, and left the keyboard shortcuts dead there. The vault you switch away from is now closed and its screen removed the moment the new one opens. Cancelling the switch before unlocking still returns you to the vault you had open, as before.
- **A vault file replaced outside the app left fingerprint unlock failing forever (Android).** The phone still held the old vault's passphrase, and every attempt blamed "check your passphrase". A rejected fingerprint passphrase now turns biometric unlock off and says the file changed; a wrong YubiKey PIN never does.
- **One mis-picked file in a restore could destroy the vault it replaced.** Restoring from a backup file now asks before anything is written, naming the vault it will replace, and keeps the old vault beside it as a `.pre-restore` file — so even a confirmed mistake can be undone.
- **After restoring a vault from a file, its safety copy still held the old vault.** Restoring from that safety copy afterwards would have brought the previous vault back. The safety copy is now refreshed to match the vault you restored.
- **After restoring a vault from a file, fingerprint unlock could stop working with no explanation (Android).** The phone still held the passphrase of the vault that was replaced, so the fingerprint handed over the wrong one. Restoring now turns fingerprint unlock off and says so, the same as changing your passphrase does.
- **At the largest text size there was no way out of the "How should this sync apply?" dialog.** Cancel sat in the dialog's button row, which does not scroll, so it was pushed off the bottom of a phone screen; the dialog also ran over the edge in 32 of the 37 languages. All three choices now scroll with the rest of the dialog.
- **Creating a vault could overwrite an existing one.** Pointing "Create vault" at a `.gabbro` file that already exists — what you try when you mean to open your vault on a second device — sealed an empty vault over it. Creating now refuses an occupied path; export, restore and saving are unchanged.
- **On a wide window at large text the vault list ran off the bottom of the screen.** The search box and filter chips grew to fill the height and the entry list was left with no room; the last entries could not be reached. The search box and chips now scroll within the top part of the pane, so the list always keeps its share.
- **The two icons in the search box ignored the text size.** The search-mode toggle (by title / all fields) and the clear button stayed at their default size while every other icon on the screen grew.
- **The new-entry type picker said each entry type twice** to a screen reader.
- **The folder selector was a 28dp tap target on a wide window** — the 48dp minimum was applied to the narrow layout only.
- **On a wide window a deleted entry could stay in the list** until the window was refocused.
- **The APK fingerprint in the README could not be pasted into AppVerifier** — the `Package:` and `SHA-256:` labels were rejected; it now shows the two bare lines AppVerifier expects.

*Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.16] – 2026-07-22

### Added
- **Native Linux packages.** Arch via the AUR (`yay -S gabbro-bin`) and Debian/Mint via a signed `.deb` (`sudo apt install ./gabbro_<version>_amd64.deb`) — both install system-wide with a menu entry and a `gabbro` command, resolve their dependencies, and uninstall cleanly. The `.deb` carries a detached GPG signature like the tarball.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **The Linux tarball no longer bundles `install.sh`.** The native packages replace it; the tarball is now extract-and-run (use the AUR or `.deb` for app-menu / PATH integration).
- **Release binaries no longer embed the build machine's file paths** — build-path hygiene, no behaviour change.

*Built with Flutter 3.44.6, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

## [0.1.0-alpha.15] – 2026-07-21

### Security
- **VERSION 11 is now the minimum vault format.** The X25519 + ML-KEM hybrid layer removed as non-load-bearing at alpha.14 (ADR-018) is now deleted outright, along with the `ml-kem` and `x25519-dalek` crates — 11 fewer dependencies. Quantum resistance is unchanged (Argon2id + AES-256-GCM).

### Added
- **In-app Quit (Linux).** A power-icon button on the locked and first-run screens exits immediately; a **Quit** item in the vault menu confirms ("Lock and quit Gabbro?"), then locks the vault (wiping keys) and exits. For tiling-WM users with no title-bar close. Localized across all 37 languages; Linux-only (Android has system navigation).
- **Linux release ships an installer.** `install.sh` (in the tarball) registers Gabbro with the desktop: a `.desktop` launcher entry plus a `gabbro` command on your PATH, so it appears in the app menu (Mint) or runs by name (tiling WMs) instead of being launched from the extract folder. Per-user by default (no root); `--system` and `--uninstall` supported. Ships a placeholder icon until the final logo lands.
- **Linux auto-type now works from a release download.** The `gabbro-autotype` trigger client ships in the tarball, so binding a keyboard shortcut no longer requires building from source. Setup for auto-type (Linux) and autofill (Android): [docs/AUTOTYPE_AND_AUTOFILL.md](docs/AUTOTYPE_AND_AUTOFILL.md).

### Fixed
- Linux auto-type no longer mistypes logins and passwords (e.g. `abc.f` typed as `abc..`), especially under load. Each character is now injected on its own keycode instead of one keycode remapped between every keystroke, which let the target app read a stale key and duplicate the previous character while dropping the next.
- High contrast is now genuinely high-contrast on every screen: the alphabet index bar (absent letters, gap marker, greyed chevrons), the sync-review changed-field rows, and the password breakdown no longer render dimmed or low-contrast text. The alphabet-bar gap marker is also no longer announced by screen readers.
- Recovery history: the Revert, Delete and reveal controls ran off the right edge at larger text in most languages, leaving no way to restore or discard a value sync had replaced. They now wrap onto their own line.
- Sync review: a long password, URL or folder name was cut off in the choice buttons, so you picked between two values you could not read. Value choices are now full-width rows that wrap onto as many lines as needed, at every text size.
- Tablet, largest text: the "select an entry" placeholder in the detail pane ran off the bottom of the pane. It now scrolls.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **A vault older than VERSION 11 is refused, not damaged.** The file is left untouched and the app explains it needs upgrading rather than reporting corruption. To upgrade: install alpha.14, open each vault once, then return. See [docs/VAULT_UPGRADE_PATH.md](docs/VAULT_UPGRADE_PATH.md).
- Importing a too-old vault now explains it in your own language with a tappable link to the upgrade steps, instead of showing an untranslated error. Matches the unlock screen.
- A vault written by a newer Gabbro build is now explained in your own language ("update Gabbro") with a tappable link, on both unlock and import, instead of an untranslated error citing a meaningless format number. Fail-closed behaviour unchanged.
- Every error a user can trigger — import, export, folder actions, vault load, sync, entry save, passphrase change, recovery history, onboarding, biometric enrolment, backup restore, YubiKey loading — is now shown in your own language, with the technical detail appended for bug reports, instead of an untranslated English error.

_Built with Flutter 3.44.6, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21._

## [0.1.0-alpha.14] – 2026-07-11

### Security
- **Vault format VERSION 11.** New vaults derive the encryption key straight from Argon2id (via HKDF); existing vaults auto-upgrade the first time you unlock them (entries unchanged). Removes the non-load-bearing X25519 + ML-KEM hybrid layer (ADR-018); quantum resistance is unchanged (Argon2id + AES-256-GCM).

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- Project repository moved to the `gabbro-foss` GitHub organisation; in-app GitHub/Issues links updated (old links redirect).
- App tagline is now "A quantum-resistant password manager" (all locales). Docs clarified: quantum resistance comes from Argon2id + AES-256-GCM, not the hybrid X25519 + ML-KEM layer (ADR-018).

## [0.1.0-alpha.13] – 2026-07-08

### Security
- **Vault format VERSION 10.** Existing vaults auto-upgrade the first time you unlock them (no action needed, entries unchanged). Hardens how one internal key is derived, removing a latent risk that a future library update could have left old vaults unopenable.
- Crack-me challenge refreshed to a new vault (current vault format). Challenge parameters (passphrase, proof string, key configuration) are deliberately undocumented — see `challenge/README.md`. Superseded challenge vaults were retired.

## [0.1.0-alpha.12] – 2026-07-06

### Added
- **Linux desktop auto-type (X11).** With a login open in Gabbro, a global hotkey types `username⇥password↵` into the focused window; uses the login's email when it has no username.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Smaller, per-device Android downloads.** Releases now ship a separate APK per phone type (modern `arm64-v8a` ~29 MB, old 32-bit `armeabi-v7a`, emulator/Chromebook `x86_64`) instead of one ~76 MB file bundling all three. Download the one for your device — use `arm64-v8a` if unsure. All are signed by the same key (same fingerprint).

### Fixed
- Biometric unlock is now per vault. Enabling it on one vault no longer clears it from another — previously all vaults shared a single key and slot, so enrolling a second vault silently disabled the first. Each vault keeps its own biometric independently on each device, and it survives syncing a vault to another device and back. Hardware-verified on Android.
- Generator copy now honours the clipboard-clear setting like entry copy: "never" no longer clears at all (was cleared after 24h), and re-copying resets the clear timer so a freshly copied password isn't wiped early.
- Tablet two-pane: the detail pane reserves bottom space so its last item is no longer hidden behind the add-entry button.
- Tablet two-pane: the column-resize handle now has a screen-reader label ("Resize columns") and its grip grows with the text size.

## [0.1.0-alpha.11] – 2026-07-04

### Added
- **Large-text accessibility — continuous text-size slider (phase 1).** An absolute text scale capped to your screen (up to 2x on phones, 3x on tablets) set by a zoom-glyph-bracketed slider with live preview, replacing the five fixed sizes. Onboarding's accessibility button reveals the slider inline (hiding the logo for room) and jumps to a strong scale. Old saved text sizes migrate automatically.
- **Help screens can be pinch-zoomed.** Tap any help screenshot to open it full-screen and pinch to zoom / drag to pan — the images are pictures that the text-size setting can't enlarge, and screenshots are blocked in-app, so this is the way to read small detail.
- **Buttons and controls grow with the text size too.** At large text, the menu, entry-row, type-picker and navigation-rail icons, the add button, page arrows, app-bar buttons, selection checkboxes and the password show/hide (eye) toggles scale up (so they stay easy to see and tap), touch targets are a full size, and the A–Z index bar's letters enlarge without spilling off their strip. Eye toggles that sit inside a text field grow a little more gently so they stay within the field.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Sync now offers "Merge automatically" or "Review all changes".** When syncing from a file you pick how to apply it: *Merge automatically* takes all incoming changes with no prompts (the incoming vault wins any clash; the replaced value is kept in history), or *Review all changes* steps through them one by one as before. Nothing is lost either way.
- **Entry history unified into one place (part of v9).** An entry's past values now live in a single history — one previous value per field, shown under one "History" button — instead of a separate single-slot "Password history" plus a growing "Previous state" list. Old vaults migrate losslessly on load; secret fields still auto-expire per your retention setting.
- **Vault sync is now field-level (format v8 → v9).** Editing different fields — or different custom key/value pairs — of the same entry on two devices now keeps both, instead of the newer whole entry overwriting the other. A genuine clash (same field changed to different values) and an item another device deleted are surfaced for you to resolve (keep mine / use theirs; keep / delete) — never silent loss. Fixes the false "nothing to sync". Cryptography is unchanged from v8; an older Gabbro refuses a v9 vault rather than opening it and silently dropping the new per-field data. Backed by a deterministic multi-device sync fuzz proof.

### Fixed
- Password breakdown is easier to find and clearer: a tappable breakdown icon now appears next to a revealed generated or login password (long-press still works), and the legend lists only the character types actually present (no stray CJK example on a Latin-only password).
- The About screen now shows the **real app version**, injected from `pubspec.yaml` at build time (no more hand-maintained, drifting string; no new dependency). The plaintext JSON export drops its wrong, hard-coded `gabbro_version` field.
- **Enter now submits (or advances) in every passphrase and PIN field** — unlock, onboarding, change-passphrase, import, sync-from-file, biometric enrollment and vault-delete authorization. In multi-field flows Enter moves to the next field and submits from the last; a YubiKey vault advances passphrase → PIN before submitting. Previously Enter did nothing in most of these fields. Also fixes a latent crash when confirming the biometric-enrollment passphrase dialog.
- Biometric unlock now works on wide screens (the tablet two-pane layout). Enabling it there previously did nothing — the toggle wouldn't stick and no biometric button appeared at unlock — because the Security screen wasn't told which vault it was for, so enrollment keyed against an empty path. Phone-width layouts were unaffected. Hardware-verified on an Android 16 tablet.
- The post-sync "Vault synced…" bar no longer lingers on the unlock screen after locking (and its **Details** button can no longer crash the app when tapped there). The bar now carries a close (X) button so it can be dismissed — an actioned snackbar never times out on its own — with the close and Details controls labelled for screen readers.
- Custom entry fields now show in a stable, consistent order (the order they were created) across devices and app restarts. They were stored in an unordered map, so two instances viewing the same vault could list the same fields differently.
- **Large-text layout hardening (accessibility, part of ADR-016).** At the largest text sizes, dropdowns no longer clip their selected value or menu items, dialogs scroll so their buttons stay reachable, and the help, language, generator and CSV-import screens no longer overflow, and the vault menu's items (Manage YubiKeys, Appearance, Language, Security, Help, About) no longer clip off the edge. The biometric-unlock button becomes a larger icon (its label wrapped over several lines), the CSV preview's header row grows with the text, and the sync review / "how to apply" / "stop reviewing" dialogs scroll as a whole. In the review, at large text the keep/replace choices become full-width rows whose value is wrapping text (a chip is single-line and clipped long values like passwords, so they couldn't be read or compared). Maximum text size is 2x on phones / 3x on tablets.

## [0.1.0-alpha.10] – 2026-06-26

### Security
- **Android release dependencies locked + supply-chain scanned.** The release runtime dependency graph is pinned in `android/app/gradle.lockfile` (reproducible builds) and scanned with `osv-scanner` — 0 known vulnerabilities. Closes the one open supply-chain gap from audit pass 3 (Gradle deps were not previously lockfile-scannable).
- **Import hardening (audit pass 3).** Import parsers now cap file size (25 MB text formats, 128 MB Enpass — announced on the import screen), bound Enpass attachment decoding, and no longer crash on a crafted Enpass expiry. A new fuzzer covers all five parsers.
- **Defence-in-depth.** Export writes can't be redirected via a symlinked temp file; the autofill summary list uses a real JSON encoder; plaintext import/export/autofill buffers are zeroized after use; native-app autofill matches the OS-attested package, not the window title.

### Added
- The alphabet index bar is now script-aware and follows the UI locale: Latin, Greek (accents folded), Cyrillic (Russian/Ukrainian/Bulgarian/Kazakh, each its own alphabet) and Korean (by leading consonant) get their script's letters instead of everything collapsing under "#". Japanese and Chinese have no human-orderable index, so those locales drop the bar for a plain title-sorted list (scrollbar on desktop, flick-scroll on mobile). Bar slots and chevrons now carry screen-reader labels, and the scroll chevrons show their label as a desktop hover tooltip. Non-Latin alphabets are best-effort and unreviewed by native speakers.
- Accessibility: the show/hide eye toggles (passphrase, PIN, password, CVV) across 12 screens now carry screen-reader labels, alongside the browse, folder add/edit/delete, vault-list add/delete/close and Help prev/next buttons — they previously announced a bare "button". Enforced per screen by `labeledTapTargetGuideline`. A sweep of every chevron control gave the remaining bare scroll chevrons — the entry-type filter row and the password-breakdown sheet (left/right) — screen-reader labels and a desktop hover tooltip too (the help-screen page chevrons already had them). Vault-list selection checkboxes now announce the entry title instead of a bare "tick box", and the search clear button has a "Clear search" tooltip (new string, all 37 locales).
- YubiKey onboarding now allows a different transport per key (Android): a USB-only key and an NFC-only key can be enrolled together, instead of forcing both onto one transport.

### Fixed
- The USB/NFC transport selector is now hidden on Android devices without NFC hardware (it previously appeared everywhere, e.g. on non-NFC tablets, where picking NFC could only fail) — across onboarding, unlock, change-passphrase, manage-vaults, manage-keys, import and sync.
- Sync-from-file with a YubiKey-protected source now shows the "Tap your YubiKey now…" note (under the PIN field, mirroring import) while the tap is awaited, and surfaces a failed tap inline instead of silently waiting on a bare spinner. Linux + Android hardware-verified.
- Full-text search ("search all fields") now matches field *values*, not field labels. Entries imported from Enpass carry empty typed fields (Email, Phone, ...) whose labels made every such entry falsely match a search for "email"/"phone"; that no longer happens, while a word in free-text notes still matches.
- Managing folders no longer throws an unhandled exception when a rename, add, or delete fails (e.g. a name that already exists) — the error is shown in a SnackBar. Renaming a folder to its unchanged name is now a no-op instead of an error.
- Autofill: when the vault unlocks but no saved login matches the site/app, it now shows the localized "no credentials found" dialog instead of a false "could not unlock — wrong credentials" error.
- Biometric unlock no longer silently fails after a passphrase change: changing the passphrase now turns biometric off (its stored secret was tied to the old passphrase) and tells you to re-enable it in Settings.
- Changing the passphrase now accepts a "Fair" passphrase, matching onboarding (it previously required a stronger one); weaker passphrases show an explicit "too weak" line.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- Android autofill now fills fields through the current `setField` API on Android 14+, keeping the deprecated `setValue` path for Android 8–13 — so Gabbro keeps building cleanly against newer Android SDKs with no change to how autofill behaves. Hardware-verified on Android 16 (web + native app, locked + unlocked vault).

### Removed
- Dead-code audit cleanup: unused Rust FFI (`EntryType`, demo `greet`, the redundant typed `create_*_entry` constructors superseded by the generic `createEntry`, `get_entry_by_id`, `delete_vault_backup`, legacy single-key `init_vault_with_yubikey`), the unreachable Kotlin `register_and_get_hmac` path, a dangling `AutofillSettingsActivity` manifest/config reference (an exported activity declared for a non-existent class), and 5 unreferenced logo PNGs. No behaviour change; bridge regenerated and test coverage preserved.

## [0.1.0-alpha.9] – 2026-06-22

### Security
- **Passphrase-only vault key is now transcript-bound (vault format VERSION 8, audit F-03).** The passphrase-only combiner folds the KEM transcript (ML-KEM ciphertext + both X25519 public keys) into the HKDF, binding the key to the transcript inside the derivation rather than only via the AES-GCM AAD — defence-in-depth, not a fix for a known attack (post-quantum security at rest still comes from AES-256-GCM + Argon2id, untouched). YubiKey vaults are intentionally unchanged; v6/v7 vaults open unchanged and migrate to v8 on next save, proven by the backward-compat gate + state-machine fuzzer and hardware-verified on Linux and Android.
- **Linux release tarballs are now OpenPGP-signed.** Each release ships a detached signature (`.tar.gz.asc`) so testers can verify the build is authentic, the same way the Android APK signature is checked. README documents the signing-key fingerprint, the inline public key, and the `gpg --verify` steps.

## [0.1.0-alpha.8] – 2026-06-18

### Security
- **Autofill matching unified into one shared matcher (audit F-10 follow-up).** The locked-vault `UnlockActivity` and the unlocked-path service now share `matchingCredentials` (PSL eTLD+1 for web, exact `app_id` for native; match on password-free summaries, decrypt only the chosen entry), replacing `UnlockActivity`'s drifted naive eTLD+1 (F-10) and loose substring matcher. Both paths are now device-verified — the locked-vault unlock flow is built (see Added).
- **Autofill website matching now uses the Public Suffix List (audit finding F-10).** The old eTLD+1 took a host's last two labels, collapsing every `*.co.uk` site to `co.uk` so unrelated entries cross-matched and the *wrong* credential could be offered. A vendored `public_suffix_list.dat` (publicsuffix.org) now computes the real registrable domain — `bbc.co.uk` and `hsbc.co.uk` no longer collide; bare public suffixes match nothing. List is vendored, never fetched at build/run; refresh procedure in `docs/MAINTENANCE.md`. Covered by a pure-JVM matcher test (normal/wildcard/exception rules) and end-to-end Robolectric tests against the real list. Hardware-verified on Android: no false-positives, correct credential when the form's fields are detected (field detection on non-standard/SPA pages is tracked separately).
- **Removed the `show_vault_list` login-screen privacy toggle (ADR-014).** It promised to hide the *existence* of other vaults under duress, but the vault registry (`vaults.jsonc`) is plaintext — so the toggle only hid vaults from someone who merely opened the app, not the adversary it targeted; a half-strength privacy feature is worse than none. The login screen now always lists registered vaults, and the active vault can be deleted even with siblings (routing to the remaining last-used vault, or onboarding when none remain). The deletion *authorization* gates (confirm checkbox + mandatory YubiKey tap) are unchanged, and old configs carrying `show_vault_list` are ignored. Flutter unit/widget tests cover the unblocked delete, the pure post-delete routing decision, and old-settings backward-compat. Awaiting a Linux hardware pass.
- **Linux core-dump hardening (audit finding R-04).** At startup the process disables core dumps (`RLIMIT_CORE=0`, permanent) and `ptrace`/`/proc/<pid>/mem` snooping (`PR_SET_DUMPABLE(0)`), so an unlocked vault's in-RAM secrets can't leak via a crash dump or another same-uid process. Because a non-dumpable process also blocks `xdg-desktop-portal` from reading its `/proc` to open a native file dialog, `PR_SET_DUMPABLE` is **raised only for the brief window a file dialog is open** (ref-counted in `runPicker`) then lowered again — yama `ptrace_scope` (≥1 on Debian/Mint and Arch defaults) covers that window, and `RLIMIT_CORE=0` is never relaxed. Linux-only; no-op elsewhere. A fork-based unit test reproduces the portal-`/proc` access rule as a regression guard.

### Added
- **Autofill can now save new and changed logins (Android).** When you submit a login the vault lacks (or a changed password), the OS offers to save it to Gabbro: it unlocks if needed, then a confirm screen lets you create a new entry, update the matched one, pick a different existing login, or cancel — never a silent overwrite; password history is kept per your retention setting. Localized across 37 locales (`eu`/`kk`/`yo` best-effort). Hardware-verified on Android (Brave).
- **Autofill now unlocks a locked vault.** Triggering autofill while Gabbro is locked opens the full unlock screen — vault picker, passphrase, YubiKey (USB **and** NFC), biometric — reusing the main app's `UnlockScreen`; on unlock it fills the matched credential (or shows a "no credentials" dialog). The autofill activity and the main app now share one unlock host (`GabbroUnlockHostActivity`) for the YubiKey/biometric channels and YubiKey NFC OTP suppression, so an NFC tap no longer escapes to the browser. Built net-first (regression-pinned `UnlockScreen` behaviour/appearance/a11y) with a testable `TapFlow` state machine. Hardware-verified on Android: USB+NFC + biometric unlock, vault picker, no-match dialog, and a clean main-app unlock/export regression.
- **Login entries gain an optional email field, and username is now optional.** A Login now holds both `username` and `email` (only title + password are required). Autofill routes the email to email-typed fields and the username to username-typed fields, each falling back to the other when only one is set — so a form that asks for an email gets the email, not the username. Old vaults load unchanged (no format bump); shown in the editor (reusing "Email (optional)", username relabelled "Username (optional)" across 37 locales), detail, and review-diff. Device-verified on Android.
- **Autofill: match a vault login to an installed Android app by its package id.** Login entries gain an optional "Android app ID" field; a native app autofills only on an **exact** package match (no loose substring matching — an unset id matches nothing, so no false positives). Apps that request autofill but match no entry are recorded (app-private, capped) and offered as tap-to-fill suggestion chips in the editor, so you needn't hunt for the package name. Field, note, and chips localised across 37 locales. Device-verified on Android (match, no-false-positive, capture); replaces the old loose `extractAppToken` matcher.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Autofill: web login fields detected from HTML attributes.** `classifyField` now reads the html `id` (catching short field names) and trusts html `name`/`id` only on real form controls, so `<form name="login">` containers are no longer mis-detected. Hardware-verified on Android across six sites; OTP/reCAPTCHA correctly skipped.
- **Password generator: classic minimum length lowered from 32 to 12 characters.** The length slider now bottoms out at 12 (default stays 32, max 256) and Rust's `MIN_LENGTH` matches. The "Passwords are at least N characters" note updates to 12 across all 37 locales (a numeric-only edit, no translation change) and is now shown **only in classic mode** — it was meaningless in passphrase (word-based) mode, so it is hidden there. Generator widget + Rust unit tests cover the new lower bound and the note's mode-gating. Hardware-verified on Linux and Android.
- **Password generator: "Capitalise words" is disabled for caseless CJK passphrase languages.** Japanese, Korean, and Chinese (Simplified/Traditional) scripts have no letter case, so the option (Rust's `to_uppercase()` is a no-op there) is now shown off and disabled whenever the selected passphrase language is CJK, derived from the language rather than mutating stored state. Widget tests pin the disabled state and that CJK generation never requests capitalisation. Hardware-verified on Linux and Android.
- **Onboarding: a "Fair" passphrase can now create a vault, and a too-weak one explains itself.** The strength gate dropped from Strong to Fair-and-above: a Fair passphrase enables the Create button while its "Fair" strength label stays visible as the warning. A Weak/Terrible passphrase keeps the button disabled **and** now shows an explicit "Passphrase is too weak" line under the strength meter, instead of a silently greyed-out button with no explanation. Widget tests cover each tier. Hardware-verified on Linux and Android.
- **Vault deletion is confirmed with a checkbox, not by typing `DELETE`.** The typed English word excluded non-Latin keyboards (and a typed name/translated word would break on Unicode normalization); the "I understand…" checkbox is reliable in every script. Widget-tested.

### Fixed
- **The autofill "No credentials found" message is now localized** — it was hardcoded English; it is now a Flutter dialog shown across 37 locales.
- **The autofill suggestion chip ("Unlock Gabbro to autofill") is now localized** — it was hardcoded English. It's a RemoteViews chip drawn by the OS with no Flutter engine, so it can't read the Flutter ARBs; localized instead via `res/values-XX/` strings across all 37 locales (`eu`/`kk`/`yo` best-effort). Resolved by the **device** locale, not Gabbro's in-app language override (RemoteViews limitation). A Robolectric test guards every locale resolves a non-blank label. Hardware-verified on Android (device set to a non-English locale shows the translated chip).
- **Vault list no longer overflows ("BOTTOM OVERFLOWED") when the search keyboard opens.** The screen kept full height under the keyboard (`resizeToAvoidBottomInset: false`) so the fixed search/filter header no longer exceeds the shrunk body; the scrollable list simply extends under the keyboard, search stays visible on top. Guarded by a phone/tablet overflow-test matrix (alphabet bar left/right, FAB, portrait/landscape, dragged list-pane width), each with the keyboard open.
- **User-facing strings that were hardcoded in English are now localized across all 37 locales.** The vault-delete confirmation, the YubiKey "no device found" errors on Linux (which had overridden the existing translation), and the CSV-mapping / file-pick / unlock / YubiKey-operation fallbacks. Best-effort translations; community refinement welcome.

## [0.1.0-alpha.7] – 2026-06-13

### Security
- **Automatic on-device safety copy of the vault, plus an honest corruption-recovery flow (audit finding R-03).** Every save keeps a `.bak` sibling equal to the *last verified save*: `write_vault` rotates the previous file to `.bak`, writes the main file atomically, **reads it back and parse-verifies it**, then syncs `.bak` to the verified bytes. A save that does not read back as a valid vault leaves `.bak` at the last good state and returns a loud error — the 2026-06-08 brick class now fails at the bad save instead of silently propagating into the safety copy. It is a single `.bak` on the same disk: corruption insurance, **not** a backup (user-driven `.gabbro` export to shared storage remains the supported real backup). On unlock, an unreadable vault is detected by a parse probe (at screen mount, and re-probed on any unlock failure and on app resume — so corruption surfaces without a vault-switch dance, while wrong passphrase/PIN/key never trigger it). The misleading passphrase prompt is then replaced by a recovery card: if a *usable* `.bak` exists (it is parse-checked, so the offer can never advertise a copy that a restore would refuse) you restore from it — and the restore returns the last verified save, including the most recent edit, which the first attempt lost; otherwise the vault is unrecoverable on this device and you can **restore from your own off-device backup file** (file picker → the file is validated as a real vault → written over the corrupt one → it opens with your credentials), or remove/delete it. Platform-aware: desktop offers "Remove from list" (keeps the file on disk) and "Delete file"; Android offers only "Delete file", because app-private storage makes a list-only removal an unreachable orphan. The first pass at this (Claude Fable 5) was component-green but failed the hardware matrix; it was diagnosed and reworked by Claude Opus 4.8 with Rob. Verified by Rust unit + bridge tests, a real-FFI integration suite (Linux), the full Flutter suite, `clippy --all-targets`, and new UI strings across all 37 locales; hardware-verified on Linux (full matrix) and on the Android emulator (both recovery states, restore-from-file via the storage picker, the platform-specific button set, and delete-file confirmed gone from app-private storage).
- **The vault no longer leaves the device via Android's backup framework (audit finding R-02).** The manifest never set `android:allowBackup`, which defaults to *true* — so on a standard consumer device, Android Auto Backup silently copied Gabbro's app-private storage (the vault file(s), `settings.jsonc`, and the alias-bearing `vaults.jsonc`) to the user's Google Drive, and device-to-device migration could carry it to a new phone. The vault is encrypted at rest, but this still handed a third party ciphertext for offline brute force, left stale vault copies in cloud backups after local deletion, and contradicted Gabbro's local-only promise. Backup is now refused at every layer the OS (and OEM transfer tools like Smart Switch) consult: `allowBackup="false"`, API 31+ `dataExtractionRules` (cloud backup **and** device-to-device, all storage domains excluded), and API ≤ 30 `fullBackupContent` — so the protection holds even if one mechanism is bypassed or its semantics change. User-driven export/backup of `.gabbro` files via the export flow to shared storage (e.g. for 3-2-1/NAS sync) is unaffected — that is, and remains, the supported way to back up a vault. Guarded by three new Robolectric tests that read the *merged* manifest, so a future plugin re-enabling backup through the manifest merger fails the suite; the built APK's merged manifest verified via `aapt dump xmltree`. Hardware-verified on Android: upgrade-in-place install, unlock, and autofill unaffected; `pkgFlags` carries no `ALLOW_BACKUP` and `bmgr backupnow` reports "Backup is not allowed".
- **Crash-on-open hardening: malformed `.gabbro` no longer panics the parser.** `SealedVault::from_bytes` reads an 8-byte body-length field straight off disk and then checked `data.len() < pos + body_len`. Because `body_len` is attacker-controlled and cast to `usize`, a crafted header with a near-`u64::MAX` body length overflowed the `pos + body_len` add — panicking on the add in debug, and in release wrapping to a small value so the guard passed and `data[pos..pos + body_len]` became a reversed range, panicking on the slice. Either way a hand-crafted or corrupt vault file crashed the app on open. Fixed with a `checked_add`: an overflowing body length now returns a clean `Err` like any other truncation. No change for valid vaults (backward-compat gate green). Found by a new negative/fuzz test, not in the wild. The parser was otherwise already well-defended (every slice length-guarded); this closes the one integer-overflow gap.
- Vault parser fuzz harness (`rust/tests/vault_parse_fuzz.rs`): the negative-input safety net for `SealedVault::from_bytes`, complementing the valid-only `vault_backward_compat` gate. Feeds the parser (1) every truncation of a real golden vault, (2) seeded-random garbage, and (3) structurally valid headers with oversized/overflowing body-length fields, asserting it always returns `Err`, never panics. Not `#[ignore]`'d — parsing does no Argon2id work, so it runs in the routine `cargo test` as a permanent guard. Caught the body-length overflow above.
- **Lock / vault-switch now clear the navigation back stack (locked-vault re-exposure hardening).** Auto-lock already wiped the back stack (`pushAndRemoveUntil`), but the manual lock button and the vault-switch dropdown used `pushReplacement`, which only swaps the top route. A hardware-found edge case (back-press during a stalled YubiKey tap after switching vaults) could leave a previously-unlocked vault's screen reachable underneath. Manual lock (`_lockAndExit`) and `switchToVault` now both `pushAndRemoveUntil((_) => false)` like auto-lock, so no prior route — and no previously-unlocked vault's screen — can survive a lock or a switch, regardless of stack depth or in-flight async state. Defence-in-depth: a failed/locked entry-list load now also clears any retained decrypted summaries from memory (the existing error gate already hid them from the UI). The originally-observed symptom was no longer reproducible after the stalled-tap fix; this closes the class by construction. Widget tests pin "lock/switch leaves nothing to pop back to" and "a locked load renders no entry-list chrome." Hardware-verified on Android.

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
- **Path fields are now editable — type or paste, not pick-only.** The vault-path field in onboarding (and the file-path fields in export/import) previously accepted only a value chosen through the native file dialog. They are now directly editable while still offering the picker — important when the native dialog is unavailable (e.g. under a Wayland bubblewrap sandbox), where typing/pasting a path is the only way in. A caller-requested read-only display mode is preserved, and an external path update (the onboarding alias-driven preview) still flows into the field. Widget tests cover typing, picking, external-update sync, and read-only mode.

### Fixed
- **Linux: launch no longer fails when the XDG data directory does not pre-exist (tolerant write path).** On a Debian/Wayland system whose `~/.local/share` did not exist, the app errored `file-not-found` at startup. `GabbroPaths` now wraps path_provider's resolution and falls back **only** when it cannot resolve at all (e.g. a sandbox with no `~/.local/share`, or no GTK app-id over FFI) to an XDG-computed path (`$XDG_DATA_HOME` or `$HOME/.local/share`, app-id `app.gabbro.gabbro`) that mirrors path_provider's own precedence — including its legacy executable-name directory — so **existing installs resolve to the exact same directory and nothing moves**. The normal path is unchanged: every working install still goes through path_provider. Config resolution gains the same tolerance (honours `XDG_CONFIG_HOME` only as a fallback when `HOME` is unset; otherwise unchanged at `~/.config/gabbro`). If no directory can be determined at all, onboarding no longer crashes — the vault-path field is left empty and editable so the user can type or paste a location. Hardware-verified on Linux (existing passphrase-only and passphrase+YubiKey vaults still open; type and pick both work) and Android (resolution is unchanged there by construction). Pure-resolution unit tests + widget tests. The separate bubblewrap *launch* env var some Wayland sandboxes need is unaffected by this and tracked separately.
- **Tablet/desktop detail pane no longer crashes when the selected entry vanishes.** `tablet_vault_layout` fetched the selected entry synchronously *during build* (`getEntry`); when that entry no longer existed — deleted, or a locked/corrupt session surfaced by any app-wide rebuild such as toggling a Security setting with an entry selected — the fetch threw inside layout and the app spammed `Another exception was thrown: Instance of 'DiagnosticsProperty<void>'`. The fetch is now guarded: it falls back to the empty "Select an entry" state and clears the stale selection after the frame. This also resolves the `DiagnosticsProperty<void>` storm seen when changing background-lock settings. Pinned by a red→green widget test. Found during R-03 hardware testing.
- **Stalled YubiKey tap no longer hangs the UI on an endless spinner (Android).** A tap (unlock or add-key) arms USB/NFC discovery and waits for a key; if none was ever presented, the platform call never completed and the spinner ran forever, recoverable only via the back arrow — and on NFC it left reader mode armed. The Android tap now has a bounded lifecycle: a 30-second timeout that stops discovery and surfaces a "no key detected" message, plus an explicit **Cancel** button (new on the unlock screen; the add-key dialog's existing Cancel now truly aborts the native tap instead of just hiding the dialog). Both paths run discovery teardown so NFC reader mode is disarmed. A user cancel clears the spinner with no error banner. Behaviour of a successful tap is unchanged. Hardware-verified on Android (USB + NFC: normal unlock single/multi-key, add-key, 30 s timeout, and Cancel). Internally the four near-identical Kotlin tap handlers (register / register+hmac / get-hmac / get-hmac-multi) were unified onto one `runTapFlow` helper that owns the timeout, cancel, and complete-once logic (the timeout/cancel now cover every tap flow, not a copy per method). 8 new Flutter tests at the channel-mock seam.

## [0.1.0-alpha.6] – 2026-06-10

### Security
- **Vault export no longer strips YubiKey protection (ADR-013).** Exporting a vault protected with passphrase + YubiKey(s) previously re-sealed the copy *passphrase-only*, so anyone who knew the passphrase could open or sync that exported file with no YubiKey — silently defeating the second factor the user had chosen. Export now preserves the source vault's protection by copying the sealed file byte-for-byte: a key-protected vault stays key-protected, and syncing from it requires the passphrase **and** a registered YubiKey. Passphrase-only vaults are unchanged. A deliberate, opt-in passphrase-only export (an explicit downgrade) remains available and never alters the original vault. The export screen shows each vault's protection and offers the opt-in downgrade toggle (default off). Both Gabbro→Gabbro front-ends now enforce the source's protection: *Import entries* and *Sync from file* each detect a key-protected source and prompt for a registered YubiKey (PIN, USB/NFC transport on Android, and a "tap your key now" cue) before merging. The *Sync from file* path was a same-day follow-up gap — it had stayed passphrase-only, so a key-protected source was correctly refused by the crypto but surfaced a misleading "different passphrase" error and could not sync at all; it now mirrors the import path (`merge_vault_from_file_with_key`), reusing the same strings and tap helper (DRY). Found by hardware test 2026-06-10 and verified on hardware: export and *Import entries* on Linux and Android (USB + NFC), and *Sync from file* on Android NFC (correct key syncs, wrong key refused). Rust core, bridge, and both UI halves landed with unit + widget tests.
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
- **Android export into a sync folder failed with "Failed to rename temp file: Operation not permitted (os error 1)"** when the destination `.gabbro` already existed (e.g. a file a NAS/sync client had placed there). Under Android scoped storage an app may create a new file in a shared folder but may not replace another app's file via a raw POSIX path, so the temp-file-then-rename write was rejected — and because the write never completed, the synced file silently went stale (rsync "saw no changes"). Android `.gabbro` export now writes through the Storage Access Framework (`androidx.documentfile`): Rust builds the export **ciphertext** + SHA-256 line (`build_export_bytes` / `build_export_passphrase_only_bytes`, sharing the byte builders with the Linux path-write), and Kotlin overwrites the file in place inside the directory tree the user grants via the folder picker — find-then-overwrite so a fixed-name sync target keeps its name (no SAF `Name (1).gabbro` dedup). **No new permission** is requested: the grant is scoped to the chosen folder, persisted so exports remember it (`android_export_folder_uri` setting), and revocable in Android Settings. Linux export is unchanged (raw-path, 0600, atomic). Plaintext JSON export is deliberately excluded (routing it would put plaintext secrets across the Flutter/Rust bridge); overwriting a non-owned JSON in shared storage still fails — a documented, low-impact limitation. Rust + settings + widget tests; hardware-verified on Android. See ADR-013.

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

### Fixed
- Android edge-to-edge (targetSdk 36): the vault list, its sync snackbar and four other screens no longer run under the navigation bar or a landscape side bar. A new inset net renders every screen with faked system bars on phone and tablet, portrait and landscape.

### Changed
- The import screen's Gabbro section now says a synced copy of this same vault belongs in Sync from vault, not import.
- Import is additive: every entry in the file is added, duplicates included. The "entries skipped" dialog is gone. A Gabbro import whose entry UUID the vault already holds gets a fresh UUID, so sync by UUID stays intact.
- Labels: the vault menu's "Sync from file" is now "Sync from vault"; the import screen's Gabbro button "Sync from vault" is now "Import" (it imports, it does not sync).
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
- Crack-me vault challenge published for public security testing: a real Gabbro vault in `challenge/`. Rules, submission, and reward are in `challenge/README.md`; challenge parameters are intentionally not documented here.
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
