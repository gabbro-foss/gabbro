# Gabbro — Learnings & Concepts

A running journal of concepts and hard-won lessons. Terse by design: short = good.

---

## Post-mortems & safety-critical lessons

### Vault-format backward compat is a hard TDD gate (brick, 2026-06-08)
A "test coverage" session (Sonnet 4.6) bricked the real YubiKey-only vault (no biometric
fallback) — real data loss, both vaults wiped and recreated. Forensics: committed source was
clean and seal<->open symmetric; the brick came from an **intermediate build run during the
session** that re-sealed the on-disk YubiKey keyslot into a state the reverted code couldn't
open. A clean rebuild can't fix bytes already on disk. YubiKey-only vaults have no second door
(biometric vaults survive because `vault_key_master` is wrapped independently in AndroidKeyStore).
**Lesson:** any change touching vault format, sealing/unsealing, the YubiKey keyslot, AAD binding,
or ML-KEM/KDF derivation — any platform — must prove backward compat against already-sealed
vaults via failing-test-first TDD with frozen golden fixtures per VERSION. "Builds + unit tests
pass on freshly-sealed vaults" is NOT evidence. Never let unverified code re-seal a user's
keyslot. [[feedback_vault_format_backward_compat_tdd]]

### Only FROZEN bytes catch a brick; round-trips never can
The brick passed a green suite because every backward-compat test re-sealed in-process then
opened (a round-trip) — which only proves "this build reads what this build wrote," never "this
build reads a *previous* build's vault." Golden-fixture harness (`rust/tests/vault_backward_compat.rs`):
- **Freeze real bytes.** Commit actual `.gabbro` files sealed once by the build that shipped each
  VERSION; never regenerate with new code.
- **Generate old versions from the tag that shipped them** (e.g. v6 fixtures from a `git worktree`
  at `v0.1.0-alpha.4`), not hand-rolled bytes. Files named by compiled-in `VERSION`.
- **Drive the real bridge fns** (`api::vault::{load_vault, load_vault_with_key_record,
  add_yubikey_to_vault, remove_yubikey_from_vault, save_vault}`) on a temp copy — exercises IO,
  (de)serialise, open, mandatory re-seal, AAD, version bump.
- **Subtlety that itself bricks:** `add_key_to_sealed`/`remove_key_from_sealed` only edit the
  record list — they do NOT re-seal the body. On a v7 vault the body is AAD-bound to those records,
  so you MUST follow with `reseal_vault_body` (also bumps version). The bridge fns do this
  internally; any new header-mutating path must too.
