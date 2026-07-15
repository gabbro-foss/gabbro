# Vault Sync

How to keep one Gabbro vault in step across devices. Gabbro has **no sync server** and
never phones home - syncing is left to you. This document is a **worked example** using
Syncthing (Linux) and Syncthing-Fork (Android), for **two devices**. It is not the only
option; it is a simple one that works.

The vault is encrypted at rest, so a sync tool only ever moves an opaque blob.

```
        Linux                                   Android phone
        ~/GabbroSync                            Download/GabbroSync
        +------------------------+              +------------------------+
        | Gabbro.gabbro          |              | Gabbro.gabbro          |
        | Gabbro.gabbro.sha256   |              | Gabbro.gabbro.sha256   |
        +------------------------+              +------------------------+
                    |                                       |
                    +------- direct, encrypted (TLS) -------+
                              Folder ID: SAME on both
```

---

## Read this first

Three ideas explain every step below.

- **Device ID** - a long code identifying one Syncthing install. Devices must add **each
  other**: adding Linux on the phone is only half; Linux must add the phone back.
- **Folder ID** - the shared identity of a synced folder. It **must be identical** on both
  devices or they will never sync. The folder *label* and the *path* are cosmetic/local and
  may differ.
- **Peer-to-peer** - there is no server. Both devices must be running and reachable
  (same LAN is simplest) for anything to move.

**The single most common mistake:** clicking *Add Folder* on the second device and letting it
generate a **new** Folder ID. Always reuse the first device's Folder ID.

---

## Before you start

- **One vault wins.** Decide which device holds the vault you want, and make the other side
  **identical or empty** before connecting. Two *different* vaults joined together produce
  conflict copies (see Troubleshooting) - the encrypted blob cannot be merged.
- **Do not edit the vault on both devices at once.** Change it in one place, let the sync
  settle, then use the other. Simultaneous edits = conflict, and you must pick a winner by hand.
- Sync `Gabbro.gabbro` and `Gabbro.gabbro.sha256` **together**; the `.sha256` verifies the vault.

---

## Part 1 - Linux

### 1.1 Install and enable

```bash
sudo pacman -S syncthing        # Arch
# sudo apt install syncthing    # Debian/Mint
systemctl --user enable --now syncthing.service
```

Use the **`--user`** unit, not `sudo systemctl`. A system service runs as **root** and would
create root-owned files in your home folder. The `--user` unit runs as you, starting at login.

> Only if you need it running before/without logging in, use *either*
> `loginctl enable-linger $USER` *or* `sudo systemctl enable --now syncthing@$USER.service`
> - never both, and never both alongside the `--user` unit (that would start two instances).

### 1.2 Create the folder

```bash
mkdir -p ~/GabbroSync
```

### 1.3 Add the folder in the GUI

Open **http://127.0.0.1:8384**. The GUI is only a dashboard - closing the browser does **not**
stop syncing.

**Screen:** *Add Folder* dialog.

| Field | Value | Notes |
|---|---|---|
| Folder Label | `GabbroSync` | Cosmetic. |
| Folder Path | `~/GabbroSync` | Local to this machine. |
| Folder ID | *keep the auto-generated value* | Linux is the origin here. **Write it down** - the phone needs it. |
| Folder Type (Advanced tab) | `Send & Receive` | Default. Keep. Two-way sync. |
| File Versioning (tab) | `Simple`, Keep Versions `5` | **Optional, recommended.** Keeps a copy of anything replaced/deleted in a hidden `.stversions/`. |

Save. The folder shows **Unshared** - expected, there are no devices yet.

### 1.4 Show the Device ID

**Screen:** *Actions* (top right) -> *Show ID*. A long code plus a QR code. Leave it open.

---

## Part 2 - Android

### 2.1 Install

Install **Syncthing-Fork** from **F-Droid**.

### 2.2 Create the target folder

With a file manager, create `Download/GabbroSync`
(full path: `/storage/emulated/0/Download/GabbroSync`).

### 2.3 GrapheneOS only - Storage Scopes

**Skip on stock Android.** GrapheneOS sandboxes an app's file access, and Syncthing-Fork
will silently see the folder as **empty** if it is not scoped.

**Screen:** phone **Settings** app (not Syncthing) -> **Apps** -> **Syncthing-Fork** ->
**Storage Scopes** -> **+** -> pick `Download/GabbroSync` -> confirm.

The scope must cover the **exact folder** you are syncing. A scope on some other directory
does nothing for this one.

### 2.4 Add the Linux device

**Screen:** *Devices* tab -> **+** -> the **QR icon** -> scan the QR from step 1.4.

