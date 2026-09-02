# AI Security Audit — Fourth Pass (plan + candidate register)

**Date:** 2026-09-02
**Auditor:** Claude Fable 5.1 (AI-assisted)
**Scope:** whole product — Rust, Dart/Flutter, Kotlin, packaging, supply chain,
release integrity, GitHub, secrets, documentation claims, development process.
Red-team (attack) / blue-team (verify, harden).
**Status:** Planning stage. No code changed. §5 lists **candidate** findings
(T-series) from six read-only code surveys plus web research: every row has a
`file:line`, none yet has a test or repro, so none is confirmed. Same caveats
as passes 1–3: AI severity estimates, not a substitute for human review.

**Behaviour-preservation rule.** Hardening must keep every documented user
flow working as it does today. A candidate whose fix would change behaviour
(a new confirm step, an opt-in toggle, a refused input that used to work) is
marked **[behaviour]** and needs the maintainer's decision before remediation.

> Reading note. Passes 1–3 (F-, R-, S-series) predate VERSION 11, the Linux
> passkey daemon, the Android credential provider, auto-type, sync/merge, the
> `.bak` scheme and the 2026-07/08 red-team. Most of today's attack surface
> has never been audited. Pass 4 starts there.

---

## 1. Method for this pass

1. Six parallel read-only surveys (passkey daemon; Android/Kotlin; Rust
   crypto/vault/sync; auto-type + local IPC; Flutter/Dart; governance + supply
   chain), each claim tagged VERIFIED (read in code) or SUSPECTED.
2. Web research: published audits of KeePassXC, Bitwarden, Proton Pass; the
   2023–2026 vulnerability classes (AutoSpill, extension clickjacking, KeePass
   CVE-2023-32784, passkey BLE takeover); community objections to AI-written
   crypto (Gentoo, IzzyOnDroid, curl, Veracode).
3. Output: this plan, the gap list (§3), the candidate register (§5), the
   workstreams that confirm or clear each candidate (§6), and the session order (§9).

Rules carried over: a finding needs `file:line` + a repro; severities
High / Med / Low / Info / Doc; a verified-clean table so nothing is re-litigated;
remediation in separate sessions; the hardware pass is the gate for anything
touching autofill, passkeys, biometrics, export, auto-type.

---

## 2. What changed since pass 3

| Surface | Untrusted input it consumes | Audited before? |
|---|---|---|
| Linux passkey daemon (`uhid.rs`, `ctaphid.rs`, `ctap2.rs`, `passkey_daemon.rs`) | CTAPHID frames + CBOR from **any seated-user process** (stock FIDO hidraw `uaccess` rules) | no |
| Android credential provider (`GabbroCredentialProviderService`, `PasskeyProvider.kt`) | Credential Manager requests, caller identity, assetlinks JSON from the network | no |
| Linux auto-type (`autotype/`, trigger socket) | Unauthenticated same-uid socket; X11 focus | no |
| Sync / merge (`merge_*`, `.bak`) | A second `.gabbro` chosen by the user or auto-picked | no |
| v11 derivation (`hkdf.rs`), hybrid gone | Header fields | pass 1 read the pre-v11 code |
| Biometric store, SAF export, pickers, JSONC config | OS callbacks, picker results, on-disk config | partly (pass 3) |

Drift since pass 3: `debugPrint` 0 → 7 (all non-secret, all active in release);
Kotlin `Log.*` 15, of which the passkey activity's are ungated.

**Not surveyed in this pass** (same model wrote code and surveys; these are
its likely blind spots): the YubiKey Kotlin layer (`TapFlow`,
`YubiKeyManager`, NFC/USB); the generated bridge (`frb_generated.rs`, most of
the `unsafe` lines); the password/passphrase generators and the `entropy`
module (which RNG each uses); the CSV mapping screen (attacker-controlled
column names into the UI); the l10n pipeline (ARB placeholders). Plus a
tree-wide grep for LLM failure patterns: duplicated logic drifting apart
(T-02), ADR promises never built (T-35), comments describing deleted code,
tests that mirror the implementation. Assigned to W1, W3, W6, W10.

**Disclosure note.** This register is public before any fix, by the
maintainer's choice (GPL-3 posture, alpha, small user base). Med rows are
scheduled first for that reason.

---

## 3. Gaps in passes 1–3

