# Gabbro — Learnings & Concepts

A running journal of concepts covered during development.

---

## Cryptography

### PQC — Post-Quantum Cryptography
Cryptographic algorithms designed to be secure against both
classical and quantum computers. NIST finalized first standards
in 2024: ML-KEM (key encapsulation) and ML-DSA (signatures).
Relevant because a sufficiently powerful quantum computer could
break current RSA/ECC encryption.

### Argon2id — Key Derivation Function (KDF)
Converts a human-memorable passphrase into a cryptographic key.
Deliberately slow and memory-hard to resist brute force attacks.
The attacker pays the same computational cost per guess as the
legitimate user — but the user only pays it once.

### AES-256-GCM
Symmetric encryption algorithm used to encrypt the vault body.
GCM mode adds authentication — detects any tampering with the
encrypted data. Fast and efficient for large payloads.

### ML-KEM (formerly CRYSTALS-Kyber)
NIST-standardized post-quantum key encapsulation mechanism.
Protects the key exchange layer against quantum computer attacks.

### Hybrid Encryption
Using both classical (AES-256) and post-quantum (ML-KEM)
encryption together. "Belt and suspenders" — if one layer is
broken, the other still holds.

### Kerckhoffs's Principle
Security should come from the key, not from hiding the algorithm
or parameters. The vault header can be plaintext because it
contains no secrets — only parameters needed to attempt
decryption.

### Salt
A random value added to a passphrase before hashing. Ensures
two users with the same passphrase get different keys. Prevents
rainbow table attacks. Not secret — just needs to be unique.

### Nonce (Number Used Once)
A random value used once per encryption operation. Like a salt
for encryption. Stored alongside encrypted data. Not secret.

### SHA-256 — Secure Hash Algorithm 256-bit
A one-way cryptographic hash function that produces a fixed 64-character
hex digest from any input. "One-way" means you cannot reverse it to
recover the original data — only verify that the data matches.
Used in Gabbro to produce a detached integrity hash alongside
exported vault files, following the same convention as Linux ISO
verification.

### Detached Hash / Checksum File
A small companion file (e.g. `vault.gabbro.sha256`) containing the hash
of another file. Lets anyone verify the file hasn't been corrupted or
tampered with, using any standard tool (`sha256sum` on Linux,
`certutil` on Windows), without needing the application that created
the file. Distinct from an embedded auth tag: the hash is outside the
file, so it can be checked before opening.

### TOTP — Time-based One-Time Password
The 6-digit codes used by Google Authenticator and similar apps.
Excluded from Gabbro deliberately — keeping your password
manager and 2FA codes separate is more secure. YubiKey provides
stronger 2FA anyway.

---

## Security Concepts

### Two Security Layers
- **Layer 1 (at rest):** vault file encryption — protects the
  vault if stolen
- **Layer 2 (app access):** FIDO2/YubiKey authentication —
  protects against unauthorised app access
- Independent layers: like a safe inside a locked room

### 3-2-1 Backup Rule
3 copies of your data, on 2 different media, with 1 offsite.
Critical for Gabbro because vault wipe after 10 failed
attempts means backups are your only recovery option.

### FIDO2/WebAuthn
Hardware authentication standard. YubiKey compliant. Used for
Layer 2 authentication. Stronger than TOTP because it requires
physical possession of the hardware key.

---

## Architecture & Design

### Flutter:Rust :: Frontend:Backend
Flutter handles UI and user interaction. Rust handles all
security-critical operations. flutter_rust_bridge connects them
via FFI (Foreign Function Interface) — like a REST API but
in-process, faster, no network to intercept.

### FFI — Foreign Function Interface
A bridge allowing code in one language to call code in another.
Gabbro uses flutter_rust_bridge to let Flutter/Dart call
Rust functions.

### ADR — Architectural Decision Record
A short markdown file recording why a design decision was made,
what alternatives were considered, and what the consequences are.
Invaluable when returning to a project after a break.
Unlike release notes (aimed at users), ADRs are aimed at
developers.

### DRY — Don't Repeat Yourself
A core programming principle: build something once and reuse it
everywhere. Example: the password generator is built once in
Rust and surfaced in both the main screen and entry editor.

### Bikeshedding
Spending disproportionate time debating trivial details while
ignoring important ones. From a story about a committee
approving a nuclear plant but debating the bike shed colour.

### Scaffold-first, adapt second
When using a generator tool (like flutter_rust_bridge_codegen),
let the tool create the canonical structure first, then adapt
your own conventions to fit — not the other way around. Fighting
the generator's expected layout causes build failures. In the
case of Gabbro, this meant accepting `rust/` as the Rust crate
name rather than the originally planned `rust_core/`.

### Docs serve the project, not the other way around
When reality diverges from a design document (e.g. folder names),
update the doc to match reality. The code is the truth; the doc
describes it.

---

## Tooling

