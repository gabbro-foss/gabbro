# Passkey Provider Investigation

Status: investigation, branch `passkey_investigation_and_implementation`. No code yet.
Goal: Gabbro stores website passkeys (WebAuthn discoverable credentials) in the vault
and serves them to browsers/apps, so they sync and back up like any entry.

**ADR situation (both left untouched until this investigation concludes):**
- ADR-008 (no browser extension, ever): stands. Both platform plans below are
  extension-free and use no Native Messaging.
- ADR-009 (no software passkey storage, "permanent"): under reconsideration. New
  argument: a YubiKey caps at 25 passkeys (firmware 5.0-5.6.x) or 100 (5.7+); the
  vault has no cap. Vault passkeys are AAL2, hardware is AAL3 (NIST SP 800-63B-4) -
  users keep the choice, as with app unlock today.
  Sources: <https://docs.yubico.com/hardware/yubikey-guidance/best-practices/all-faq-passkeys.html>,
  <https://pages.nist.gov/800-63-4/sp800-63b.html>

---

## Shared Rust core (platform-independent)

Both platforms need the same authenticator engine; only the transport differs.

- New vault entry type `Passkey`: private key (ES256, P-256), credential ID
  (random 32 bytes), RP ID, user handle, user name/display name, COSE public key,
  created/modified. Serialisation like any entry (`#[serde(default)]` on new fields).
- Crypto ops in `rust/src/`: ES256 keygen, COSE_Key encoding, authenticatorData
  assembly (flags UP, UV, BE=1, BS=1 for synced passkeys), SHA256withECDSA signing of
  `authenticatorData || clientDataHash`. Signature counter stays constant 0 -
  WebAuthn-sanctioned for synced passkeys
  (<https://www.w3.org/TR/webauthn-3/#sctn-sign-counter>).
- Attestation: "none"/self-attestation. Browsers accept it by default; the rare RP
  with a hardware-attestation allowlist will reject Gabbro passkeys (accepted).
- Import/export later: FIDO Credential Exchange Format CXF 1.0 is a Proposed
  Standard (2026-03-09); the transfer protocol CXP is still a working draft.
  <https://fidoalliance.org/specifications-credential-exchange-specifications/>

## Android: Credential Manager provider

First-party OS API. When any app/browser creates or uses a passkey, Android 14+
shows Gabbro in the system picker - no extension, no autofill heuristics.

- Implement `androidx.credentials.provider.CredentialProviderService`
  (`androidx.credentials:credentials` 1.6.0): `onBeginCreateCredentialRequest`,
  `onBeginGetCredentialRequest`, `onClearCredentialStateRequest`. Manifest service
  guarded by `android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE` + capabilities XML
  (`TYPE_PUBLIC_KEY_CREDENTIAL`).
  <https://developer.android.com/identity/sign-in/credential-provider>
- Two-phase flow: phase 1 returns entries for the picker (or an unlock
  `AuthenticationAction` when the vault is locked); phase 2 is a PendingIntent into
  our own activity, which unlocks, does the crypto via the Rust core, and returns the
  W3C JSON response. Request/response JSON is the W3C WebAuthn serialisation
  (<https://www.w3.org/TR/webauthn-3/#dictdef-publickeycredentialcreationoptionsjson>).
- Caller validation is the provider's job: native apps via Digital Asset Links
  (`assetlinks.json` on the RP domain vs caller package + cert); browsers via a
  privileged-browser allowlist the provider ships itself (reference list:
  <https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json>; Bitwarden vendors
  Google + community lists as assets).
- Works without Play Services on Android 14+: the pipeline is AOSP framework.
  GrapheneOS documents native credential-manager passkey support
  (<https://grapheneos.org/features>). Floor: API 34 (provider role does not exist
  below 14; our autofill service keeps covering passwords there).
- Coexists with `GabbroAutofillService` - one app can be both (Bitwarden is).
- Reference implementations: Bitwarden Android (GPL, Kotlin service + Rust-core
  crypto, same split as ours: <https://github.com/bitwarden/android>), KeePassDX
  (<https://github.com/Kunzisoft/KeePassDX/issues/1421>).

## Linux: virtual FIDO2 authenticator over /dev/uhid

No OS provider API exists. The extension-free route: a userspace daemon creates a
kernel virtual HID device (uhid) that speaks CTAP2. Browsers enumerate it exactly
like a plugged-in YubiKey - zero browser config, zero extension.

- Kernel uhid: open `/dev/uhid`, `UHID_CREATE2` with a FIDO HID report descriptor
  (usage page 0xF1D0), exchange 64-byte HID reports.
  <https://www.kernel.org/doc/html/latest/hid/uhid.html>
- Discovery is automatic: systemd's `fido_id` udev builtin tags any 0xF1D0 HID
  device `ID_FIDO_TOKEN=1`, granting the logged-in user hidraw access
  (<https://github.com/systemd/systemd/blob/main/src/udev/fido_id/fido_id.c>).
  Chromium filters on usage page 0xF1D0
  (<https://chromium.googlesource.com/chromium/src/+/refs/heads/main/device/fido/hid/fido_hid_discovery.cc>);
  Firefox uses authenticator-rs over hidraw with CTAP2 enabled
  (<https://github.com/mozilla/authenticator-rs>).
- To implement in Rust: CTAPHID framing (INIT/CBOR/MSG, 64-byte packets) + CTAP2
  CBOR commands `getInfo`, `makeCredential`, `getAssertion` (+ optional
  `credentialManagement`; vault UI covers listing/deleting natively). Advertise
  `rk: true` and built-in UV - unlock/consent happens in Gabbro's own UI, avoiding
  the clientPIN protocol. Spec:
  <https://fidoalliance.org/specs/fido-v2.1-ps-20210615/fido-client-to-authenticator-protocol-v2.1-ps-errata-20220621.html>
- No authenticator-side desktop crate exists; reuse pieces (all GPL-3.0-compatible):
  `ctap-types` CBOR types (<https://docs.rs/fido-authenticator>), CTAP2 state machine
  reference OpenSK (<https://github.com/google/OpenSK>), uhid descriptor + plumbing
  proof tpm-fido (<https://github.com/psanford/tpm-fido>, U2F-only), full
  CTAP2-over-uhid proof incl. discoverable credentials:
  <https://github.com/mc256/tpm-fido2-thinkpad-linux>.
- Deployment: one udev rule + `uhid` module load (ships in the .deb/PKGBUILD);
  daemon runs alongside the app or as part of it. Wayland/X11 irrelevant (kernel
  path). Native and snap browsers work; Flatpak browsers only if their manifest
  grants device access (their limitation, not ours).
- Security notes: any same-user process with hidraw access can request an assertion,
  so every operation gets a Gabbro consent dialog (RP ID shown). KeePassXC's
  passkeys are extension-based (<https://keepassxc.org/docs/KeePassXC_UserGuide#_passkeys>) -
  no password manager ships this route today.

## Rejected / deferred routes

- Browser extension + Native Messaging: banned, ADR-008.
- `linux-credentials` D-Bus portal (<https://github.com/linux-credentials/credentialsd>):
  right long-term shape, but today its browser wiring is itself an extension and no
  browser or desktop ships it. Track; revisit if browsers adopt the portal natively.

## Open decisions (in order)

1. ADR-009: supersede or amend? Blocks everything else.
2. Platform order: Android (small, first-party API, proven pattern) vs Linux
   (larger, novel daemon, no prior art among password managers).
3. Vault format: new entry type = new VERSION -> migration corpus vault + fixtures.