| # | Gap | Evidence | Closed by |
|---|-----|----------|-----------|
| G1 | Never re-baselined after v11, passkeys, auto-type, sync, `.bak` | dates 05-31 / 06-11 / 06-25; v11 landed 07-09 | W1, W2, W4, W5 |
| G2 | Static reading trusted too far; only fixed-seed in-tree "fuzzers", none coverage-guided | R-01; no `cargo fuzz`, no `proptest` | W1, W2, W5 |
| G3 | Test quality never measured (AI tests over AI code) | no `cargo mutants` | W1, W5 |
| G4 | Tapjacking deferred twice (R-07 → "remains unaddressed") | no `filterTouchesWhenObscured` in tree | W3 |
| G5 | Swap/`mlock` deferred to an expert review that has not happened | R-05 | W7 |
| G6 | Memory forensics stale (2026-06-14, before passkey keys and cards) | `mem_forensics.sh` canaries | W7 |
| G7 | Availability half-closed: ransomware, deletion, `.bak` under the old passphrase | S-2, R-03 residual | W5, W10 |
| G8 | Supply chain = advisories only; no build-time code-execution inventory, SBOM, toolchain pin, SDK provenance | pass 3 §Supply-chain | W8 |
| G9 | Release integrity never audited: tag signing, key escrow, keystore-loss plan, reproducibility, GitHub settings | no CI; `.github/` = FUNDING.yml | W9 |
| G10 | "No telemetry" asserted, never measured | README instruction only | W9 |
| G11 | `rust/src/fido/` deferred in every pass; `unsafe` FFI never read | "deferred per ADR-010" ×3 | W1 |
| G12 | Logging drift unchecked | 7 `debugPrint`, 15 `Log.*` | W6 |
| G13 | Doc claims drift: SECURITY.md dated 06-20; F-12 contradicts its own heading; ADR-017 §2 clipboard claim wrong | files | W10 |
| G14 | Severities never human-rated | every pass says so | external scope (W10) |
| G15 | Auditor monoculture: every pass is a Claude model | headers | W10 |
| G16 | Red-team report retired to git history | commit b3ca91c7 | W10 |
| G17 | ADR conformance never checked: ADR-017 says opt-in + Wayland detection; neither exists | T-35 | W4 |
| G18 | Encoding of the passphrase never tested with non-ASCII input across all entry points | T-02 | W1, W6 |
| G19 | Concurrency never audited: session mutex released during save; lock vs save; overlapping fills | T-03, T-04, T-37 | W1, W4 |

---

## 4. Attacker personas (red team)

1. **File thief** — has `.gabbro`, `.bak`, `.stversions/`, sync copies. Offline.
2. **Same-uid local process (Linux)** — no root. Opens the hidraw node, the auto-type socket, X11, `~/.config/gabbro/`; reads `/proc`. Includes sandboxed desktop apps granted X11 access.
3. **Malicious Android app** — installed by the victim. Autofill, credential provider, WebView, overlays, intents, shared storage.
4. **Malicious website / relying party** — drives passkey flows and the one network call.
5. **Malicious file** — import, poisoned sync `.gabbro`, tampered `.bak`, restore-from-file.
6. **Supply chain** — crates, pub packages, Gradle, the AUR-sourced Flutter SDK, the FRB codegen binary, IDE tooling, the AI coding tool.
7. **Impersonator** — fake update, repackaged APK, tampered tarball or APT index, moved git tag.
8. **Physical access** — RAM, swap, hibernation, biometrics, cold boot.

Out of scope stays as SECURITY.md states: root, compromised YubiKey, coercion, silicon side-channels.

---

## 5. Candidate findings (T-series, unconfirmed)

Severity is the AI estimate **if confirmed**. "Repro" says what a confirming
session must produce. `[behaviour]` = fix changes a user-visible flow.