### rustup
The Rust toolchain installer and version manager. On Arch Linux,
install via pacman (`pacman -S rustup`) rather than the upstream
curl installer, to stay consistent with Arch's package management
philosophy. After install, run `rustup toolchain install stable`
and `rustup default stable`.

### flutter_rust_bridge_codegen
CLI tool that scaffolds a Flutter + Rust project with all bridge
wiring pre-configured. Install via `cargo install flutter_rust_bridge_codegen`.
Run `flutter_rust_bridge_codegen create gabbro` to generate
a new project. The generated structure includes platform folders
for all targets (android, ios, linux, macos, windows), cargokit
build integration, and example bridge code.

### cargokit
Build integration layer inside `rust_builder/` — handles compiling
the Rust crate and linking it into the Flutter app for each target
platform. Generated automatically by flutter_rust_bridge, not
edited manually.

### Cargo
Rust's package manager and build tool. `Cargo.toml` declares
dependencies; `Cargo.lock` pins exact versions. Analogous to
`pubspec.yaml` / `pubspec.lock` in Flutter.

### AUR (Arch User Repository)
Community-maintained package repository for Arch Linux. Packages
are built from source using `makepkg`. When multiple providers
exist for a dependency, prefer the most straightforward binary
package (e.g. `flutter-bin` over split or dev variants) unless
there is a specific reason to do otherwise. Always check AUR
comments for known issues before installing.

### flutter group (Arch Linux)
On Arch, Flutter is installed to `/opt/flutter` and requires
group membership for write access. Add your user with:
`sudo usermod -aG flutter $USER`, then log out and back in.

### SPDX — Software Package Data Exchange
A standard format for communicating licence information.
SPDX identifiers are short strings that unambiguously identify a
licence — tools, package managers, and legal scanners all understand
them. Examples: `GPL-3.0-only`, `MIT`, `Apache-2.0`.

The distinction between `GPL-3.0-only` and `GPL-3.0-or-later` matters:
- `GPL-3.0-only` — licensed under GPL-3.0 and only GPL-3.0; future
  versions do not automatically apply; retains full author control
- `GPL-3.0-or-later` — future FSF GPL versions apply automatically;
  cedes some control to the FSF

Gabbro uses `GPL-3.0-only`. See ADR-004.

### GPL-3.0 — GNU General Public License version 3
A strong copyleft licence for applications. Key properties:
- Anyone distributing modified versions must release source under
  GPL-3.0 (share-alike)
- Copyright notices and attribution must be preserved
- Commercial use and monetisation are explicitly permitted
- Standard no-warranty and liability limitation clauses protect
  the author
- Designed for standalone applications, unlike LGPL which is
  designed for libraries

Chosen over LGPL because Gabbro is an application, not a library.
See ADR-004 for full reasoning.
A file at the root of a git repository that tells git which files and
folders to ignore — i.e. never track or commit. Essential for excluding
build artefacts, IDE settings, and development-only folders that have
no place in version control. A trailing slash (e.g. `chat_info/`) tells
git the entry is a directory. Flutter projects ship with a
generated `.gitignore`; project-specific exclusions are added manually.

---

## Project History & Naming

### App Naming — Gabbro
The app was named Gabbro after a dark, hard intrusive igneous rock —
geologically stable, found worldwide, and essentially inert. The name
was chosen to convey permanence and trustworthiness without relying on
trend-driven signals (e.g. "quantum", "crypto"). It works without
awkward connotations across English, French, German, Italian, and
Spanish. The working title VaultQPV served as an internal codename
during early architecture design.

Key criteria applied during the naming process: works across target
languages, no bad phonetic connotations (e.g. French *étron*, French
*s'évader*), not already registered in the same space, timeless rather
than trendy, available as `gabbro.app`.

---

## UX & Internationalisation

### Colour-coded Password Display
Inspired by Enpass. Colours distinguish character types.
Updated from the original emoji concept to use both colour
and a symbol marker per character type, so that colour is
never the sole carrier of meaning — see ADR-003.

### Colour Vision Deficiency (CVD)
Affects approximately 8% of men and 0.5% of women. The most
common forms (deuteranopia, protanopia) cause difficulty
distinguishing red from green. Designing with CVD in mind
means: (1) never use colour as the only differentiator,
(2) choose palettes where hues remain distinct under CVD
simulation, (3) offer user-overridable colours.

### WCAG — Web Content Accessibility Guidelines
A set of internationally recognised accessibility standards.
WCAG 2.1 criterion 1.4.1 ("Use of Colour") requires that colour
is not used as the only visual means of conveying information.
Relevant to Gabbro's password character display and any other
colour-coded UI elements.

### i18n Edge Cases in Security Inputs
Locale-specific characters (e.g. é, à, ü on Swiss/French
keyboards) may not be available on all keyboards. Gabbro
warns users when non-universal characters are detected in
their master passphrase, without blocking their use.

### Entropy (password)
A measure of password unpredictability in bits. Higher is
better. Displaying entropy in real time educates users about
why length and character variety matter.
