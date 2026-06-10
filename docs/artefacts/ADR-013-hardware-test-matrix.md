# ADR-013 Hardware Test Matrix — Export Security Posture

Validates the committed ADR-013 work (export preserves protection; import enforces
it; opt-in passphrase-only downgrade) on real hardware. All steps are **physical
app actions and observations** — no function names. Run on a **release build**
(`flutter build linux --release` / `flutter build apk --release`).

Mark each cell **Pass / Fail / N/A** and note anything surprising.

## Preconditions / setup

- **VaultA — key-protected.** A vault created with a passphrase (call it **PA**)
  and **two** YubiKeys (**YK1**, **YK2**) during onboarding. Add one recognizable
  entry: a Password item titled **`HW-Sync-Canary`** with a memorable password.
- **VaultB — passphrase-only.** A separate vault with passphrase **PB** and at
  least one entry of its own (so a successful sync is visibly additive).
- Both YubiKeys on hand; YubiKey **PIN** known.
- Android: device with USB-C and NFC (S23).
- Pick scratch export paths, e.g. `~/VaultA_preserved.gabbro` and
  `~/VaultA_passphrase_only.gabbro` (Linux) or the Downloads folder (Android).

> A "tap" means: on Linux, touch the inserted YubiKey when it blinks; on Android,
> touch the USB-C key or hold the key to the NFC coil, per the chosen transport.

---

## Scenarios

### S1 — Export screen reflects key protection
1. Launch Gabbro; unlock **VaultA** (enter PA, tap a key).
2. Open the menu → **Export**.
3. With format **.gabbro** selected, read the protection note.
4. Look for the **"Export without YubiKey protection (passphrase only)"** switch.

**Expected:** the note states the exported copy keeps its YubiKey protection (a
registered key is required to import it); the switch is present and **OFF**.

| Linux | Android |
|---|---|
| pass | pass |

### S2 — Default export preserves protection
1. In Export (VaultA), leave the toggle **OFF**.
2. Choose a destination (`~/VaultA_preserved.gabbro` / Downloads) and tap **Export**.
3. Check the destination folder.

**Expected:** export succeeds; **two** files appear —
`VaultA_preserved.gabbro` and `VaultA_preserved.gabbro.sha256`.

| Linux | Android |
|---|---|
| pass | pass |

### S3 — Headline: sync a key-protected export into yubikeyless VaultB
1. Lock, then unlock **VaultB** (PB).
2. Menu → **Import**. In the **Gabbro vault** section, pick
   `VaultA_preserved.gabbro`.
3. Observe the section after selecting the file.
4. Enter **PA** in the passphrase field and the **YubiKey PIN** in the PIN field.
   (Android: choose **USB** or **NFC** in the transport selector.)
5. Tap **Sync from vault**; when prompted, **tap YK1**.
6. Look through VaultB's entries.

**Expected:** after step 3 an info note appears ("This vault is protected by a
YubiKey…") plus a **YubiKey PIN** field (and on Android a USB/NFC selector). After
the tap, the sync succeeds and **`HW-Sync-Canary`** now appears in VaultB.

| Linux | Android |
|---|---|
| pass | pass |

### S4 — Security: passphrase alone cannot bypass the key
1. Unlock **VaultB**; Import → pick `VaultA_preserved.gabbro`.
2. **Remove/withhold all YubiKeys.** Enter PA + PIN, tap **Sync from vault**, and
   present **no** key.

**Expected:** the sync is **refused** — an error appears (Linux: "No FIDO2 device
found…"; Android: a USB/NFC timeout). **No** entries are imported into VaultB.

| Linux | Android |
|---|---|
| pass | pass - message appears to "tap your yubikey now" and user can still back out |

### S5 — Opt-in passphrase-only downgrade export
1. Unlock **VaultA** (PA + tap). Menu → **Export**.
2. Turn the **"Export without YubiKey protection (passphrase only)"** switch **ON**.
3. Read the warning that appears.
4. Export to `~/VaultA_passphrase_only.gabbro`.

**Expected:** turning the switch on surfaces a warning (the file opens with the
passphrase alone, anyone with the passphrase can read it, original vault
unchanged); export succeeds.

| Linux | Android |
|---|---|
| pass | pass |

### S6 — Sync the downgraded export with passphrase only (no key)
1. Unlock **VaultB** (PB). Import → pick `VaultA_passphrase_only.gabbro`.
2. Observe the Gabbro section.
3. Enter **PA**, tap **Sync from vault**.

**Expected:** **no** YubiKey fields/info note appear (passphrase-only source); the
sync succeeds with the passphrase alone (no key prompt); `HW-Sync-Canary` is
present in VaultB.

| Linux | Android |
|---|---|
| pass | pass |

### S7 — Downgrade export does not mutate the original
1. After S5, lock and unlock **VaultA** again.

**Expected:** VaultA **still** requires PA **and** a YubiKey tap to unlock — the
on-disk vault's protection class is unchanged by the passphrase-only export.

| Linux | Android |
|---|---|
| pass | pass |

### S8 — Negative cases on key-protected sync
Import `VaultA_preserved.gabbro` into VaultB and try each:

| Case | Steps | Expected | Linux | Android |
|---|---|---|---|---|
| a. Wrong passphrase | wrong PA, correct PIN, tap a registered key | error after tap (decrypt fails); nothing synced | pass | pass |
| b. Wrong PIN | correct PA, wrong PIN, tap | PIN error; nothing synced | pass | pass |
| c. Unregistered key | correct PA + PIN, tap a key **not** registered to VaultA | no-match error; nothing synced | pass | pass (slow) |

### S9 — Android transport sub-matrix
Repeat **S3** over each transport.

| USB-C | NFC |
|---|---|
| pass | pass |

### S10 — Integrity companion (optional)
1. Linux: `sha256sum -c VaultA_preserved.gabbro.sha256` in the export folder.

**Expected:** reports `OK`.

| Linux |
|---|
| pass |

### S11 — Regression sanity (key-protected vault still normal)
1. Unlock **VaultA** (PA + tap); edit `HW-Sync-Canary`'s password; save.
2. Lock, unlock again; confirm the edit persisted.

**Expected:** unlock, edit, and re-unlock all behave as before — the export/import
changes did not disturb normal key-protected vault use.

| Linux | Android |
|---|---|
| pass | pass |

---

## Notes / findings

_(Record failures here with the exact step, the message shown, and the platform.
Anything that fails becomes a fix-forward task; the Dart flow is host-tested, so a
hardware failure is most likely in the platform tap path or the import wiring.)_