### 5.1 Rust crypto, vault, sync (W1, W5)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-01 | Med | Argon2 `m_cost`/`t_cost` read from the header with no upper bound and run **before** the AAD check: a crafted file aborts the process (4 GiB alloc) or hangs it (`t_cost = 2^32`) on open, adopt, restore-from-file, or sync pick | `file_format.rs:232-236`, `kdf.rs:39`, `vault_crypto.rs:72` | craft header; open via adopt; observe abort |
| T-02 | **Med-High** | Passphrase encoding is inconsistent and lossy: create/unlock/change send `String.codeUnits` (UTF-16) through `Uint8List.fromList`, which keeps the low byte of each unit; import and sync send `utf8.encode`. Consequences: (a) a non-Latin passphrase collapses to an ASCII-range byte string (Cyrillic а..я → `0`..`O`), losing entropy the user believes they have and the generator advertises; (b) a vault with a non-ASCII passphrase cannot be synced or imported by the same app | `unlock_screen.dart:680`, `onboarding_screen.dart:473,491`, `change_passphrase_screen.dart:271-272`, `security_screen.dart:215,238`, `frb_generated.dart:6649`; vs `import_screen.dart:396`, `vault_list_screen.dart:1349` | create vault with passphrase `пароль`; sync from it → fails; show two distinct passphrases yielding one key |
| T-03 | Med | Save runs **outside** the session mutex: every mutating op clones body + passphrase + key, releases the lock, then does Argon2id + write. Lock landing mid-save zeroizes the session while the clones live, and the file write lands after "locked" | `session.rs:423-481,600-619,3741-3979`; lock is sync `vault_bridge.rs:418`; Dart timers `main.dart:1103,1140,1197` | trigger lock during a slow save; observe write after lock |
| T-04 | Low | Two concurrent saves share one `<path>.tmp`; possible rename of a temp another thread is still writing (lost update, not corruption) | `io.rs:136`, `io.rs:37` | two overlapping saves |
| T-05 | Low | A panic while the session guard is held poisons the mutex; plaintext stays resident; no panic hook | `session.rs:59,118` | inject panic in a bridge call |
| T-06 | Low | Restore-from-file and adopt write the foreign header verbatim; a keyed vault then keeps weak Argon2 params on every later save (merge cannot import weak params — verified clean) | `io.rs:231,245`, `vault.rs:1293-1302` | adopt a file with `t_cost=1`; save; inspect header |
| T-07 | Low-Med | Sync ignores local tombstones: an incoming entry absent locally is always added, so a deleted (compromised) login resurrects and may autofill again; incoming `field_times` trusted unbounded (`u64::MAX` wins every field) **[behaviour]** | `session.rs:3556-3565`, `session.rs:1410-1425` | delete entry; sync from an older copy |
| T-08 | Low | Merge accepts Passkey entries with arbitrary key material; no check that `private_key` matches `public_key_cose` | `session.rs:1735-1770` | sync a file with mismatched keypair |
| T-09 | Low | After a passphrase/key change, `.bak` holds the old-credential bytes until the refresh step; a crash in between leaves it so; undocumented | `io.rs:80,105`, `session.rs:665` | kill between rotate and refresh |
| T-10 | Low | `Debug` derived on every secret-bearing type (`LoginEntry`, `CardEntry`, `PasskeyEntry`, `FileEntry`, `VaultEntry`, `HmacMatch`); one `{:?}` in a future error path prints secrets | `entry.rs:122-408`, `fido/device.rs:138-144` | grep + a tripwire test |
| T-11 | Low | `fido/`: hmac-secret output, PIN `CString` and 64-byte pair never zeroized; device/cred/assert handles leak on every early `Err` | `fido/device.rs:40,69-98,141,151,228-245` | code read + valgrind-style handle count |
| T-12 | Info | `harden_process()` failure is logged, not fatal; picker dumpable-toggle errors swallowed, so a failed lower leaves the process dumpable silently | `api/simple.rs:8`, `safe_file_picker.dart:34-38` | fault-inject `prctl` |
| T-13 | Info | `body_len as usize` truncates on the shipped 32-bit `armv7` target; GCM still fails, no memory issue | `file_format.rs:335` | none needed; note |

### 5.2 Linux passkey daemon (W2)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-14 | Med | Silent `getAssertion` (`options.up=false` + allowList) is **signed with no consent** over an attacker-supplied `clientDataHash`, returning credential id and user handle. Any seated-user process that knows a credential id gets a valid assertion. Spec-permitted, but it makes vault passkeys usable by local malware without user presence, which is the property passkeys are sold on | `ctap2.rs:67-71,348-361`, `webauthn.rs:68-70` | local CTAP client; obtain assertion |
| T-15 | Med | No reassembly timeout: one INIT packet with a large BCNT and no continuations wedges the single global `Pending`; every channel gets `ERR_CHANNEL_BUSY` until restart. Passkeys DoS by any local process (or a buggy browser) | `ctaphid.rs:23-37,66-68`, `passkey_daemon.rs:161-226` | send one INIT; browser passkey use fails |
| T-16 | Low-Med | Cross-channel response misrouting: a second request during an open consent dialog re-points `inflight_cid`; the signed response for request 1 is framed onto channel 2 (SUSPECTED) | `passkey_daemon.rs:177-201` | interleave two clients |
| T-17 | Low | Consent is bound to the chosen account only by an index re-derived at perform time; if the rp's passkey set changes in between, a different credential signs | `ctap2.rs:117-120`, `passkey_daemon_bridge.rs:66-70` | change set during dialog |
| T-18 | Low | `rp_id` accepted verbatim (no length, case, IDNA or PSL rule) and rendered raw in the consent dialog; a homograph or RTL-override rp_id misrepresents the site | `ctap2.rs:202,299`, `passkey_consent_dialog.dart:26-28` | rp_id with U+202E |
| T-19 | Low | Credential-existence oracle: `getAssertion` without allowList returns 0x2e instantly when the rp has nothing, but streams KEEPALIVE when it does, before the user acts | `ctap2.rs:325-327`, `passkey_daemon.rs:208-214` | time the two cases |
| T-20 | Low | BCNT unbounded against `maxMsgSize` (64 KiB accepted); `next_seq` is `u8` with no bound (panics in debug); CTAPHID CANCEL not implemented; CID counter never wraps | `ctaphid.rs:70,94,120,126` | oversized message; >256 CONTs |
| T-21 | Info | Counter fixed at 0 (sanctioned for synced keys, removes clone detection); no `credProtect`; `numberOfCredentials` absent | `webauthn.rs:76,91`, `ctap2.rs:371-386` | note; decide |
| T-22 | Info | No fuzzer for CTAPHID, CTAP2 or CBOR; ciborium nesting 256, no size limits | `ctap2.rs:90-296` | add harness |