| Field | Value |
|---|---|
| Device ID | filled in by the scan |
| Name | e.g. `linux-desktop` |
| Everything else | defaults |

Save. It will show **Disconnected** until Linux adds it back - expected.

---

## Part 3 - Connect them

### 3.1 Linux accepts the phone

Within ~30-60s the Linux GUI shows a bar: *"<phone> wants to connect"*.

**Screen:** *Add Device* dialog.

- **Name:** e.g. `phone`
- **Sharing tab:** tick **GabbroSync** (this offers the folder to the phone in the same step)
- **Advanced tab:** defaults

Save.

### 3.2 Phone accepts the folder

The phone should prompt *"<linux> wants to share GabbroSync"* -> accept, then set the
**Directory** to `Download/GabbroSync`. The Folder ID is carried over by the prompt - do not
change it.

**If no prompt appears** (common - the notification is unreliable), add it by hand instead:

**Screen:** *Folders* tab -> **+**

| Field | Value | Notes |
|---|---|---|
| Folder ID | the value from step 1.3 | **Must match exactly.** Replace the auto-filled one. |
| Folder Label | `GabbroSync` | Cosmetic. |
| Directory | `/storage/emulated/0/Download/GabbroSync` | |
| Sharing | tick the Linux device | |
| Folder Type | `Send & Receive` | Default. Keep. |

Save. Both sides should reach **Up to Date**.

---

## Part 4 - Verify (do not skip)

"Up to Date" can appear before a folder is really wired up. Prove it moves both ways with a
throwaway file - never the vault:

```bash
echo test > ~/GabbroSync/synctest.txt     # 1. create on Linux
# -> confirm synctest.txt appears in Download/GabbroSync on the phone
rm ~/GabbroSync/synctest.txt              # 2. delete on Linux
# -> confirm it disappears on the phone
```

Both halves must pass. Step 2 proves deletions propagate, not just additions.

---

## Defaults to keep

Leave these alone unless you have a reason:

| Setting | Default | Why keep it |
|---|---|---|
| Folder Type | Send & Receive | Two-way sync. `Receive Only` would never upload your changes. |
| Watch for Changes | on | Picks up edits immediately instead of waiting for a rescan. |
| Listen address / GUI port | `127.0.0.1:8384` | GUI is loopback-only - not exposed to the network. |
| Introducer | off | Keep pairing explicit. |

Two defaults worth a decision:

- **Global Discovery / Relaying** (both **on**). These let devices find each other over the
  internet, and relay through third-party servers when a direct connection fails. Traffic stays
  end-to-end encrypted, but your Device ID is announced publicly. If both devices are always on
  the same LAN you may turn both off (Actions -> Settings) for a smaller footprint.
- **File Versioning** (**off**). Turning on `Simple` is cheap insurance while you are still
  learning - it makes a bad sync recoverable.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Folder stuck at **0%**, shows **empty**, no error (GrapheneOS) | Storage Scope does not cover the folder | Add the exact folder to Storage Scopes (2.3) |
| Devices connect but folder never syncs | Folder IDs differ | Compare both; they must be identical |
| No folder-share prompt on the phone | Unreliable Android notification | Add the folder by hand with the matching Folder ID (3.2) |
| `*.sync-conflict-<date>-<time>-<id>.*` files appear | Both sides had **different** content; Syncthing kept both rather than lose one | Nothing is deleted. Compare, keep the one you want, remove the other |
| `.stfolder.removed-*` folders appear | Leftover markers from removing a folder on Android; they then sync everywhere | Safe to delete - not vault data |
| Phone shows `Download` **and** `Downloads` | Same directory under two names (Android file-manager alias) | Not a duplicate. Do not "clean up" one - you would delete the real folder |
| A file shows on one device but not the other's file manager | Stale Android media index | Trust Syncthing's own file count; it reads the live filesystem |

Read live status without the GUI:

```bash
KEY=$(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
curl -s -H "X-API-Key: $KEY" \
  "http://127.0.0.1:8384/rest/db/status?folder=<folder-id>"
```

`state`, `localFiles`, `needFiles` and `errors` tell you the truth when the UI is ambiguous.

---

## Notes on security

- The vault is **encrypted at rest**, so Syncthing only ever handles ciphertext. Its transport
  is TLS between devices, including over relays.
- `Download/` is **shared storage** - other apps with storage access can read the vault file
  there. That is acceptable *because* it is encrypted, but it is the reason the passphrase
  matters. Do not put a decrypted export in a synced folder.
- Syncthing's own "untrusted device" encryption is unnecessary here - the payload is already
  encrypted by Gabbro.
- `.stversions/` holds old vault copies. They are encrypted too, but they are also **real old
  vaults**: a rotated-away passphrase still opens the copy that used it.
