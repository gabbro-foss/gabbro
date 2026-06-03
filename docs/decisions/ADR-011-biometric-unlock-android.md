# ADR-011: Biometric Unlock on Android

## Status
Accepted

## Date
2026-06-03

## Context

Typing a long passphrase on a phone every time the vault re-locks is a
significant friction point, particularly for users who lock frequently (e.g.
30-second foreground timeout). The YubiKey tap remains a required second factor
on Android; the passphrase is the friction point, not the hardware tap.

Two approaches were considered:

**Option A — Passphrase stored encrypted on device (chosen)**
The passphrase is encrypted with a Keystore-managed AES-256-GCM key that
requires biometric authentication to use, and the ciphertext is stored
app-privately in `EncryptedSharedPreferences`. On every subsequent unlock, the
user authenticates with biometrics; Kotlin decrypts the passphrase and passes it
transiently to Rust, where it is zeroed after the Argon2id KDF completes.
Cold-start and post-lock-timeout unlocks both require only a biometric prompt.

**Option B — Biometric as identity gate only (rejected)**
Biometrics only confirm identity for in-app re-authentication operations (export,
change-passphrase confirmation) where a Rust session is already live. After a
lock timeout the vault session is cleared, so the passphrase is unavailable and
the user must type it again to re-unlock. Option B therefore does not remove
passphrase typing from the most common friction point (re-unlock after timeout)
and adds complexity for minimal gain over the status quo.

## Decision

Implement **Option A** as an opt-in Android-only feature. The master passphrase
is stored encrypted in `EncryptedSharedPreferences`, protected by a biometric-gated
Android Keystore key. When enabled, biometrics are offered as a primary unlock
method alongside the passphrase — the passphrase field is always visible and
usable; biometrics are never the sole path. The YubiKey tap applies only to users
who enrolled a YubiKey during onboarding.

The feature is:
- **Disabled by default** — high-risk users may not want passphrase material on
  the device; they must explicitly opt in
- **Android-only** — Linux has no biometric subsystem; the toggle is hidden on
  Linux
- **Scoped to the app** — Gabbro never stores, reads, or transmits biometric
  data (fingerprint templates, face geometry); that data lives exclusively in the
  phone's Trusted Execution Environment (TEE), managed by the OS

## Security properties

| Property | Detail |
|---|---|
| Biometric data stored by Gabbro | Never — TEE only |
| Which biometrics unlock Gabbro | All biometrics enrolled on the device (all fingerprints, face unlock); the app cannot restrict to a specific fingerprint — this is an Android platform constraint |
| What Gabbro stores | AES-256-GCM ciphertext of passphrase + encryption nonce (`EncryptedSharedPreferences`). The nonce (also called IV — Initialization Vector) is a random value generated per encryption; AES-GCM requires it so that two encryptions of the same passphrase produce different ciphertext. |
| Key protection | Android Keystore, `setUserAuthenticationRequired(true)` |
| New biometric enrolled on device | Keystore key automatically invalidated (`setInvalidatedByBiometricEnrollment(true)`); this applies to **any** new biometric enrollment — including the legitimate user adding a second fingerprint. Next biometric attempt fails; user must re-enter passphrase and re-enroll in Gabbro. This is intentional: it prevents an attacker with physical access from enrolling their own fingerprint to take over the key. |
| Passphrase in memory | Decrypted transiently in Kotlin, passed to Rust as `byte[]`, zeroed in Rust immediately after Argon2id; never held in Dart |
| YubiKey tap | Applies only to users who enrolled a YubiKey during onboarding — biometrics only replace passphrase typing |
| Passphrase always available | Yes — the passphrase field is always shown alongside the biometric option; biometrics are never the sole unlock path |
| User can delete enrollment | Yes, from within the app; no OS interaction needed |

## Operational design

### Enabling biometric unlock

1. User navigates to **Settings → Security** and toggles **Biometric unlock** ON
2. App checks biometric hardware availability; if unavailable shows an error (see
   messages below) and reverts the toggle
3. User is shown an explanation dialog (see messages below)
4. User enters their current passphrase in a prompt (to seed the enrollment)
5. Android `BiometricPrompt` is shown to confirm enrollment
6. On biometric success: Kotlin generates a new AES-256-GCM Keystore key,
   encrypts the passphrase, stores ciphertext + IV in `EncryptedSharedPreferences`
7. Setting saved as `biometric_unlock: true`

### Unlock flow (biometric enabled)

1. App opens or vault re-locks (foreground / background timeout)
2. Unlock screen shows both a **Use biometrics** button and the passphrase text
   field simultaneously; the user may use either
3. If user taps **Use biometrics**: Android `BiometricPrompt` shown; on success
   Kotlin decrypts stored ciphertext → passphrase bytes passed to Rust →
   Argon2id KDF runs → passphrase bytes zeroed → vault key derived → unlock
   proceeds