### 5.3 Android (W3)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-23 | Med | Autofill matches on `webDomain` **before** package, with no browser allowlist on that path: a native app whose own view structure claims `webDomain=bank.example` is offered the bank's credentials (AutoSpill class) | `GabbroAutofillService.kt:243-252,726-728` | test app with a WebView / custom view asserting a domain |
| T-24 | Med | Assetlinks URL is built by interpolating an unvalidated `rpId`; redirects are followed; no response size cap. A site with an open redirect on `/.well-known/` (or a subdomain takeover) lets an attacker app be "verified" for that rp_id | `PasskeyProvider.kt:142`, `GabbroPasskeyActivity.kt:105-110` | rpId `victim.example` + 302 to attacker host |
| T-25 | Low-Med | No public-suffix / registrable-domain check on native-app `rpId`; relation list accepts `handle_all_urls` (deep-link relation) as sufficient | `PasskeyProvider.kt:91-93,145` | rpId `co.uk` |
| T-26 | Low-Med | Tapjacking: no `filterTouchesWhenObscured` / `setHideOverlayWindows` on unlock, consent, save; only `FLAG_SECURE` (R-07, open since 06-11) | `GabbroUnlockHostActivity.kt:63` | overlay PoC |
| T-27 | Low | Passkey activity logs caller package, cert SHA-256 and `rpId` in **release** builds | `GabbroPasskeyActivity.kt:131,148-153,269-274` | logcat |
| T-28 | Low | Passwords cross JNI as immutable `String` and flow into `AutofillValue`; nothing zeroed on the Kotlin side (F-04/L-2 class, still open) | `RustBridge.kt:16-45`, `GabbroAutofillService.kt:292-299,343` | heap dump |
| T-29 | Low | Biometric Keystore key not pinned to `AUTH_BIOMETRIC_STRONG` at the key layer; no `setUnlockedDeviceRequired`; decrypted passphrase copy handed to Flutter is never zeroed; enrol hex `String` never cleared | `BiometricHelper.kt:131-147`, `GabbroUnlockHostActivity.kt:239-244,263` | code read |
| T-30 | Low | Clipboard copies lack `EXTRA_IS_SENSITIVE`; Android 13+ shows the password in the clipboard preview | no `ClipData` handling in Kotlin; `clipboard_clear.dart:32` | copy on Android 13 |
| T-31 | Info | R8 minify off despite proguard config; **debug builds signed with the release key**, `key.properties` loaded unconditionally | `build.gradle.kts:52-62,10-12` | note |
| T-32 | Low | Save flow: a hostile app controls username, email, password and (via webDomain) the stored URL; the confirm screen is the only gate — an injected entry with a victim URL later autofills there **[behaviour]** | `GabbroAutofillService.kt:107-130`, `SaveActivity.kt:54-60` | hostile save request |

### 5.4 Linux auto-type, clipboard, local process (W4)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-33 | Med | Any same-uid process connects to the trigger socket (no peer check), and the target window is captured **after** the trigger, then deliberately re-activated: the attacker's own window receives username, Tab, password, Enter. Precondition: a Login detail screen is open in Gabbro **[behaviour]** | `trigger.rs:82`, `main.dart:705-715`, `fill.rs:118-132` | 20-line client + focused window |
| T-34 | Low | `ChangeKeyboardMapping` binds password keysyms to scratch keycodes for the typing window; every X client can read them with `GetKeyboardMapping` (no XTEST or grab needed) | `inject.rs:170-186` | second client polls mapping |
| T-35 | Low | Listener starts on every Linux launch; no opt-in toggle and no Wayland detection, contradicting ADR-017 §3/§8 **[behaviour]** | `main.dart:664-665` | none; conformance |
| T-36 | Low | Fallback socket path under `/tmp` when `XDG_RUNTIME_DIR` is unset; directory and socket keep default mode; delete-then-bind TOCTOU; no symlink check | `trigger.rs:28-53`, `autotype_listener.dart:26-32` | unset var; other user pre-creates |
| T-37 | Low | Per-connection buffer unbounded, no rate limit, no in-flight guard: memory growth, and overlapping fills interleave keymap batches | `autotype_listener.dart:59-61`, `main.dart:705-715` | stream without close; two triggers |
| T-38 | Info | Intermediate keysym `Vec`s built before the `Zeroizing` wrap are dropped unscrubbed | `sequence.rs:13-17`, `keysym.rs:18-20` | code read |
| T-39 | Doc | Linux clipboard managers keep history regardless of the wipe; ADR-017 §2 claims deterministic clearing; no `x-kde-passwordManagerHint`; the wipe overwrites whatever is on the clipboard, including the user's later copy | `clipboard_clear.dart:57-60`, ADR-017 §2 | doc + optional MIME hint |

