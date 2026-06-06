# Gabbro

A post-quantum password manager built with security as core DNA.

> **Status: Alpha — v0.1.0-alpha.5 released.**
> All vault operations are implemented and tested in Rust.
> Flutter UI implemented (506 tests passing).

---

## What is Gabbro?

Gabbro is a free, open-source password manager designed for users who
take security seriously. It combines classical and post-quantum
cryptography to protect your secrets today and against the quantum
computers of tomorrow.

Named after the intrusive igneous rock — hard, stable, enduring.

### Key properties

- **Post-quantum cryptography** — ML-KEM (NIST standard) alongside
  AES-256-GCM; belt and suspenders against both classical and quantum
  threats
- **Hardware key required** (optional but recommended) — FIDO2/YubiKey authentication; minimum
  two keys (primary + backup)
- **Rust for all secrets** — every cryptographic operation lives in
  Rust; secrets never cross the Flutter/Rust bridge in plaintext
- **Local-first** — your vault lives on your device; sync is your
  choice and your responsibility
- **Localised** — UI available in 33 languages (EN, FR, DE, IT, ES, and 28 more); follows system locale with in-app override
- **Multi-language passphrase generator** — 29-language wordlist library; classic generator uses language-native character pools (Greek, Cyrillic, Hiragana/Katakana, Hangul, CJK)
- **In-app help** — offline help carousel; no external website or internet connection required
- **FOSS** — GPL-3.0-only licensed

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) |
| Crypto & secrets | Rust |
| Bridge | flutter_rust_bridge v2 (FFI) |

The Flutter:Rust split follows a strict principle: if it touches a
secret, it lives in Rust. Everything else lives in Flutter.

---

## Target Platforms

| Platform | Target |
|---|---|
| Linux (Arch, Mint) | v1 |
| Android (F-Droid) | v1 |
| Windows, macOS, iOS | v2 (future) |

---

## Encryption

```
passphrase + random_salt
→ Argon2id (KDF)
→ 256-bit master key
→ ML-KEM (post-quantum key encapsulation)
→ AES-256-GCM (vault encryption)
→ encrypted vault body + auth tag
```

Vault files use the `.gabbro` extension and are self-contained —
all parameters needed for decryption travel with the file.
Exports include a detached SHA-256 hash for integrity verification.

---

## Verifying Export Integrity

Every vault export produces two files:

```
vault.gabbro         — the encrypted vault
vault.gabbro.sha256  — detached SHA-256 hash
```

To verify the export has not been corrupted or tampered with:

```bash
sha256sum -c vault.gabbro.sha256
```

A clean result prints `vault.gabbro: OK`. This follows the same
convention as Linux ISO verification and can be run before decryption
using any standard tool — no Gabbro installation required.

Note: AES-256-GCM's authentication tag already detects tampering
during decryption. The detached hash is a UX complement that allows
verification *before* opening the vault.

---

## Project Structure

```
gabbro/
├── lib/          # Flutter UI (Dart)
├── rust/         # Cryptography and secrets (Rust)
├── rust_builder/ # Cargokit build integration (do not edit)
├── docs/         # Architecture docs and ADRs
│   └── decisions/
└── ...           # Platform folders (android, ios, linux, macos, windows)
```

Full details in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Contributors

- [Robert Leckenby](https://github.com/Zabamund/) — project owner,
  architect, and lead developer
- [Claude.ai](https://claude.ai) — AI development partner

---

## Installation

> **Alpha release — for invited testers only.** The cryptographic
> implementation has not yet undergone external review. Do not store
> passwords you cannot afford to lose.

Download the latest release from the
[Releases](https://github.com/Zabamund/gabbro/releases) page,
or receive the artifact directly from the project owner.

### Linux (Arch, Debian trixie, Linux Mint)

Requires glibc ≥ 2.34 — satisfied by all current Arch, Debian stable,
and Mint installations.

```bash
tar -xzf gabbro-v0.1.0-alpha.1-linux-x86_64.tar.gz
./bundle/gabbro
```

You can place the `bundle/` directory anywhere; the app is self-contained.

### Android

1. Enable **Install from unknown sources** on your device:
   - Android 8+: Settings → Apps → Special app access → Install unknown apps → select your file manager → Allow
2. Transfer `gabbro-v0.1.0-alpha.1-android.apk` to your device (USB, email, or file transfer).
3. Tap the APK file in your file manager to install.

Tested on Android 11+. YubiKey authentication requires a YubiKey 5 series key (USB-A/C for all devices; NFC where supported).

---

## Development

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install)
- [Rust](https://rustup.rs/) (`rustup toolchain install stable`)
- [flutter_rust_bridge_codegen](https://crates.io/crates/flutter_rust_bridge_codegen)

On Arch Linux, install Flutter via the AUR (`flutter-bin`) and Rust
via pacman (`pacman -S rustup`). Add yourself to the `flutter` group:

```bash
sudo usermod -aG flutter $USER
# log out and back in
```

### Run locally

from `gabbro` root folder:

```bash
flutter pub get
flutter run -d linux   # Linux desktop
flutter run -d android # Android device/emulator
```

### Build

from `gabbro` root folder:

```bash
flutter build linux --release   # Linux desktop
./build/linux/x64/release/bundle/gabbro # Run on linux
flutter build apk --release     # Android device
adb install build/app/outputs/flutter-apk/app-release.apk # install on Android device
```

### Tests

```bash
# Rust unit tests
cd rust && cargo test

# Flutter tests
flutter test

# Integration tests
flutter test integration_test/
```

---

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — full architecture reference
- [`docs/LEARNINGS.md`](docs/LEARNINGS.md) — concepts and decisions explained
- [`docs/AI_SECURITY_AUDIT.md`](docs/AI_SECURITY_AUDIT.md) — AI-assisted security review of the crypto and vault modules (Claude Opus 4.7, 2026-05-31)
- [`docs/decisions/`](docs/decisions/) — architectural decision records (ADRs)

---

## Licence

GPL-3.0-only — see [`LICENSE`](LICENSE) for details.

---

## Contributing

This project is in early development. Contributions, feedback, and
security review are welcome.

**Before contributing, please open an issue** to discuss what you have
in mind. This applies to bug reports, feature requests, and proposed
changes alike.

### On agentic contributions

Gabbro is a security-critical project. All contributions must be
human-authored and human-reviewed.

- **Agentic pull requests are not accepted.** PRs authored or
  generated by AI agents will be closed without review. This is not
  a reflection on AI tools generally — it is a recognition that
  security-sensitive code requires human understanding, human
  accountability, and human judgement at every step. 
  (See: [the curl project's experience with AI contributions](https://daniel.haxx.se/blog/2024/01/02/the-i-in-llm-stands-for-intelligence/) for context on why this matters.)
- **Agents are welcome to open issues.** If an AI assistant has
  identified a bug, a security concern, or a reasonable feature
  request, a respectfully written issue is a genuine contribution.
  Please state clearly that the issue was AI-assisted.

Human reviewers are scarce; their attention is valuable. Please
respect that.