4. If user types passphrase directly: normal unlock flow, unchanged
5. YubiKey tap (if enrolled) follows whichever path was taken

### Disabling biometric unlock

1. User toggles **Biometric unlock** OFF in **Settings → Security**
2. App deletes the ciphertext from `EncryptedSharedPreferences`
3. App deletes the Keystore key entry
4. Setting saved as `biometric_unlock: false`

Nothing remains on the device after step 3.

### Keystore key invalidation

If Android detects new biometric enrolment on the device after the Keystore key
was created (e.g. a new fingerprint added at OS level):

- The Keystore key is automatically invalidated by the OS
- The next biometric unlock attempt throws `KeyPermanentlyInvalidatedException`
- Gabbro catches this, deletes the stale ciphertext, and shows an error (see
  messages below)
- The user must re-enter their passphrase to re-enroll

## User-facing messages

All messages must be translated to all supported languages.

**Explanation dialog on enable:**
> **About biometric unlock**
>
> When enabled, Gabbro encrypts your master passphrase and stores it
> on this device, protected by your biometrics. Your passphrase is
> decrypted only at the moment of unlock and is never kept in memory.
>
> Your fingerprint or face data is never stored by Gabbro — it stays
> in your phone's secure chip.
>
> **All biometrics enrolled on this device** (fingerprints, face) will
> be able to unlock Gabbro. You cannot restrict it to a specific
> fingerprint.
>
> If any new biometric is added to this phone (including a second
> fingerprint), this setting will be automatically disabled and you
> will need to set it up again.
>
> **Recommendation:** keep this disabled if you have a high threat model
> or share this device.

**Biometric hardware unavailable:**
> Biometric unlock is not available on this device. No biometric sensor
> was found or no biometrics have been enrolled in system settings.

**Keystore key invalidated (any new biometric enrolled at OS level, including a
second fingerprint added by the user themselves):**
> Biometric unlock was disabled because the biometrics on this device
> changed (a new fingerprint or face was added in system settings).
> This is a security measure.
> Please re-enter your passphrase and enable biometric unlock again if
> you wish to continue using this feature.

**Biometric prompt title (system prompt):**
> Unlock Gabbro

**Biometric prompt subtitle (system prompt):**
> Confirm your identity to unlock the vault

**Biometric cancelled or failed (shown below passphrase field):**
> Biometric authentication was not completed. Enter your passphrase to unlock.

## Implementation notes

- No new Rust bridge functions are needed
- New Kotlin file: `BiometricHelper.kt` — handles Keystore key lifecycle,
  `BiometricPrompt`, encrypt/decrypt
- New Flutter `MethodChannel`: `app.gabbro.gabbro/biometric` — methods:
  `enroll(passphrase: Uint8List)`, `authenticate() → Uint8List`,
  `unenroll()`, `isEnrolled() → bool`, `isAvailable() → bool`
- `settings.dart`: add `biometricUnlock: bool` (default `false`); Android-only
  semantics, persisted in `settings.jsonc` on all platforms
- Security screen: biometric `SwitchListTile` visible only when
  `Platform.isAndroid`
- Unlock screen: on Android with biometric enrolled, trigger `BiometricPrompt`
  on init; on success call existing `_unlock()` with retrieved passphrase; on
  failure/cancel show normal passphrase field

## Consequences

### Positive
- Removes passphrase typing friction on Android for all unlock and re-auth flows
- Biometric data never held by the app; no new biometric privacy surface
- Passphrase field always present alongside biometric option — user is never
  locked out if biometrics fail
- YubiKey tap (where enrolled) unchanged; biometrics are an additional
  convenience layer, not a security downgrade
- Enrollment deletion is app-internal; no OS settings interaction required
- Keystore invalidation on any new OS biometric enrolment (including a second
  legitimate fingerprint) limits exposure from physical-access attacks; the
  trade-off is that adding a second fingerprint requires re-enrolling in Gabbro

### Negative / Tradeoffs
- The master passphrase (encrypted) is now stored on the device; if the Android
  Keystore implementation has a vulnerability, the passphrase ciphertext is
  exposed — this is the standard Android biometric unlock trade-off accepted by
  all major password managers
- Opt-in default limits adoption but is the correct posture for a
  security-focused app
- Adds a Kotlin platform channel and new test surface

## References
- ADR-010: YubiKey FIDO2 hmac-secret authentication
- Android BiometricPrompt API:
  https://developer.android.com/reference/androidx/biometric/BiometricPrompt
- Android Keystore system:
  https://developer.android.com/training/articles/keystore
- `KeyGenParameterSpec.setInvalidatedByBiometricEnrollment`:
  https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setInvalidatedByBiometricEnrollment(boolean)
- `EncryptedSharedPreferences`:
  https://developer.android.com/reference/androidx/security/crypto/EncryptedSharedPreferences