### 5.5 Flutter / Dart (W6, W7)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-40 | Med | `suspendForegroundLock()` is resumed only `if (mounted)`; if the YubiKey-management screen unmounts during a tap, foreground auto-lock stays off for the process lifetime | `manage_yubikeys_screen.dart:284-292`, `main.dart:1100,1109-1113` | unmount mid-tap; timer never fires |
| T-41 | Low-Med | `_lock()` returns early when the last-used vault file is missing, after `lockVault()` but **before** clearing the navigation stack; decrypted screens and reveal state stay on screen | `main.dart:1199-1206` | remove file; auto-lock |
| T-42 | Low | Reveal state and displayed secrets survive Android pause and Linux focus loss until a lock fires; no lifecycle observer on detail/generator screens | `entry_detail_screen.dart:150-153`, `generator_widget.dart:198` | reveal; background; resume |
| T-43 | Low | Cheap lifetime reductions missing: passphrase controllers never cleared after success; biometric bytes not zeroed; `SaveContext.password` retained for the activity lifetime; entropy estimator receives the live passphrase per keystroke (F-12 class) | `unlock_screen.dart:343,680,690`, `change_passphrase_screen.dart:147-149`, `onboarding_screen.dart:310-311,447-450`, `main.dart:563-577` | gcore canaries |
| T-44 | Low | Registry vault paths unvalidated (traversal, symlink, extension); a malformed `settings.jsonc` or one unknown enum silently resets **all** settings (auto-lock, clipboard timeout, paste block) to defaults; malformed registry → empty list | `vault_registry.dart:38-44,91-103`, `settings.dart:105-121,220-232` | corrupt one byte |
| T-45 | Low | Raw bridge error strings shown at ~25 sites; serde's `unknown variant` echoes file content into the UI | survey list (change_passphrase 299, unlock 469, vault_list 878/1540/2776, import 366/428/456, …) | craft body |
| T-46 | Low | No bidi isolation or IDN display for vault URLs, titles and rp_id in confirm dialogs | `entry_detail_screen.dart:790,822`, `passkey_consent_screen.dart:29-31` | U+202E title |
| T-47 | Info | `debugPrint` active in release; messages carry entry id and socket path (not secrets) | `main.dart:697,713` | note |

### 5.6 Governance, release integrity, supply chain (W8, W9)

| ID | Sev | Candidate | Where | Repro to produce |
|---|---|---|---|---|
| T-48 | Med | Release tags and commits are unsigned; the release recipe prescribes `git tag -a` (artifacts are signed, the tag naming them is not) | `BUILD_AND_RELEASE.md:247`; `git tag -v` → no signature | none; fix recipe |
| T-49 | Med | Toolchain provenance: Flutter SDK from an AUR package validated by md5 only, `Validated By: None`; `flutter_rust_bridge_codegen` `cargo install`ed with no recorded hash; Rust toolchain unpinned; `build-deb.sh` downloads the tarball unverified when given no `--tarball` | `~/.cache/yay/flutter-bin/PKGBUILD:60-61`, `build-deb.sh` | none; policy |
| T-50 | Low | No security contact or disclosure policy: SECURITY.md points to a contact the README does not state; no root/`.github` SECURITY.md (GitHub shows none); no GHSA mention; no `security.txt` | `SECURITY.md:16-17,410-411` | none; write policy |
| T-51 | Low | A personal identity is present in the public commit history of the main repo and the AUR clone, and is the active git identity in both — against the project's own PII rule | `git log`; AUR clone config | none; rotate identity |
| T-52 | Low | `.gitignore` covers keystores only under `android/`; no `.env` pattern; no `rust-toolchain.toml`; no Dependabot alerts or advisory-only CI | `.gitignore`, `android/.gitignore` | none |
| T-53 | Info | Pass 1's IDE-extension list is obsolete for this machine (VSCodium, Python tooling only); rust-analyzer build-script note still true where it is installed | `codium --list-extensions` | refresh table |
| T-54 | Info | `vault_parse_fuzz` is not an explicit gate leg (runs inside `cargo test`); no coverage-guided fuzz; no mutation score; 23 build-script crates and 7 proc-macro crates execute at compile time on the resolved target (42 / 12 across all targets) | `gabbro_test`, `cargo metadata` | add legs |

---

## 6. Workstreams (what confirms or clears each candidate)

**W1 — Rust core.** T-01..T-06, T-10..T-13. Add: constant-time review (only
`aes-gcm`'s tag check is CT; `PasskeyEntry` `PartialEq` compares private keys
byte-wise, local only); the `change_vault_passphrase_with_keys` intermediate
that carries the old nonce with a new AAD until reseal (footgun, verified safe
today); RFC 9106 / 5869 / SP 800-38D known-answer vectors; `cargo mutants`
score for `crypto/` and `vault/`; `cargo fuzz` target for `from_bytes`.