- **Keep it cheap:** fixtures sealed with transiently-lowered Argon2id params (params live in the
  header and are read back on open, so magnitude doesn't change the code path). Revert production
  after; see `FIXTURES.md`.
**Standing gate:** every new VERSION ships `vN_passphrase.gabbro` + `vN_multikey_2keys.gabbro`.
In the Release pre-flight.

### Vault safety copy — "sync after verified save", not "rotate before write" (R-03)
First design (rotate the existing file to `.bak` *before* overwriting) is wrong: the backup is
always one save behind, so restore silently drops the user's latest edit. Correct model: **`.bak`
= last *verified* save.** In `write_vault`: write the main file atomically, **read it back and
parse** (`SealedVault::from_bytes` — cheap, no KDF), then copy the verified bytes to `.bak`.
Payoffs: restore returns the latest good state; a save that wrote successfully but is garbage
fails loudly and leaves `.bak` at the previous good state. Residual: a save that parses but is
logically wrong still flows to `.bak` — backward-compat gate + fuzzer guard that class.
UX corollaries: probe **usability not existence** (parse-check `.bak`; `backup_usable` not
`backup_exists`); a suggestion is not a recovery path (provide the file-picker restore button,
don't just say "restore from your off-device backup"); destructive UX is platform-shaped
("remove but keep file" only makes sense on desktop; on Android app-private storage offer
"Delete file").

### Process hardening — stop in-RAM secrets escaping to disk/another process (R-04)
The vault file is always encrypted; the exposure is **decrypted** material in RAM while unlocked.
Two escape routes, two Linux syscalls (`rust/src/hardening.rs`):
- `setrlimit(RLIMIT_CORE, {0,0})` — no crash core dump (zero the *hard* limit too).
- `prctl(PR_SET_DUMPABLE, 0)` — blocks `ptrace` / `/proc/<pid>/mem` by same-uid processes (also
  gates core dumps).
Call once early via the frb `#[frb(init)]` hook (`init_app()`), before any secret is in memory.
Failure logged not fatal. No-op off Linux (Android is already non-dumpable). Crate: `libc`
(already a transitive dep -> zero added supply-chain surface), `cfg(linux)`-only.
**The dumpable<->portal trap (a regression this caused):** `PR_SET_DUMPABLE(0)` and `file_picker`
cannot coexist. A non-dumpable process has `/proc/<pid>/{root,cwd,exe}` symlinks gated by
`ptrace_may_access`; `xdg-desktop-portal` reads exactly those to build the caller's app-info on a
FileChooser request -> EACCES -> *every* Linux file dialog failed as "portal unreachable" on a
normal desktop. Fix: keep `DUMPABLE=0` as baseline but **raise it only for the picker window** —
`runPicker` (`safe_file_picker.dart`) brackets each dialog with `setProcessDumpable(true/false)`
(ref-counted for nesting). During that brief user-initiated window yama `ptrace_scope >= 1`
(Debian/Mint/Arch defaults) still blocks non-ancestor tracers; `RLIMIT_CORE=0` untouched.
Regression guard: fork-based unit test in `hardening.rs` (a same-uid parent can `read_link` a
child's `/proc/<pid>/root` iff the child is dumpable; deny-half is unprivileged-only — root holds
`CAP_SYS_PTRACE`). HW sign-off: `/proc/<pid>/limits` core size 0, `kill -SEGV` -> no core, vs an
unhardened control.

### AES-GCM AAD — finalise all header fields before sealing
When AAD binds a plaintext header to the encrypted body, every mutable header field must be set
**before** `header_aad()` runs. Mutating a `SealedVault` header field after sealing (e.g.
`sealed.alias = Some(...)`) computes the tag over the wrong AAD — fails only at *open* time with
an opaque auth error. Fix: pass all header fields as constructor args to `seal_vault(...)`. The
only legitimate post-seal mutation is `reseal_vault_body` (re-derives nonce + ciphertext under
the current header).

### Linux dirs — wrap path_provider, don't reimplement it
A Wayland tester errored `file-not-found` because `~/.local/share` didn't exist. The tempting fix
(compute the data dir from XDG vars ourselves) is a **data-loss trap**: `path_provider_linux`
derives the dir suffix from the running GTK app's id (`g_get_prgname` -> `app.gabbro.gabbro`) over
FFI at runtime, not from the binary name (`gabbro`). Reimplementing risks a *different* dir ->
registry reads empty -> looks exactly like the brick. Safe shape: **wrap, don't replace** — keep
calling `getApplicationSupportDirectory()` as the primary resolver; only on a thrown exception
fall back to an XDG path mirroring path_provider's own precedence (existing app-id dir ->
existing legacy exe-name dir -> else create app-id dir). The app-id constant is consulted only
when FFI is unavailable (never on a normal machine).
**XDG != display server:** `XDG_DATA_HOME`/`XDG_CONFIG_HOME` say *where files live*, independent
of X11/Wayland — there is no "Wayland data path." Config asymmetry is deliberate: data honours
`XDG_DATA_HOME` (path_provider always did) but config honours `XDG_CONFIG_HOME` *only* as a
fallback when `HOME` is unset — because the old config code ignored it, so newly honouring it
would *move* the registry for anyone who has it set.

### file_picker on Linux is a DBus-portal client — guard it or it crashes in a sandbox
A Debian/Wayland tester's app threw unhandled `SocketException: ... /run/user/1000/bus` from
`FilePicker.saveFile`. On Linux `file_picker` calls `org.freedesktop.portal.FileChooser` over the
DBus *session* bus; in a hand-rolled bubblewrap sandbox the bus socket isn't bound -> connect
fails -> exception propagates. The packaging cure (bind the bus + a portal backend, in
`BUILD_AND_RELEASE.md`) can't be relied on per tester, so **the app must not crash regardless.**
Pattern: `lib/safe_file_picker.dart` wraps every picker call; `runPicker(op)` passes results
through (incl. `null` = cancelled) but converts a thrown `Exception` to typed
`FilePickerUnavailable`; the call site catches it and shows `showPickerUnavailable(context,
{hasManualEntry})`. Two messages: flows with an editable path field say "type/paste the path";
picker-only flows say the portal is unreachable. Wrap at the call site for *pure* pickers; wrap
*inside* the seam only when it bundles more than picking (e.g. unlock's `onRestoreFromFile` picks
AND restores).
**Dart gotcha:** a `final` local assigned inside a `try` does NOT type-promote to non-null inside
a later closure even after an `if (x == null) return;` guard. Fix: use `x!` in the closure, or
bind `final y = x;` after the guard.

### i18n — never confirm a destructive action by matching free text the user types
"Type DELETE to confirm" is English-only; translating the word, or "type the vault name", still
rely on string equality against typed text — and Dart's `==` compares UTF-16 code units with no
Unicode normalizer, so NFC-vs-NFD (Hangul, accented Latin) or full-/half-width IME output fails
to match with no explanation. Use a gate needing no text match: an "I understand..." checkbox or
hold-to-delete. Rule: don't gate on `typed == expected` for locale-dependent input.

### Privacy — a UI toggle is only as strong as the storage under it (ADR-014)
`show_vault_list` (default OFF) aimed at coercion-resistance, but the registry it hid
(`~/.config/gabbro/vaults.jsonc`) is **plaintext**, listing every alias + path. So it only hid
vaults from someone who *merely opened the app*, never from the adversary who reads the file. We
removed it (login always lists vaults). A real hidden-vault capability needs *encrypting the
registry* — a storage change, not a UI flag. Rule: before adding a privacy control, ask what an
attacker who can read the underlying file already sees; if the toggle doesn't change that, it's
theatre.

### Holding a mutex across a slow op causes deadlock
`Mutex::lock()` holds the lock until the `MutexGuard` drops. Calling a slow fn (e.g. `save_vault()`
running Argon2id) while holding it blocks every other thread on that mutex. Fix: clone what you
need out of the guarded region, drop the guard (close the block), then call the slow fn. Surfaced
as an apparent freeze navigating back from `CreateEntryScreen` mid-save (`list_entry_summaries`
blocked on the mutex `session_create_entry` held across ~20s debug Argon2id).

---

## Gabbro crypto stack

### Hybrid lock/unlock flow (VERSION 6+)
```text
SETUP: passphrase+salt -> Argon2id -> 96 bytes
 [0..32]  -> X25519 static private (clamped)
 [32..64] -> d  ML-KEM.KeyGen(d,z) -> ML-KEM-1024 keypair   (FIPS 203 7.1)
 [64..96] -> z
LOCK:  ML-KEM encapsulate -> ct + ssA; X25519 ephemeral -> eph_pub + ssB;
       HKDF(hkdf_salt, ssA||ssB, "gabbro-hybrid-kex-v1") -> intermediate_key;
       AES-256-GCM(intermediate_key, plaintext, AAD=header_aad()) -> ct + nonce   (VERSION 7 AAD)
UNLOCK: re-derive 96 bytes -> same keypairs; ML-KEM decapsulate + X25519 -> ssA, ssB;
       HKDF -> intermediate_key; AES-256-GCM decrypt.
```
The version byte selects the path at open (`ml_kem_keypair_for_version`). Legacy VERSION <= 5
seeded `StdRng` from bytes[32..64] (`from_kdf_output_legacy`, retained read-only); VERSION 6+
feeds d/z directly via `MlKem1024::generate_deterministic(d,z)` (`ml-kem` >= 0.2.3 `deterministic`
feature) — FIPS 203 7.1-conformant, no bytes discarded. The F-02 audit found the old doc-comment
claimed both 32-byte halves were used but only the first 32 were consumed.

### VERSION 4 — `wrapping_key` / `passphrase_blob` (decouple key_blobs from the passphrase)
Problem (v3): `key_blob_i = AES-GCM(vault_key_master, combine_yubikey(intermediate_key, hmac_i,
salt_i))`; `intermediate_key` is passphrase-derived, so changing the passphrase invalidates every
blob -> N YubiKey taps to re-seal. Bad UX.
Solution: a random 32-byte **`wrapping_key`** made once at creation, never changed. `key_blob_i`
now uses `wrapping_key` instead of `intermediate_key`, so it's stable. **`passphrase_blob`** =
`nonce(12) || AES-GCM(wrapping_key under intermediate_key)(48)` = 60 bytes, stored after the
YubiKey records. Changing the passphrase only re-encrypts `passphrase_blob` — one write, zero taps.
Unlock (multikey): derive `intermediate_key`; decrypt `passphrase_blob` -> `wrapping_key` (wrong
passphrase = auth fail here); CTAP2 with any one credential -> `hmac_i`; `combine_yubikey(
wrapping_key, hmac_i, salt_i)` -> decrypt `key_blob_i` -> `vault_key_master` -> body.
Passphrase-only vault: `passphrase_blob` empty, body encrypted directly under `intermediate_key`
(v2-compatible). File format: after the YubiKey records, before the body length — `pb_len` (u16
BE; 0=passphrase-only, 60=multikey) then `passphrase_blob`. `VERSION_MIN_READABLE` stays 2; v3
vaults read as pb_len=0. HW-validated session 16 (2026-05-22): Linux + Android USB + Android NFC.

### passphrase_blob is a passphrase oracle in YubiKey vaults
An attacker with the file can verify a candidate passphrase by checking AES-GCM auth of
`passphrase_blob` — no YubiKey. The body (note) still needs the YubiKey HMAC-secret. With a
256-char random passphrase the oracle is useless in practice, but document it. The YubiKey layer
is a *second* HKDF pass (`HKDF(yubikey_salt, intermediate_key || hmac_secret, "gabbro-yubikey-v1")`),
independent of the hybrid-KEM combiner.

### Random session key vs passphrase-derived key
The body is encrypted with a random session key; the passphrase derives keypairs that
*encapsulate* it. So changing the passphrase only re-runs encapsulation — the body needn't be
re-encrypted. Standard pattern in encrypted storage.

### Argon2id benchmarking
Benchmark on target hardware, not from recommendations. Target 0.5-1.0s. On a 2011 desktop
m=65536/t=3/p=4 = 84ms (too fast); t=25 = 667ms (good). Tool: `cargo run --bin bench_kdf --release`.
Source: OWASP Password Storage cheat-sheet.

---

## Android / Kotlin platform

### yubikit-android 3.1.0 — FIDO2 hmac-secret API (confirmed by `javap`, don't guess)
Package names/signatures change across yubikit majors. Key classes: `fido.client.Ctap2Client`
(high-level WebAuthn), `fido.ctap.Ctap2Session` (raw CTAP2), `fido.client.extensions.HmacSecretExtension`,
`fido.webauthn.*`. Gotchas:
- `ClientError.getErrorCode(): Code` (Kotlin `e.errorCode`), not `.code`.
- `getClientExtensionResults()` is nullable — safe-call.
- `MultipleAssertionsAvailable extends Throwable` (not Exception) — catch explicitly before the
  general handler.
- `PublicKeyCredentialUserEntity(name, id, displayName)` — name before id.
- Offline RP (no WebAuthn server): pass `ClientDataProvider.fromHash(randomBytes)` as the first
  arg to make/get; the 32-byte hash goes as `clientDataHash`; the `challenge` field is ignored.
- hmac-secret keys — reg: `Extensions.fromMap(mapOf("hmacCreateSecret" to true))`; assertion in:
  `mapOf("hmacGetSecret" to mapOf("salt1" to base64url_salt))`; out:
  `extensionMap["hmac-secret"]["output1"] as ByteArray`.

### Use `Ctap2Session` (raw CTAP2), not `Ctap2Client`, for native apps
`Ctap2Client` enforces WebAuthn domain validation on the RP ID and rejects `"app.gabbro.gabbro"`
(not a PSL eTLD+1). `Ctap2Session` treats the RP ID as an arbitrary string — correct for native
FIDO2.

### USB FIDO2 needs `UsbFidoConnection`, not `SmartCardConnection`
YubiKey USB = HID (FIDO2) + CCID (PIV/OATH). `UsbFidoConnection` (HID, implements `FidoConnection`)
opens a FIDO2 session; `SmartCardConnection` (CCID) cannot.
`device.requestConnection(UsbFidoConnection::class.java) { ... }`.

### hmac-secret key agreement is separate from PIN UV auth
Two distinct key agreements: `clientPin.getPinToken` (PIN token used to sign `clientDataHash` —
proves PIN) and `clientPin.getSharedSecret` (platform key + shared secret to encrypt the salt and
decrypt the output). Don't confuse the secrets. `getSharedSecret()` returns
`Pair(platformKey, sharedSecret)`; encrypt+authenticate the salt with `sharedSecret`, send
`platformKey`, decrypt output with `sharedSecret`.

### CTAP2.1 two-touch: `up=false` is ignored unless the token carries the UP flag (YubiKey 5.4.x)
Goal: vault creation does `makeCredential` (touch) then `getAssertions`+hmac-secret reusing that
touch. CTAP2 `up=false` only works if the pinUvAuthToken has the UP flag, set only when the token
was issued alongside a physical touch (a UV flow). On CTAP2.1, yubikit routes `getPinToken` to
`getPinUvAuthTokenUsingPinWithPermissions` (PIN-only) -> no UP flag -> YubiKey 5.4.3 enforces a
second touch -> times out `CTAP2_ERR_ACTION_TIMEOUT (0x3a)`. Both `up=false` and a combined
`MC|GA` permission failed. Paths forward: (A, chosen) accept two touches + clear UI; (B) a
UV-bearing token; (C) split register from hmac retrieval. Related Flutter bug: the 30s foreground
lock timer fired mid-CTAP2, disposing `OnboardingScreen` -> `Null check` crash in `_createVault`'s
finally. Fixes: `_lock()` bails if `widget.vaultPath` doesn't exist yet; `if (mounted)` guards on
every setState in catch/finally.

### YubiKey NFC — suppress the NDEF browser-opening bug in-app
Activating NFC opened a browser to `my.yubico.com` (the YubiKey broadcasts OTP slot 1 as an NDEF
URI; Chrome wins `NDEF_DISCOVERED` for https). yubikit's `startNfcDiscovery` calls
`enableReaderMode` which suspends foreground dispatch; `stopNfcDiscovery`'s `disableReaderMode`
does NOT re-enable it -> a window where NDEF reaches the browser. Fix (app-side, no `ykman`):
`NfcConfiguration().skipNdefCheck(true)` (sets `FLAG_READER_SKIP_NDEF_CHECK`), and re-arm
`enableForegroundDispatch` in `stopDiscovery("nfc")` right after `stopNfcDiscovery` so stray NDEF
intents go to `onNewIntent` (dropped). Disabling OTP-over-NFC via `ykman` is optional; real-world
breakage risk is very low (only legacy Yubico-OTP-over-NFC-specifically services).
[[feedback_nfc_reader_mode]]

### Kotlin `object` initialisers run on first access — defer Android APIs with `by lazy`
A Kotlin `object` singleton's property initialisers run on first member access; if they call
Android-only code (`Handler(Looper.getMainLooper())`) they crash JVM unit tests. Use
`by lazy { ... }` to defer to runtime. Same for `SensorManager`, `NotificationManager`, etc.

### AndroidKeyStore + BiometricPrompt (CryptoObject)
Generate a key in AndroidKeyStore with `setUserAuthenticationRequired(true)` +
`setInvalidatedByBiometricEnrollment(true)`; make a `Cipher` (ENCRYPT for enrol, DECRYPT with the
stored IV for auth); pass it as `CryptoObject` to `BiometricPrompt.authenticate()`; in
`onAuthenticationSucceeded` call `.doFinal()`. Any newly-enrolled biometric throws
`KeyPermanentlyInvalidatedException` at `Cipher.init()` -> catch -> `unenroll()` -> report
`KEY_INVALIDATED`. Ciphertext+IV are stored as Base64 in plain `SharedPreferences` (safe —
useless without the Keystore key; `EncryptedSharedPreferences` would be redundant). **All
OS-enrolled biometrics work** (any fingerprint, face) — no API to restrict to one; disclose
upfront.

### Per-vault biometric enrollment scoping
Enrollment stores one passphrase. Scope it to `vaultPath`: store it with the ciphertext;
`isEnrolled(vaultPath)` checks the ciphertext exists AND the path matches; `authenticate` returns
`NOT_ENROLLED` on mismatch. Security settings must query `isEnrolled(vaultPath)` on load (not just
read `settings.biometricUnlock`) so the toggle reflects the open vault.

### `FlutterFragmentActivity` for BiometricPrompt
`FlutterActivity` doesn't extend `FragmentActivity`, which `BiometricPrompt` requires. Use
`class MainActivity : FlutterFragmentActivity()` — drop-in (extends AppCompatActivity ->
FragmentActivity); NFC/platform channels unaffected.

### `EXTRA_ASSIST_STRUCTURE` is not forwarded to autofill auth activities
The framework does NOT deliver `EXTRA_ASSIST_STRUCTURE` to the activity launched via a `Dataset`
auth `PendingIntent` (undocumented) -> `getParcelableExtra(...)` is null. Fix: pack everything the
auth activity needs (parsed `AutofillId` lists, web domain, package name) as explicit intent
extras in `onFillRequest()`.

### AutofillService field detection is not reliable — use all three signals in priority order
1. `autofillHints` (most reliable, often unset — PayPal sets none); 2. `inputType` bitmask
(catches most password fields; username fields often `VARIATION_NORMAL`); 3. `hint`/`idEntry`
keyword match (last resort). Bitwarden/1Password use all three. `webDomain` is null for native
apps — extract a token from the package name (`com.paypal.android.p2pmobile` -> `paypal`) and
substring-match vault URLs (approximate, can false-positive, but standard). A `System.loadLibrary()`
failure crashes the service silently and Android stops invoking it until re-enabled — verify the
`.so` name (`unzip -l app-release.apk | grep so`).

### Chromium browsers expose the HTML truth in `htmlInfo`, not in hints/inputType
Brave/Chromium set `inputType=0x0` on web fields and carry the real signal as HTML attributes
(`type`/`name`/`id`/`autocomplete`) — so web detection rides on `htmlInfo`. Read html `id` too
(`name="user"` won't keyword-match but `id="id_username"` does); and trust html name/id only when
an html `type` is present, else a `<form name="login">` container gets mis-classified as a field.

### `logcat` as a TDD proxy for untestable platform code
The autofill service + auth activity need a real device/OS session. Add `Log.d("GabbroAutofill",
...)` at each decision point, trigger on hardware, read logcat to see which branch fired, fix,
re-run. The log output is the "test result". A full structure dump kept behind `BuildConfig.DEBUG`
(compiled out of release) is the reusable form — pure formatter unit-tested, emission
device-verified. [[feedback_android_hardware_before_commit]]

### Robolectric for framework-dependent Kotlin helpers
Plain JVM tests hit `android.jar` stubs (`throw "Stub!"`), so helpers touching `android.net.Uri`,
`org.json`, `SharedPreferences` can't be unit-tested (they sat `@Ignore`d). Robolectric swaps in
real implementations. Setup: `testImplementation("org.robolectric:robolectric:4.13")`,
`testOptions{unitTests{isIncludeAndroidResources=true}}`, `src/test/resources/robolectric.properties`
`sdk=34` (4.13 ships android-all only to API 34; compileSdk is 36),
`@RunWith(RobolectricTestRunner::class)`, `Context` from `RuntimeEnvironment.getApplication()`,
service from `Robolectric.setupService(...)`. Reach private helpers via **`internal`** (not
reflection — string method names break on rename); `private->internal` moves no logic
(`:app:assembleDebug` clean). Robolectric does NOT back AndroidKeyStore
(`getInstance("AndroidKeyStore")` throws) — anything touching real key material stays `@Ignore`d;
don't wrap `deleteKey()` in try/catch just to pass a Robolectric test. These are *characterization*
tests pinning known weaknesses (naive last-two-labels eTLD+1; `parseSummariesJson` dropping a
whole batch on one bad record).

### Build environment
- **Java:** Gradle/Kotlin may fail `IllegalArgumentException: 26.0.1` on Java 26 (Kotlin 2.2.x
  can't parse it). Point Gradle at Android Studio's JBR 21:
  `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (machine-local,
  committed for single-dev).
- **AGP:** 8.9.1 confirmed with Flutter 3.41.9. <8.9.1 too old for core-ktx 1.17.0 / browser
  1.9.0; 8.11+ breaks Flutter's gradle plugin (`.compileSdkVersion!!.substring(8)` NPE; the
  confusing error message is the AGP or Java version string).
- **Platform-gate native deps:** `libfido2-sys` (links OpenSSL + host libfido2) is unavailable
  cross-compiling for Android. Gate in Cargo.toml `[target.'cfg(not(target_os="android"))'.dependencies]`
  and `#[cfg(not(target_os="android"))] pub mod fido;`. Android uses `yubikit-android` (Kotlin)
  instead — mutually exclusive by platform.
- **Alternate APK entry point:** `flutter build apk --release --target test/foo.dart` (the file
  must define `main()`); delete after, don't ship.

### Deployment / emulator
- `adb install <apk>`; `adb shell rm /data/data/app.gabbro.gabbro/files/gabbro.gabbro` (vault) or
  `adb shell pm clear app.gabbro.gabbro` (all data — preferred for onboarding tests). Vault path:
  `/data/data/<app-id>/files/`.
- Emulator on Arch needs `libbsd` (else `libbsd.so.0` load error) and `kvm` group. Prefer an
  **AOSP** system image (FOSS-aligned, de-Googled compat, no Play Services). Debug Argon2id ~20s
  on emulator (worse than desktop) — always `--release` for perf.
- Android 16 enforces edge-to-edge (no opt-out; `windowOptOutEdgeToEdgeEnforcement` ignored). When
  overriding one MediaQuery field use `MediaQuery.of(context).copyWith(...)`, not `MediaQueryData(...)`
  which zeroes all insets and breaks AppBar/FAB positioning.
- `FilePicker.saveFile()` is desktop-only (silently null on Android). Android export:
  `FilePicker.getDirectoryPath()` (SAF), append the filename; keep the Export button disabled
  until a dir is chosen; use a distinct icon (`Icons.folder`). [[reference_android_emulator_testing]]
- Storage: declare no storage permissions. App-private (`getApplicationDocumentsDirectory`) needs
  none; user paths go via SAF/file_picker (URI-scoped). Avoid `MANAGE_EXTERNAL_STORAGE`. Android
  FDE has been enforced since Android 10.
- Android `<queries>` package visibility (Android 11+): without an `ACTION_VIEW` http/https intent
  in `<queries>`, `canLaunchUrl` silently returns false. Drop the `canLaunchUrl` guard, call
  `launchUrl` and check the returned bool (show a snackbar on failure).

---

## Flutter / Dart

### App lifecycle & auto-lock
`WidgetsBindingObserver` mixin: register in `initState`, deregister in `dispose`, override
`didChangeAppLifecycleState`. The same action fires different states per platform: Android
focus-loss = `inactive` (transient — ignore), invisible = `hidden` -> `paused`; a Linux tiling WM
workspace-switch fires only `inactive`; a floating WM `inactive` -> `hidden`. X11/Wayland are
identical via the GTK embedder. Two complementary lock strategies: **timestamp** (record
`_backgroundedAt` on background, compare on `resumed` — robust to Android Doze suspending `Timer`;
`??=` keeps the earliest, as Android fires hidden before paused) and **timer**
(`Timer(_backgroundDuration, _lock)` on desktop `inactive`, because a tiling-WM app stays visible
while unfocused and `resumed` won't fire — the process is still running so the Timer is reliable).
`_lock()` cancels both + nulls `_backgroundedAt`. Navigate from outside the tree (timer callback)
via `MaterialApp.navigatorKey` + `pushAndRemoveUntil(..., (_) => false)`. Reset inactivity on
input by wrapping MaterialApp in a `Listener` (`HitTestBehavior.translucent`, `onPointerDown`) —
NOT `GestureDetector`/`PanGestureRecognizer`, which wins the gesture arena against text-cursor
drag handles and breaks text selection; also `HardwareKeyboard.instance.addHandler` for keys.
Test seam: `GabbroApp(clock: () => now)` (fakeAsync/pump controls `Timer` but NOT `DateTime.now()`).
Lifecycle test caveat: `hidden`/`paused`/`detached` disable frames, so after a background lock you
must send `resumed` then `pump()` then `pump(500ms)` to render queued navigation; `inactive`
doesn't disable frames.

### FFI testability — inject the bridge call as a parameter
Widget tests run in a pure Dart VM with no Rust binary; any widget calling a bridge fn directly
crashes. Make the call an optional ctor parameter defaulting to a **top-level** fn that calls the
real FFI (Dart requires top-level defaults, not instance methods). Tests pass stubs. Applies to
every bridge call including `estimateEntropy` (fires on every keystroke). [[feedback_dart_test_helpers]]
Same for platform branches: expose `isAndroid` as a ctor param defaulting to `Platform.isAndroid`
(the ctor must be non-const) so Android-only UI is testable on Linux.
[[reference_platform_channel_test_seam]] Also `tester.runAsync()` for real OS I/O in widget tests
(`File.create(recursive:true)`) — `pump()` drives the virtual clock but not platform I/O, so it
hangs otherwise.

### Global test sandbox — `flutter_test_config.dart`
Tests must never touch real on-disk state (config `~/.config/gabbro`, the data dir).
`Platform.environment` is immutable in tests, so: (1) `lib/app_paths.dart` `GabbroPaths` owns both
dirs with a `@visibleForTesting static String? sandboxRoot`; every call site routes through it.
(2) `test/flutter_test_config.dart` is a magic filename — its `testExecutable(testMain)` wraps
EVERY test in `test/`; set `sandboxRoot` to a temp dir before `testMain()`, delete after. Per-test
isolation points `sandboxRoot` at its own temp in `setUp` and **restores the previous global value
(not null)** in `tearDown`. It doesn't govern `integration_test/` (different harness — those use
explicit temp paths). Also a latent-bug detector: any test secretly reading a real file now fails
against the empty sandbox.

### Test the *decision*, not the FFI-on-mount UI
A nav test driving post-delete routing **hung forever**: routed-to screens make bridge calls on
mount (`UnlockScreen._probeVault` -> `onVaultIsReadable`, `deleteVaultFiles`); under `flutter test`
there's no Rust isolate so the futures never complete. Moving it to `integration_test/`
(`flutter drive --profile`) passed standalone but **crashed under gate load**
(`DriverError: Service has disappeared` + an OpenGL-frame timeout — pumping the full UI through the
headless GL driver is fragile). Robust answer: **extract the pure decision**
(`postDeleteRoute(wasActive, hasRemaining)` -> screen enum) and unit-test that; leave the thin
wiring to widget tests + a hardware pass. (The `flutter_test_config.dart` sandbox does NOT apply
under `flutter drive` — set `sandboxRoot` in `setUp` there.)

### integration_test on Linux must run profile, not debug
`flutter test integration_test/foo -d linux` builds Rust in **debug** -> production Argon2id blows
the 30s timeout (`TimeoutException`, not a logic failure). `flutter test --release` isn't a flag;
`flutter drive --release` is rejected for non-web. Working path:
`flutter drive --driver=test_driver/integration_test.dart --target=integration_test/foo_test.dart
-d linux --profile` (optimized Rust, attachable driver). Give vault-creating tests
`timeout: Timeout(Duration(minutes: 3))`. Needs a live `DISPLAY` (real GTK window, no xvfb). A
benign "integration_test plugin not detected" warning appears but results ARE captured. Scope
Phase 1 to passphrase-only (no YubiKey).

### Dialog & controller lifecycle
- `StatefulBuilder` gives dialog-local `setState`; declare the mutable var **outside** the
  `builder` closure (declared inside, it resets every rebuild).
- Don't dispose a `TextEditingController` right after `showDialog` returns — the dismiss animation
  rebuilds the `TextFormField` against the disposed controller (assertion cascade). Declare the
  controller inside the dialog's `builder` and capture the value via `onChanged` into a local that
  outlives the dialog (GC'd after the animation).
- `pumpAndSettle` times out when a dialog `TextField` cursor is still blinking (the periodic
  `AnimationController` never idles), e.g. dismissing one dialog while opening another. Use explicit
  `pump(duration)` steps for multi-dialog transitions.
- `showDialog<T>` / `showModalBottomSheet<T>` return `Future<T?>`; the value is what
  `Navigator.pop(value)` passes; `null` = dismissed — always guard. Use an enum to distinguish
  actions (`pop(_FailureAction.edit)` vs `.skip`).

### l10n
- Two codegen steps after adding a bridge fn: `flutter_rust_bridge_codegen generate` (else Dart
  "Method not found") AND `flutter gen-l10n` (else "getter X isn't defined" for new ARB keys).
- A new UI language = 4 sites: `app_<code>.arb`, the `LanguageChoice` enum (`settings.dart`), the
  label arm (`language_screen.dart`), and the easy-to-miss `_languageChoiceToLanguage()`
  (`generator_widget.dart`) — without the last, the passphrase generator silently falls back to
  English. Caught by the 31-case test in `generator_widget_test.dart`. [[feedback_showlangfallback_picker]]
- `GlobalMaterialLocalizations.delegate.isSupported` is false for locales outside Flutter's set
  (yo, nn) -> Material widgets crash on null. Wrap the delegate so unsupported locales load English
  Material strings (custom `LocalizationsDelegate`: `isSupported` always true, `load` falls back to
  `en`).
- Store stable English identifiers (card status `'active'`), translate only at display via a
  `switch` helper with a pass-through default — never store translated strings (a locale switch
  would corrupt data). In dropdowns separate the stored value from the display label.
- Dropping `const` when adopting ARB: `const InputDecoration(labelText:'Title')` ->
  `InputDecoration(labelText: l.fieldTitle)` (`l` is runtime). Mechanical across validators/
  tooltips/hints.

### Stale state & re-fetch after mutation
- After any bridge save the Flutter DTO is stale (missing Rust-stamped `updated_at`,
  `previous_password`) — call `getEntry(id:)` before navigating/displaying, else "Saved Unknown"
  timestamps.
- Any widget caching a vault entry ID must reset it on vault-mutating events (import/delete/
  passphrase change). `TabletVaultLayout._selectedEntryId` not reset on `onRefresh()` after import
  -> `getEntry()` with a stale id -> Rust `Err` -> silent empty-state + log-spam (no visible crash).
- Never call a throwing bridge fn synchronously in `build()`. `tablet_vault_layout`'s sync
  `getEntry(id)` in `build()` throws when the entry is gone -> an endless
  `DiagnosticsProperty<void>` storm masking the primary error; any app-wide `setState` re-runs that
  build, so an unrelated action "causes" the crash. Guard: `try {...} catch { return emptyState; }`
  + clear stale selection in a post-frame callback; prefer `FutureBuilder` for async fetches.
- Pushed routes get props frozen at push time; a parent `setState` doesn't propagate. For props
  that can change while on the stack (a vault alias renamed elsewhere), read from a shared ancestor
  at `build()`: `GabbroApp.maybeOf(context)?.registry.lastUsed?.alias ?? widget.vaultAlias`.

### Lists, scrolling, layout
- `ListView.builder` is lazy -> a `GlobalKey` on an off-screen header has null context;
  "scroll to index" needs `scrollable_positioned_list` (`ItemScrollController.scrollTo(index:)`).
- `Row` (not `Stack`) for list + index bar (no overlapping tap targets); `HitTestBehavior.opaque`
  on the bar's `GestureDetector` to catch taps in the gaps; `LayoutBuilder` to window the letter
  list to fit; `ScrollConfiguration(...scrollbars:false)` to drop the redundant scrollbar.
- `ScrollController` exposes `position.{pixels,maxScrollExtent,viewportDimension}`; add/remove the
  listener in initState/dispose; read extents in `addPostFrameCallback` (not in `build`); use a
  threshold (>80) to avoid rounding artifacts; `animateTo` for smooth scroll. A `ScrollController`
  listener fires only on scroll — for geometry changes (rotation) use
  `NotificationListener<ScrollMetricsNotification>` (return false to bubble).
- `Wrap` (not `Row`+`Expanded`) for button groups so labels stay legible at large text scale.
- `SafeArea` around scrollable bodies for system-UI insets; `mainAxisSize: MainAxisSize.min` on a
  Column inside `SingleChildScrollView` to enable scroll; FAB clearance =
  `padding: EdgeInsets.only(bottom: 80)`.

### Misc Flutter/Dart
- `usize` Rust return -> Dart `BigInt`, not `int` — `.toInt()` at the call site.
- `getEntry` is synchronous (a non-async Rust fn) — `await` on it is a compile error. Check the
  Rust signature: `async fn` -> Future, `fn` -> direct value.
- `Clipboard.setData(...)` is async; `await` then check `mounted` before `ScaffoldMessenger`.
  Auto-clear only reaches the system clipboard — clipboard-history managers (Klipper, Gboard,
  Samsung) keep their own ring buffer we can't touch; best-effort, document honestly. Autofill
  bypasses the clipboard entirely (a security win). Copy always uses the real value, never the
  bullet placeholder.
- `listEquals` (package:flutter/foundation) for list value equality — Dart `==` on lists is
  reference equality (unlike Python). Needed for change-detection of custom fields.
- Closure capture in list builders: compute per-tap values *inside* the builder callback, not
  outside (captured once at build time).
- DI for screens uses top-level `_default*` fns as defaults; `find.descendant` to scope finders
  when text appears in both a field and a tile.
- Long press on Linux desktop = hold left mouse (right button doesn't trigger `onLongPress`).
- `String?` (Rust `Option<String>`) needs a null-check before use (`if (e.f != null) use(e.f!)`);
  generated sealed classes give an exhaustive `switch` (`VaultEntryData_Login(:final field0)`).
- `createEntry` (vault_bridge) persists to session+disk; `createLoginEntry` (vault) just builds a
  standalone DTO. Use `createEntry` to persist. `prefill` (raw `Map`, failed import) vs `existing`
  (valid DTO, edit) on a form screen; `existing` wins if both set.
- `ValueKey((a,b))` (a record tuple) to rebuild a child when either of two parent values changes.
- `library_private_types_in_public_api`: expose a public abstract class (`GabbroAppState`) that the
  private `_State` implements; `of()`/`maybeOf()` return the public type.
- Throw `PlatformException(code:...)` from Linux hardware paths so a generic catch can code-dispatch
  (`NO_FIDO2_DEVICE`, `TRANSPORT_ERROR`) instead of hitting the generic `_` arm.
- Bulk-op accumulation: track side-effect counts in a local and return it (e.g.
  `showImportFailuresDialog` returns `Future<int>` of entries saved).

### TDD philosophy
Tests are specs of intended behaviour. When a design decision changes the intended behaviour
(e.g. full-screen push nav replacing in-place edit-mode dimming), rewrite the test to match the
real architecture and delete the dead code — don't force it through or leave it skipped forever.

---

## FIDO2 (Linux / libfido2)

- libfido2 speaks CTAP2 over USB HID; any FIDO2 device with the **hmac-secret** extension works on
  the Linux path with no code changes: YubiKey 5 (USB+NFC), SoloKeys Solo 2, Nitrokey FIDO2.
  Google Titan has no hmac-secret -> fails at `fido_dev_make_cred` (surfaces via `fido_register`'s
  `Result<_, String>`). `fido_list_devices()` auto-enumerates all USB HID FIDO2 devices.
- Hardware-gated Rust tests: each FIDO2 op needs a physical tap. Add
  `println!(">>> TAP ... (tap n/N)")` before each presence-blocking call + run `--nocapture`;
  `--test-threads=1` (tests are `#[serial]` and share `/dev/hidraw5`).
  `GABBRO_TEST_PIN=<pin> cargo test fido -- --ignored --test-threads=1 --nocapture`. Tap counts:
  register=1, deterministic-hmac=3, total 4. [[reference_yubikey_test_hardware]]

---

## Rust quick reference (Python -> Rust)

One-liners for the learner; the Gabbro-specific Rust lessons follow.

- **Ownership/move:** assigning transfers ownership; `.clone()` for an explicit copy; move the
  original into its last use to avoid a needless clone. `let`/`mut`: immutable by default, `mut`
  opts in.
- **`Option<T>`** (`Some`/`None`, no null) and **`Result<T,E>`** (`Ok`/`Err`) force the caller to
  handle both; the bridge maps `Err` -> a Dart exception. Early exits via `return Err(...)`; the
  final bare expression (no `;`) is the return value.
- **Visibility:** private by default; `pub` to expose (struct fields need their own `pub`);
  `pub(crate)` = crate-internal (compiler-enforced `_`).
- **`fn`/`pub fn`:** types mandatory, `->` for return. **`impl`:** no-`self` = associated fn
  (`Type::f()`), `&self` = method. **`new() -> Result`** is the constructor/validation idiom (no
  `__init__`).
- **`struct`** ~= dataclass (fixed fields, compile-time). **`enum`** = closed variant set used in
  `match` (exhaustive — the compiler forces all arms). Composition over inheritance: embed
  `pub meta: EntryMeta`, reach via `entry.meta.id`.
- **Types:** `Vec<u8>` = bytes; `HashMap<K,V>` = dict (`into_values()` drops keys);
  `String::from`, `Vec::new`, `::` path separator (`.` for instance methods). DTO = a plain
  bridge-crossing struct.
- **Closures** `|x| ...` ~= lambda; iterators are lazy/composable (`.chars().filter(...).count()`);
  `vec.retain(|x| keep)` filters in place. `chars()` iterates Unicode scalars; Unicode-safe
  capitalisation = `.next().to_uppercase()` (returns a String) + remainder.
- **`use`:** like `from x import y`; sometimes needed only to bring a **trait** into scope to
  unlock its methods (`use rand::Rng` for `.gen_range()`; `EncodedSizeUser` for `.as_bytes()`) — if
  a trait import looks unused but removing it breaks compilation, keep it with
  `#[allow(unused_imports)]` + a comment.
- **Macros `name!()`** run at compile time (variadic, type-generic, can see source) — `!` means
  macro, not negation. `format!`, `assert!`/`assert_eq!`/`assert_ne!` (print values; optional
  `, "msg {}", v`), `vec!`, `panic!`.
- **`*value`** dereferences a wrapper (ml-kem returns `Array<u8,N>` -> `(*secret).try_into()` ->
  `[u8;32]`). **`to_be_bytes()`/`from_be_bytes()`** = big-endian (network/file order, a matched
  pair). `include_str!` embeds a file at compile time as `&'static str`. **`||` in crypto specs** =
  concatenation, not OR.
- **Derives/attributes:** `#[derive(Debug, Clone, PartialEq)]` (Debug for `{:?}`/test output;
  PartialEq for `assert_eq!`/`==`, every field must also impl it). `#[cfg(test)]` (compile only in
  test), `#[test]`, `#[ignore]` (skip unless `-- --ignored`),
  `#[flutter_rust_bridge::frb(sync|ignore|init)]`. Doc comments: `///` (item, ~= docstring), `//!`
  (enclosing module).
- **Tests:** `#[cfg(test)] mod tests { use super::*; ... }`; `#[serial]` (serial_test dev-dep) for
  tests sharing a process-wide static like `VAULT_SESSION` — a Mutex stops data races but not
  logical ones. Struct-update `..default_config()` + a `default_config()` fixture to override one
  field; test randomness with large samples (200 chars) so all pools are hit.
- **Zeroize:** `Zeroizing<T>` zeroes the inner value on drop (RAII via Drop) — it narrows the RAM
  window, doesn't eliminate it (swap/hibernation/cold-boot remain; FDE is a prerequisite).
  `ZeroizeOnDrop` implements Drop, so you can't move a field out (E0509) — change conversion fns to
  take `&T` and `.clone()` fields, or use `ref mut` in match arms.
- **Generics noise:** alias complex types (`type YubikeyTriple = Option<(Zeroizing<Vec<u8>>,
  Vec<u8>, [u8;32])>;`) to silence `clippy::type_complexity`.
- **Binary serialisation with a cursor:** length-check `data.len() >= pos+n`, slice, convert
  (`u32::from_be_bytes`, `try_into().unwrap()` is safe after the check), advance `pos`; length-prefix
  variable fields. Same pattern as PNG/ZIP.

---

## Rust ↔ bridge (flutter_rust_bridge)

- `flutter_rust_bridge_codegen generate` (from `gabbro/`) regenerates the Dart stubs + `frb_generated*`
  after any public API change — never edit generated files; stale ones cause `cannot find function
  ...` build errors. If codegen hangs 30min+, `dart run build_runner clean` then re-run.
- snake_case -> camelCase automatically. `#[frb(sync)]` -> a plain Dart fn (fast in-memory only;
  blocks the UI); `async fn` -> a Dart `Future`/`await` (required for Argon2id ~667ms).
- Bridge-friendly types only: `Path` -> `String`, `&[u8]` -> `Vec<u8>`, internal enums/structs ->
  DTOs (`LoginEntryData` etc., bridge-friendly fields only; build the internal type then convert to
  the DTO for the return). `#[frb(ignore)]` skips internal fns. Wrapper pattern: pure logic in
  `vault.rs`, bridge-friendly wrappers in `api/vault_bridge.rs`. Rust enums -> Dart `sealed class`
  (exhaustive switch) via freezed + build_runner. `simple.rs` (`greet` + `init_app`) — leave alone.
- Tuple return `(Vec<Success>, Vec<Failure>)` for per-item partial success; `Result` only for
  catastrophic failure. `map_err` transforms the error arm. Map source field names to canonical
  keys at the boundary (`extract_raw_fields`) so Flutter only ever sees Gabbro keys.
- **Domain-model blast radius:** adding a field touches the struct, the validated ctor, all ctor
  call sites, struct literals (tests + `mask_entry`), the DTO, the DTO-conversion fn, the bridge
  conversion, and the regenerated `frb_generated.rs`. After a signature change, manually patch
  `frb_generated.rs` with a placeholder to unblock `cargo test`, then regenerate — never leave the
  manual patch. **grep all of rust/src after a signature change** — `cargo build` misses test-only
  call sites (e.g. `vault/io.rs`). [[feedback_bulk_replace_misses]]
- **`#[serde(default)]`** on every new Vec/Option field of a persisted struct. [[feedback_serde_default]]

---

## Session model & memory security

- Rust-owned state across stateless bridge calls: `static VAULT_SESSION:
  Lazy<Mutex<Option<VaultSession>>>` (once_cell). `Lazy` = init on first access, `Mutex` = one
  thread (Flutter may call from multiple isolates), `Some`/`None` = unlocked/locked.
- `VaultSession` stores the passphrase (`Vec<u8>`) deliberately: every mutating call re-seals
  (Argon2id+ML-KEM+AES) and `seal_vault` needs it; re-supplying it per call across the bridge is
  worse exposure. The window is bounded by auto-lock + `lock_vault` (which zeroizes).
  `session_change_passphrase` updates the stored copy after re-sealing.
- `zeroize` on lock: `s.passphrase.zeroize(); s.entries.clear();` — `Vec<u8>` impls `Zeroize`
  (volatile writes + memory fence; overwriting with random is no better and slower). `.clear()`
  drops nested Strings promptly but doesn't guarantee byte-overwrite; full coverage needs deriving
  Zeroize on every `entry.rs` struct (backlog). Dart can't zeroize (GC, string interning) — the
  session model limits Dart exposure: summaries for lists, one full entry on demand, never the
  whole vault.
- Lazy loading is the default: `list_entry_summaries()` (id/type/title/folder/tags/favourite — no
  secrets) for lists, `get_entry(id)` for detail, `create_entry`/`update_entry` to persist.
- Bulk ops: mutate the in-memory session N times without saving (`session_add_entry_no_save`/
  `session_delete_entries_no_save`) then `session_save` once — one Argon2id+encrypt+write, not N.
- `do_save`/`extract_yubikey` pair: extract YubiKey material while the mutex is held, dispatch to
  `save_vault_with_yubikey` or `save_vault`; every save-calling fn becomes a one-liner. The
  hmac-secret is deterministic (same credential+salt -> same 32 bytes) so caching it for the
  session is safe (CRUD saves need no re-tap).

---

## Other Rust lessons

- **Importer UUID preservation:** thread the source UUID into `meta.id` (don't `Uuid::new_v4()`),
  or re-importing creates duplicates. The Bitwarden parser had this bug (`BwItem` didn't
  deserialize `id`). CSV is exempt (no stable identity -> fresh UUIDs are correct).
- **Format migration without a version bump:** shape-detect the decrypted JSON body — first
  non-whitespace byte `[` = legacy `Vec<VaultEntry>` (migrate `folder=="Personal"` -> `""`), `{` =
  new `VaultBody{folders,entries}`. Use only when additive and the shapes are unambiguous; else
  bump the version.
- **Expiry purge on unlock:** `purge_expired_history` (first step of `unlock_vault`) nulls expired
  `PreviousSecret` history; `is_expired` parses the ISO-8601 UTC string via `days_from_ymd`,
  `None` = keep-forever, unparseable = treated as not-expired (no silent loss).
- **Date arithmetic without chrono:** convert to days-since-epoch (handle leap years, `u64`
  years), add, convert back; keep the time-of-day by parsing only `[0..10]`. `is_leap` is defined
  once per module.
- **Masking boundary:** mask at the bridge only when Flutter never needs the plaintext.
  `MASKED_VALUE` = "********" (fixed length — the real length leaks search space). But
  `PreviousSecretData.value` is shown via a UI toggle, so pass `p.value.clone()` in plaintext; the
  UI handles obscuring.
- **SHA-256 hex:** a `hybrid_array`/`ml-kem` version conflict means `LowerHex` isn't impl'd for
  `sha2`'s `GenericArray` — `.into()` to `[u8;32]` then
  `bytes.iter().map(|b| format!("{:02x}",b)).collect()`.
- **Dependency version conflicts:** different versions of a shared dep (e.g. `rand_core` 0.6 vs
  0.10) make traits incompatible even if the APIs match — fix by *reducing* deps (removed
  `rand_chacha` for `StdRng`), not adding constraints.
- **Trait imports for method dispatch:** a method from a trait is only callable if the trait is in
  scope, even if you never name it (`EncodedSizeUser` for `.as_bytes()`). Keep "unused" but
  required imports with `#[allow(unused_imports)]` + a comment.
- **Cargo test output:** lib + each `src/bin/` + doc tests = three runners; binaries with no
  `#[test]` show "running 0 tests"; `required-features` binaries are skipped when the feature is off.
- **Debug vs release:** unoptimized Rust makes Argon2id ~20s vs ~667ms release — always `--release`
  for any perf/UI test, any platform; never tune Argon2id from debug timings.
- **Rustdoc:** bare 4-space-indented doc-comment code blocks are compiled as Rust — Unicode (`x`,
  subscripts) -> "unknown start of token". Fence with ` ```text `. Affects `cargo test --doc`.
- **BOM:** Excel CSV prepends `\u{FEFF}`; strip first:
  `input.strip_prefix('\u{FEFF}').unwrap_or(input)` (in `sniff_csv`/`import_csv`).
- **End-to-end tests catch boundary bugs** a crypto-only and a serialization-only test both miss
  (wrong header bytes -> a decryption error, not a deserialization error).
- **Wordlist curation:** filter frequency corpora (hermitdave/FrequencyWords, OpenSubtitles) with
  an **explicit per-language alphabet**, never `[a-z]` (admits q/w/x/y absent from Croatian/Latvian/
  Slovenian; but `y` IS valid in Lithuanian). Traps: missing letters (Croatian `đ` between d/e —
  zero occurrences is a red flag); aspell lists include derived foreign proper nouns; subtitle
  corpora have cross-language bleed (accepted — entropy comes from pool size). Audit after
  generation: every script letter appears somewhere; forbidden letters appear nowhere.
  [[feedback_wordlist_char_classes]]

---

## Concept reference

### Cryptography
- **PQC:** secure vs classical + quantum; NIST 2024 standards ML-KEM (KEM) + ML-DSA (signatures).
- **Argon2id:** slow, memory-hard KDF (passphrase -> key); attacker pays per-guess, user once.
- **AES-256-GCM:** symmetric body encryption + authentication (detects tampering).
- **ML-KEM (Kyber):** PQ key encapsulation (establishes a shared secret). **ML-DSA (Dilithium):**
  PQ signatures (prove identity). Independent problems — changing one doesn't touch the other.
- **Hybrid encryption:** classical + PQ together. Hybrid *key exchange* (ML-KEM+X25519) is
  reasonable (ephemeral keys compose cheaply); hybrid/composite *signatures* (ECDSA+ML-DSA,
  draft-ietf-lamps-pq-composite-sigs) are now the wrong tradeoff for new deployments — not used.
- **ML-DSA-44/65/87** = NIST levels 2/3/5 (~SHA-256 / AES-192 / AES-256); sigs ~2.4/3.3/4.6 KB.
  Gabbro targets ML-DSA-44 (level 2 is already beyond conservative for auth). NIST levels 1-5 =
  "how hard is the best known attack" (L1~=AES-128 ... L5~=AES-256).
- **YubiKey/FIDO2/WebAuthn stack:** YubiKey = hardware signer (key never leaves); FIDO2 = app<->key
  protocol; WebAuthn = the API (algorithm via `pubKeyCredParams`). **PQ gap:** YubiKey 5 (Apr 2026)
  does Ed25519/ECDSA, not ML-DSA — Gabbro v1 uses Ed25519 for FIDO2; the PQ claim rests on the
  *encryption* stack (ML-KEM+AES), not auth (ADR-005). Clean migration to ML-DSA-44 when HW supports it.
- **Kerckhoffs:** security from the key, not a hidden algorithm — the header can be plaintext (only
  parameters). **Salt** (per-user, unique, not secret — defeats rainbow tables) vs **nonce**
  (per-encryption, 12-byte for AES-GCM, must never repeat for a key, not secret).
- **SHA-256:** one-way 256-bit hash. **Detached hash file** (`vault.gabbro.sha256`): verify
  integrity with `sha256sum` without the app (checkable before opening; distinct from an embedded
  auth tag).
- **TOTP:** the 6-digit codes — deliberately excluded (keep PW manager and 2FA separate; YubiKey is
  stronger anyway).
- **Diceware/EFF:** random words from a list. EFF large = 7776 words (6^5, ~12.92 bits/word); ES/IT
  variants = 8192 (2^13, 13.00 bits). 4 words ~= 51.7 bits (practical minimum, enforced in
  `PassphraseConfig`); 6 words ~= 77.5 bits.
- **Entropy estimate (typed passwords):** detect char classes present, sum full pool sizes
  (conservative — never apply `exclude_ambiguous`, the estimator only sees the string);
  `entropy = length x log2(pool)`. See `entropy.rs`.

### Security model & architecture
- **Two layers:** at-rest vault encryption (protects a stolen file) + FIDO2/YubiKey app access
  (protects against unauthorized use) — independent (a safe inside a locked room).
- **3-2-1(+1) backup:** 3 copies, 2 media, 1 offsite (+1 immutable/air-gapped). Critical because
  the vault wipes after 10 failed attempts. The dev repo follows it (local + NAS + Synology offsite).
- **FDE prerequisite:** memory protections assume full-disk encryption (Android enforces since 10;
  Linux = the user's LUKS responsibility). FDE doesn't cover a device seized *unlocked* — that's
  what zeroize + auto-lock address (complementary).
- **Flutter:Rust :: frontend:backend** via flutter_rust_bridge (FFI = in-process, no network). UI
  in Flutter, security-critical in Rust. **`api/` vs `vault/`:** `api/` = the bridge boundary (only
  what Flutter calls); `vault/` = the internal domain model. Single source of truth for shared types
  (`SealedVault` lives once, in `file_format.rs`). Make invalid state unrepresentable (`CardEntry::new`
  rejects bad lengths). Enum variant names are internal — Dart maps to display text. Scaffold-first
  (accept the generator's layout, e.g. the crate named `rust`). Docs serve the code.
- **ADR** = decision record (why/alternatives/consequences; for devs, vs release notes for users).
  **DRY**, **bikeshedding** (trivial debates), **composition over inheritance**.

### Tooling
- **rustup** (Arch: pacman not curl), **Cargo** (`Cargo.toml` ~= pyproject, `Cargo.lock` ~= pip
  freeze, crates.io ~= PyPI; lib vs bin crate; feature flags `--features v4`), **cargokit** (auto
  build integration, don't edit), **flutter_rust_bridge_codegen** (scaffolds the project).
- **Run dirs:** `cargo *` from `gabbro/rust/`; `flutter *` and `flutter_rust_bridge_codegen
  generate` from `gabbro/`.
- **AUR:** build from source, prefer `flutter-bin`, check comments. **Flutter group** on Arch:
  `/opt/flutter`, `usermod -aG flutter $USER`.
- **SPDX/GPL:** Gabbro = `GPL-3.0-only` (not `-or-later` — retains author control; ADR-004).
  GPL-3.0 = strong copyleft for apps (share-alike, attribution, commercial OK), chosen over LGPL
  (apps not libs). GPL permits charging for distribution -> a paid Play Store build is fine; F-Droid
  free.
- **git:** `.gitignore` (trailing `/` = dir), `git remote add origin ...`, `push -u`, SSH key auth.
  `wc -l` for wordlist sanity (`7776`). [[reference_github_release]]
- **Dependency licence audit** before each RC: cross-check `_kComponents` (`about_screen.dart`) vs
  `Cargo.toml` + `pubspec.yaml`; dev-deps excluded; dual-licence (Apache-2.0/MIT for RustCrypto)
  listed as such. First audit (May 2026) found `once_cell`/`base64` missing.

### UX / i18n / naming
- **Gabbro:** a dark, inert igneous rock — permanence/trust, no trend signals; works across
  EN/FR/DE/IT/ES, no bad phonetics, `gabbro.app` free. The codename was VaultQPV.
- **Colour-coded password display** (ex-Enpass): colour + a per-type symbol so colour isn't the
  sole carrier (ADR-003). **CVD** ~8% men / 0.5% women (red-green) -> never colour-only (WCAG 2.1
  1.4.1), CVD-distinct palettes, user-overridable. **i18n input:** warn (don't block) on
  non-universal chars (é/à/ü) in the master passphrase. **Entropy display** educates in real time.
- **Testing pyramid:** many fast unit -> fewer widget -> few slow integration; build bottom-up.
  **Vault magic bytes:** `47 41 42 42 52 4f` = "GABBRO" + `01 00` version (u16 BE) in
  `file_format.rs`; verify with `hexdump -C`.