**W2 — Passkey daemon.** T-14..T-22. Add: `cargo fuzz` targets for
`ctaphid::handle_report`, `ctap2::describe_request`; conformance run with
`fido2-token`/`fido2-cred` and two browsers; decide the `up=false` policy
against CTAP 2.1 §hmac-secret and the platform-authenticator practice of
refusing silent assertions **[behaviour]**; per-channel reassembly with timeout.

**W3 — Android.** T-23..T-32. Add: AutoSpill test app; overlay PoC; assetlinks
client with `instanceFollowRedirects=false`, host-only rp_id syntax, PSL
check, size cap; MobSF + `apkanalyzer` on the release APK; Robolectric nets
for rp_id syntax, public-suffix rp_id, redirect, webDomain precedence.

**W4 — Auto-type, clipboard, local IPC.** T-33..T-39. Options for T-33 that
keep the flow: capture the active window **before** accepting the trigger
(needs a small design change), refuse if the active window changed within N
ms of the trigger, or require a physical keypress in Gabbro **[behaviour]**;
`SO_PEERCRED` uid check (cheap, no behaviour change); `0700` socket dir;
bounded buffer; single in-flight fill; Wayland detection; the opt-in toggle
ADR-017 promised.

**W5 — Vault format, sync, import, availability.** T-06..T-09. Add: sync-merge
fuzzer (two vaults, random ops, invariants: no resurrection without a
decision, no newer-loses); `cargo fuzz` over the import parsers; document
`.bak` semantics after credential change; crash-safety re-run with the `.bak`
sync step.

**W6 — Flutter.** T-40..T-47, T-02 (Dart side). Add: a net that fails the suite
on any `print`/`debugPrint` outside an allow-list; lifecycle observer on
secret-showing screens; controller clearing; registry path validation; a
per-field settings fallback; bidi isolation (`Bidi`/`⁨…⁩`) on
untrusted strings.

**W7 — Memory and physical access.** Re-run `mem_forensics.sh` on the current
GUI with canaries for a passkey private key, a card number and a Cyrillic
passphrase; KeePass CVE-2023-32784-style keystroke-remnant test on Flutter's
obscured field; decide `mlock`/`MADV_DONTDUMP` for the 32-byte keys (R-05).

**W8 — Supply chain.** T-49, T-52..T-54. Inventory the 23 build-script crates
and 7 proc-macros; `rust-toolchain.toml`; record the FRB codegen hash; SBOM
(`cargo cyclonedx`, `flutter pub deps --json`) attached to releases; consider
`cargo vet`; verify the Flutter tarball against Google's published SHA-256
instead of the AUR md5; state the AI coding tool as a same-uid actor in
`AI_DEVELOPMENT_PROCESS.md` (its hooks and permission file are the control).

**W9 — Release integrity, GitHub, secrets.** T-48, T-50, T-51. Signed tags
(`git tag -s`), signed commits; root `SECURITY.md` with contact, PGP key,
embargo window, GHSA; `security.txt` on the Pages site; GitHub 2FA, branch
protection, secret scanning + push protection, Dependabot **alerts only**;
GPG key revocation cert and Android keystore escrow + loss plan; reproducible
build recipe (Docker, pinned toolchain; bit-for-bit is the goal, not the
first milestone); "no telemetry" proven by `tcpdump` in the gate's netns.

**W10 — Documentation and claims.** T-39, G13, G16. Red-team every sentence
in README and SECURITY.md "What has been verified"; date SECURITY.md; restore
the RT findings table; add availability, passkey (AAL2) and auto-type rows to
the threat model; write the external-review scope (OSTIF-style intake) from
this document.

---

## 7. Verified clean in the surveys (do not re-litigate)

| Property | Evidence |
|---|---|
| Every AES-GCM seal draws a fresh `OsRng` nonce; no derived nonces | `aes_gcm.rs:18-19,57-58`; all 13 seal sites enumerated |
| Tag/passphrase verification is `aes-gcm`'s constant-time check; no manual tag compare | `aes_gcm.rs:38,90` |
| No panic on attacker input in `file_format`/`vault_crypto`; all slices length-guarded; `body_len` `checked_add` | `file_format.rs:270-348`, `vault_crypto.rs:206-342` |
| `.bak`, `.tmp`, `.pre-restore` are `0600` + `O_NOFOLLOW` + symlink-checked | `io.rs:20,51,87` |
| Merge never imports foreign Argon2 params | `vault.rs:1176,1293-1302` |
| Passkey private key never crosses to Dart; DTO blanks it | `vault_bridge.rs:377-394`, `passkey_daemon_bridge.rs:66-76` |
| Locked daemon answers only getInfo; create/assert refused before parsing | `ctap2.rs:53,191-193,293-295` |
| No `.gabbro` MIME/VIEW handler on Linux or Android; no custom scheme | packaging + manifest |
| URL opener allows `http`/`https` only; `xdg-open` via argv, no shell | `gabbro_url_opener.dart:35-49`, `linux_url_opener.dart:229` |
| All 37 locales carry all 681 keys; no blank security string possible | `l10n.yaml`, `lib/l10n/*` |
| No secrets in git history (8 pattern hits, all fixtures/placeholders); no host paths or personal emails in tracked files | full-history grep |
| GPG fingerprint + public key and Android cert SHA-256 published; artifacts detach-signed | `README.md:330-363,437-445` |
| Backup fully excluded; `FLAG_SECURE` on the shared base activity; exported services guarded by system permissions; PendingIntents target non-exported activities | manifest, `GabbroUnlockHostActivity.kt:63` |
| Assetlinks fetch fails closed on any exception, toggle-off refuses before network | `PasskeyProvider.kt:139-143,168-172` |
| `deny.toml` locks sources to crates.io, denies yanked; no `build.rs` of our own; no git deps | `rust/deny.toml`, `cargo tree -e build` |
| Immutable releases enabled; AUR PKGBUILD pins sha256 for both sources | docs, `linux/packaging/aur/PKGBUILD` |
| `harden_process`: `RLIMIT_CORE` hard 0 never relaxed; picker toggle nesting-safe | `hardening.rs:9-58`, `safe_file_picker.dart:54-68` |

---

## 8. What the community objects to, and what this pass must earn

Sources: Gentoo (mgorny, "vibe-coded cryptography software"), IzzyOnDroid's
inclusion policy (ADR-019), curl's 2026-01 bug-bounty shutdown over AI slop,
Veracode 2025/2026 (45% of samples insecure; best model 68% pass),
Cryptography Stack Exchange on Gabbro (ADR-018), r/privacy threads.

| Objection | Where Gabbro stands | What this pass must do |
|---|---|---|
| "Rolled their own crypto" | Composition of RustCrypto primitives only | W1: list every crypto call site; prove no hand-rolled primitive or compare |
| "Unaudited" | True; AI passes are informational | W10: fundable external scope; this document is the intake |
| "AI tests testing AI code" | Real risk | W1/W5: report the mutation score, not the pass count |
| "Hallucinated or malicious deps" | Names checked in pass 1 | W8: SBOM, `cargo vet`, build-time execution inventory |
| "Plausible findings, no repro" (curl) | Passes 1–3 required `file:line` | §5 rows stay *candidates* until a repro exists; record what the AI got wrong (R-01 precedent) |
| "Single developer" | True | W9: key escrow, contact, succession note |
| "Open source ≠ audited" | Acknowledged | W9: reproducible builds so "open" means "this binary is that source" |
| "Password managers leak via autofill" (AutoSpill, clickjacking, KeePass CVE-2023-32784) | No extension; AutoSpill class present as T-23; tapjacking T-26 | W3, W7 |
| "New PQ code drifts from spec" | Hybrid removed | W1 known-answer vectors |
| "Why not KeePassXC?" | Legitimate | README: honest differences, no claims |

---

## 9. Session order

Each session ≤ one cluster, hardware-verified where marked, findings
confirmed or cleared before any remediation.

1. **Quick confirmations, high value:** T-01, T-02, T-03, T-40, T-41 (all reproducible on a dev box in one session).
2. **W2 passkey daemon:** T-14..T-22 + fuzz harness. *Linux hardware.*
3. **W3 Android:** T-23..T-32 + AutoSpill/overlay PoCs. *Android hardware.*
4. **W4 auto-type + clipboard:** T-33..T-39. *Linux hardware.*
5. **W5 sync/import:** T-06..T-09 + merge fuzzer.
6. **W8 + W9 supply chain, release, GitHub, secrets:** T-48..T-54; `tcpdump` no-telemetry proof.
7. **W6 + W7 Flutter, memory:** T-42..T-47; gcore re-measure.
8. **W10 docs and external-review scope.**

Remediation follows each session in its own session with a hardware matrix,
as in passes 1–3. Candidates marked **[behaviour]** wait for the maintainer.

---

## 9b. Avenues beyond the workstreams (external-reviewer view)

What an outside reviewer landing on this repo would still ask for. Ranked by
trust gained per hour. Only A4 changes user-visible behaviour.

| # | Avenue | Why it matters | Where it lands |
|---|--------|----------------|----------------|
| A1 | **OpenSSF Scorecard** run and published | The first thing an automated reviewer runs; today Gabbro scores low on signed releases, branch protection, security policy, fuzzing, pinned deps — most already in T-48..T-52 | W9 |
| A2 | **Passphrase strength estimator audit** against zxcvbn-class corpora and breach lists | SECURITY.md says passphrase-only security equals passphrase strength; a flattering estimator silently weakens every such vault | new: W1 (Rust `entropy`) + W6 (onboarding UI) |
| A3 | **Standalone vault format spec** (`VAULT_FORMAT.md`: byte layout, version rules, AAD bytes, published test vectors) | Auditors need it; lets a stranger verify the v11 derivation independently, the way KDBX can be | W10 |
| A4 | **Secure-by-default on Linux** **[behaviour]**: passkey daemon and auto-type listener start on every launch; the CTAP parser runs inside the key-holding process | Reviewer asks why both are on by default and why a parser bug equals the vault; answers are opt-in defaults (ADR-017 promised one) and Landlock/seccomp confinement of the daemon | W2, W4 |
| A5 | **Continuous fuzzing** (OSS-Fuzz or ClusterFuzzLite) | Turns "fuzzed once" into "fuzzed daily"; free for Rust projects | W2, W5, W8 |
| A6 | **Public post-mortem of the 2026-06-08 vault-brick incident** | Trust comes from how incidents were handled; this one produced the compat gate | W10 |
| A7 | **"Audit Gabbro in one afternoon" guide** (offline build, gate, `mem_forensics.sh`, fuzzers, hardware matrix) | Lowers the bar for the volunteer reviewer the project hopes for | W10 |
| A8 | **Sigstore/cosign signing beside GPG** | Provenance in a public transparency log; survives a lost GPG key | W9 |
| A9 | **Move rows out of §5 quickly** | Fifty-four unconfirmed candidates left standing read as the AI slop the doc warns about; confirmed or struck rows are the proof of work | session 1 onward |
| A10 | **A named human review**, even partial (one module, one afternoon) | Until a person signs something, the auditor monoculture (G15) stands | W10 scope |

---

## 10. Tooling to add

`cargo fuzz` (ctaphid, ctap2, from_bytes, merge, import), `cargo mutants`,
`cargo geiger`, `cargo cyclonedx`, optional `cargo vet`, `gitleaks`,
`semgrep`, MobSF, `apkanalyzer`, `tcpdump` in the gate's netns.
Existing: `cargo audit`, `cargo deny`, `osv-scanner`, `mem_forensics.sh`,
the in-tree property tests.

---

## 11. Published audits to borrow method from

| Audit | Useful for |
|---|---|
| Recurity Labs, Proton Pass 526.2501 (2026) — mapped in pass 1 | symlink, permissions, memory forensics |
| Cure53, Bitwarden (annual since 2020) | crypto "unnecessary complexity" class; autofill overlay |
| Molotnikov, KeePassXC 2.7.4 (2023) | memory after lock; database read/write review shape |
| ANSSI CSPN, KeePassXC 2.7.9 (2025) | first-level certification checklist |
| OSTIF audit programme | scoping and funding an external review |
| Tóth, DOM-based extension clickjacking (DEF CON 33) | confirms ADR-008; overlay analogues on the uhid consent dialog |
| AutoSpill (Black Hat EU 2023) | T-23 |
| KeePass CVE-2023-32784 | W7 keystroke-remnant test |
| CVE-2024-9956 (FIDO:/ BLE) | confirm no hybrid-transport handling exists |

---

## Findings register (T-series, confirmed)

_Empty until a session produces a repro. Rows move here from §5._

| ID | Finding | Sev | Layer | Status |
|----|---------|-----|-------|--------|

---

## References

- Bitwarden audits: https://bitwarden.com/help/is-bitwarden-audited/
- Cure53 publications: https://github.com/cure53/Publications
- KeePassXC audits: https://keepassxc.org/audits/
- OSTIF 2024–25 report: https://ostif.org/sovereigntechagencyostifreport2025/
- Extension clickjacking: https://marektoth.com/blog/dom-based-extension-clickjacking/ ; https://www.kb.cert.org/vuls/id/516608
- AutoSpill: https://dl.acm.org/doi/abs/10.1145/3577923.3583658
- KeePass CVE-2023-32784: https://github.com/vdohney/keepass-password-dumper
- CVE-2024-9956: https://mastersplinter.work/research/passkey/
- Veracode 2026 GenAI Code Security: https://www.veracode.com/blog/spring-2026-genai-code-security/
- LLM PQC secure-coding drift: https://arxiv.org/pdf/2606.19474
- curl and AI slop: https://www.bleepingcomputer.com/news/security/curl-ending-bug-bounty-program-after-flood-of-ai-slop-reports/
- RustSec #189 (Argon2 constant-time): https://github.com/RustSec/advisory-db/issues/189
- WebAuthn rp_id rules: https://web.dev/articles/webauthn-rp-id
- EncryptedSharedPreferences deprecation (not used by Gabbro; noted for ADR-011 accuracy): https://proandroiddev.com/goodbye-encryptedsharedpreferences-a-2026-migration-guide-4b819b4a537a
- Clipboard managers vs auto-clear (KeePassXC #926): https://github.com/keepassxreboot/keepassxc/issues/926
- Gentoo on vibe-coded crypto: https://blogs.gentoo.org/mgorny/2026/05/28/why-gentoo/
- IzzyOnDroid policy: https://izzyondroid.org/docs/general/AppInclusionPolicy/
- Reproducible builds: https://f-droid.org/docs/Reproducible_Builds/ ; SLSA: https://slsa.dev/spec/draft/build-provenance
