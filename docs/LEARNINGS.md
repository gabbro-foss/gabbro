# Gabbro — Learnings & Concepts

A running journal of concepts covered during development.

---

## Rust — `Zeroizing<T>` for automatic secret cleanup

`Zeroizing<T>` from the `zeroize` crate is a newtype wrapper that calls
`.zeroize()` on its inner value when dropped. It is the idiomatic way to
ensure short-lived secret buffers are cleared from memory even if the
function returns early or panics.

Python analogy: a context manager (`with` block) that guarantees cleanup
on exit regardless of how the block exits — except `Zeroizing<T>` works
via Rust's ownership and `Drop` trait, so no explicit `with` syntax is
needed. The cleanup is woven into the type system.

Usage pattern for stack arrays and cloned `Vec<u8>`:

```rust
use zeroize::Zeroizing;

// Stack array — zeroed on drop
let key: Zeroizing<[u8; 32]> = Zeroizing::new(derive_key(...)?);
some_function(&*key); // deref to &[u8; 32]

// Cloned Vec — zeroed on drop
let passphrase = Zeroizing::new(session.passphrase.clone());
save_vault(&entries, &passphrase, &path)?;
```

Important nuance: `Zeroizing<T>` narrows the window during which a secret
is recoverable in RAM — it does not eliminate the risk entirely. Swap,
hibernation, and cold-boot attacks can still preserve zeroed memory pages.
Full-disk encryption (FDE) remains a stated prerequisite for Gabbro's full
security model.

---

## TDD — rewriting tests when architecture decisions change

TDD is not about locking in tests that can never change. A skipped test that
was written anticipating an implementation that was never built (or was
superseded by a better design decision) should be rewritten to match the
actual architecture — not forced through or left skipped indefinitely.

In this case: test 6 in `vault_list_tablet_test.dart` was written expecting
in-place edit-mode dimming (`_isEditing` state). The implemented architecture
uses full-screen push navigation (Option 2 from the wireframe decisions),
which makes the dim both unnecessary and unobservable. The correct response
was to remove the dead `_isEditing` code and rewrite the test to assert the
actual behaviour: tapping the pencil pushes `CreateEntryScreen`.

The principle: tests are specifications of intended behaviour. When the
intended behaviour changes by design, the specification changes too.

---

## Flutter — `ScrollMetricsNotification` for geometry-driven UI

A `ScrollController` listener only fires when the user scrolls. It does
not fire when the scroll geometry changes due to a layout event such as
an orientation change. This means chevron/affordance visibility logic
driven only by a controller listener will not update on rotation.

`ScrollMetricsNotification` fires whenever the scroll metrics change —
including on viewport resize. Wrap the scrollable in a
`NotificationListener<ScrollMetricsNotification>` and call the update
function from `onNotification`. Return `false` to let the notification
bubble up.

```dart
NotificationListener<ScrollMetricsNotification>(
  onNotification: (notification) {
    _updateChevrons();
    return false;
  },
  child: SingleChildScrollView(...),
)
```

Python analogy: like attaching a callback to a `resize` event on a
widget rather than only listening to scroll events — the geometry changed
even though nothing was scrolled.

---

## Flutter — `library_private_types_in_public_api` lint

Dart's `library_private_types_in_public_api` lint fires when a public
method returns or exposes a private type (one starting with `_`). The fix
is to introduce a public abstract class that exposes only the API surface
descendants need, and have the private state class implement it.

```dart
abstract class GabbroAppState {
  AppSettings get settings;
  Future<void> updateSettings(AppSettings updated);
}

class _GabbroAppState extends State<GabbroApp>
    implements GabbroAppState { ... }
```

The static `of()`/`maybeOf()` methods then return `GabbroAppState`
instead of `_GabbroAppState` — no private type crosses the public
boundary.

---

## Android — `<queries>` and package visibility (Android 11+)

Android 11 introduced package visibility restrictions. Apps must declare
which URL schemes they intend to query in `AndroidManifest.xml` via a
`<queries>` block. Without it, `canLaunchUrl()` from `url_launcher`
returns `false` for `https://` URLs even when a browser is installed —
the launch is silently skipped.

Fix: add `ACTION_VIEW` intents for `https` and `http` schemes inside
`<queries>`:

```xml
<intent>
    <action android:name="android.intent.action.VIEW"/>
    <data android:scheme="https"/>
</intent>
<intent>
    <action android:name="android.intent.action.VIEW"/>
    <data android:scheme="http"/>
</intent>
```

Also: drop the `canLaunchUrl` guard and call `launchUrl` directly,
checking the returned `bool` to show a snackbar on failure. The guard
pattern is the silent failure point — if `canLaunchUrl` returns `false`,
nothing happens and the user has no feedback.

Python analogy: like checking `os.path.exists()` before `open()` — if
the check itself is broken, the failure is invisible. Better to attempt
the operation and handle the exception explicitly.

## Android — storage permissions and scoped storage

Gabbro declares no storage permissions in `AndroidManifest.xml`. This
is correct because:

- **App-private storage** (`getApplicationDocumentsDirectory()` via
  `path_provider`) requires no permission on any Android version — the
  OS grants access automatically to the app's own directory.
- **User-chosen paths** (export/import via `file_picker`) use the
  Storage Access Framework (SAF) — the OS file picker grants URI-scoped
  access for the specific file chosen, without a blanket storage
  permission.

The dangerous permission to avoid is `MANAGE_EXTERNAL_STORAGE` — it
grants broad access to shared storage and draws heavy Play Store
scrutiny. Only needed if writing outside app-private storage without SAF.

This assumption must be verified before v1 — see bikeshed.

---

## Flutter — file_picker v11 API

The correct call is `FilePicker.pickFiles()` directly — no `.platform`
intermediary. Pass `withData: true` to get file bytes in memory (required
on Android where file paths are not directly accessible). The result is a
`FilePickerResult?`; access bytes via `result.files.first.bytes`.

```dart
final result = await FilePicker.pickFiles(withData: true);
if (result == null || result.files.isEmpty) return;
final bytes = result.files.first.bytes; // Uint8List?
```

## Clipboard security — auto-clear limitations

`Clipboard.setData(ClipboardData(text: ''))` clears the *system* clipboard —
the next paste from any app will be empty. However, clipboard manager apps
(Samsung Keyboard history, KDE Klipper, Gboard history) maintain their own
ring buffer of recent clips stored separately from the system clipboard.
Gabbro has no API access to these — they survive our clear.

Auto-clear is therefore best-effort: it closes the accidental-paste window
but cannot reach clipboard history managers. Always inform the user of this
limitation (Gabbro does so via the copy snackbar). Document honestly in
`docs/SECURITY.md` when written.

Python analogy: like `del my_dict['key']` — removes the reference, but if
another dict also holds the value, it persists.

## Autofill vs clipboard — security distinction

Autofill does not use the OS clipboard. Credentials go directly from the
autofill service into the target field via the OS autofill framework —
clipboard history managers never see them. This is a meaningful security
advantage over copy-paste. See ARCHITECTURE.md Bikeshed for implementation
notes.

## Flutter — App Lifecycle & Auto-lock

### WidgetsBindingObserver
A mixin that lets a `State` class listen to app lifecycle events.
Register with `WidgetsBinding.instance.addObserver(this)` in `initState`,
deregister in `dispose`. Override `didChangeAppLifecycleState` to react
to state changes.

### AppLifecycleState
Key states for auto-lock:
- `paused` — app fully backgrounded or screen off. Start the background timer here.
- `resumed` — app returned to foreground. Cancel the background timer, restart the foreground timer.
- `detached` — app process being torn down. Lock immediately, no timer needed.
- `inactive` — brief focus loss (notification shade, etc.). Ignored for locking — too aggressive.

### GlobalKey<NavigatorState>
When navigation must happen from outside the widget tree (e.g. a timer
callback in `_GabbroAppState`), pass a `GlobalKey<NavigatorState>` to
`MaterialApp` via `navigatorKey`. Then call
`_navigatorKey.currentState?.pushAndRemoveUntil(...)` to navigate and
clear the stack. The `pushAndRemoveUntil` with `(_) => false` predicate
removes all routes — correct for a lock event where returning to the
previous screen would bypass security.

### Foreground inactivity detection
Wrap the entire `MaterialApp` in a `GestureDetector` with
`HitTestBehavior.translucent` so it receives events without blocking
child widgets. Reset the foreground timer on `onTap` and `onPanDown`.
This catches taps and scrolls without needing to instrument individual
screens.

### Timer in Dart
`dart:async` `Timer` fires a callback once after a duration.
Cancel with `timer.cancel()` before it fires to abort.
Python analogy: `threading.Timer` — same concept, same cancel pattern.
Always cancel in `dispose` to avoid callbacks firing on a dead widget.

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
AES-256-GCM requires a 12-byte nonce for every encryption
operation. It must never repeat for the same key — if it does,
the encryption is broken. Generated randomly at seal time,
stored in the vault file header, read back at open time.

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

### Diceware / EFF Wordlists
A method of generating passphrases by selecting words randomly
from a large wordlist. The EFF large wordlist contains 7776 words
(6^5 — corresponding to five dice rolls), giving ~12.92 bits of
entropy per word. Some lists (e.g. ES, IT variants used in Gabbro)
contain 8192 words (2^13), giving exactly 13.00 bits per word.
A 4-word passphrase from a 7776-word list gives ~51.7 bits of
entropy — considered the practical minimum for security.
A 6-word passphrase gives ~77.5 bits — comfortably strong.

### Passphrase Entropy Minimum
From a security standpoint, a passphrase must have at least 4 words
to be considered acceptable. Fewer words (1–3) from any standard
wordlist produce insufficient entropy regardless of list size.
Gabbro enforces this as a hard minimum in `PassphraseConfig`.

### ML-DSA — Post-Quantum Digital Signature Algorithm
The signature half of NIST's post-quantum standard. DSA = Digital
Signature Algorithm — used to *prove identity* (authentication). A
private key signs a challenge; the other party verifies with the
public key. Analogous to a wax seal: proves the message came from
you and wasn't tampered with.
Contrast with ML-KEM, which *establishes a shared secret* (key
exchange). These solve different problems: ML-DSA proves who you
are; ML-KEM sets up an encrypted channel.

### ML-DSA parameter sets (ML-DSA-44 / 65 / 87)
ML-DSA comes in three parameter sets corresponding to NIST security
levels 2, 3, and 5 respectively. Higher levels = larger signatures
+ more compute, in exchange for a larger security margin.
- ML-DSA-44: Level 2 (~SHA-256 collision resistance equivalent).
  Signature size ~2.4 KB.
- ML-DSA-65: Level 3 (~AES-192 equivalent). ~3.3 KB.
- ML-DSA-87: Level 5 (~AES-256 equivalent). ~4.6 KB.
Gabbro targets ML-DSA-44. Level 2 is already beyond conservative
for authentication; the extra size of Level 3/5 buys protection
against attacks that don't currently exist. The gap between Level 2
and Level 3 is not worth the bytes — like rating a safe for a
storm category that doesn't exist.

### NIST Security Levels
A 1–5 scale used to compare post-quantum algorithm parameter sets.
Roughly: Level 1 ≈ AES-128, Level 2 ≈ SHA-256 collision resistance,
Level 3 ≈ AES-192, Level 5 ≈ AES-256. Not a direct equivalence —
more a "how hard is the best known attack" comparison. Higher is
stronger but costs more in key/signature size and compute time.

### Hybrid classical + PQ (signatures)
A scheme that bundles two signatures — one classical (e.g. ECDSA)
and one post-quantum (e.g. ML-DSA) — into a single object. Both
must verify for authentication to succeed. Rationale during the
transition period: trust ECDSA's 20-year track record while hedging
on the newer ML-DSA. Now considered the wrong tradeoff for *new*
deployments: ML-DSA has two years of production use, quantum
timelines have accelerated, and the complexity cost of hybrid
signatures outweighs the hedge benefit. Hybrid *key exchange*
(ML-KEM + classical) remains reasonable because ephemeral keys are
cheap to compose — but that reasoning does not carry over to
authentication.

### Composite signatures
The formal IETF standardisation of hybrid signatures: a defined
wire format for bundling two signatures (e.g. ECDSA + ML-DSA) into
a single object, with a standard key type and verification procedure.
Draft: draft-ietf-lamps-pq-composite-sigs-15 (18 composite key
type combinations). High complexity cost for Gabbro: no legacy
compatibility requirement means no benefit from composite signatures.
Not used in Gabbro.

### WebAuthn / FIDO2 / YubiKey — the stack
Three layers that work together for hardware authentication:
- **YubiKey**: the physical device. Does the actual cryptographic
  signing in tamper-resistant hardware. Private key never leaves
  the device.
- **FIDO2**: the protocol between the app and the hardware key.
  Defines how challenges are issued, how credentials are stored,
  how signatures are returned.
- **WebAuthn**: the API your application code calls. Says "ask the
  user to tap their key and return a signed challenge." The app
  doesn't talk to the YubiKey directly — it calls WebAuthn, which
  handles the FIDO2 protocol.
In Flutter/Dart, the app calls a WebAuthn library; the YubiKey does
the signing; the app verifies the returned signature. Algorithm
selection happens via the `pubKeyCredParams` parameter at credential
creation time.

### YubiKey hardware support gap (PQ)
Current YubiKey 5 series hardware (as of April 2026) supports
Ed25519 and ECDSA for FIDO2 — not ML-DSA. Gabbro's target
algorithm is ML-DSA-44, but this depends on Yubico shipping
PQ-capable hardware or firmware (likely Series 6 or equivalent).
Gabbro v1 therefore uses Ed25519 as the FIDO2 signature algorithm
— the strongest available classical option. The auth layer is
designed for a clean migration to ML-DSA-44 when hardware supports
it. This is documented honestly in ADR-005. The PQ claim for Gabbro
v1 rests on the *encryption* stack (ML-KEM + AES-256-GCM), not the
authentication layer.

### Authentication vs key exchange — two different problems
- **Authentication** (ML-DSA): proves identity. "Who are you?" 
  You sign a challenge with your private key; the other party
  verifies. Used in Gabbro's Layer 2 (YubiKey unlock).
- **Key exchange** (ML-KEM): establishes a shared secret. "How do
  we encrypt our conversation?" Neither party knows the secret in
  advance — they derive it together. Used in Gabbro's Layer 1
  (vault encryption).
Independent operations. Changing the signature algorithm does not
touch the vault encryption, and vice versa.

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
The "+1" variant (3-2-1+1) adds an immutable or air-gapped
copy for extra resilience. Gabbro's development repo already
follows this: local machine + NAS sync + Synology HyperBackup
offsite = 3-2-1+1 in practice.

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

### Enum as internal plumbing vs UI concern
When a Rust enum (e.g. `Language`) is exposed across the bridge,
its variant names are internal identifiers — not user-facing strings.
The Flutter/Dart layer is responsible for mapping enum variants to
display text in whatever language or format the UI requires.
This keeps Rust free of UI concerns and makes localisation trivial.

### Compile-time asset embedding (`include_str!`)
`include_str!("path/to/file")` reads a file at compile time and
embeds its contents as a `&'static str` directly in the binary.
Zero runtime I/O, zero risk of missing files at runtime. Ideal
for fixed assets like wordlists. The path is relative to the
source file containing the macro.

### Module separation: `api/` vs `vault/`
`rust/src/api/` is the bridge boundary — only what Flutter needs
to call lives here. `rust/src/vault/` is the internal domain model
— the core types and logic, invisible to Flutter until explicitly
exposed via an API function. Keeping these separate follows the
principle of separating your domain model from your interface layer.

### Composition over inheritance
Rust has no class inheritance. Shared data is modelled by embedding
one struct inside another (`pub meta: EntryMeta`). To access a field
on the inner struct: `entry.meta.id`. This is more explicit and
flexible than inheritance — the relationship is "has a", not "is a".

### Making invalid state unrepresentable
A core Rust design principle: if a value cannot exist in a valid
domain, use the type system or constructor to prevent it from being
created at all. Example: `CardEntry::new()` rejects card numbers
outside 12–19 digits — invalid entries simply cannot exist in the
vault.

### Single source of truth for shared types
When two modules need the same type, define it once in the most
appropriate module and import it everywhere else. In Gabbro,
`SealedVault` was initially defined separately in both
`vault_crypto.rs` and `vault/file_format.rs`. The fix was to
keep the single definition in `vault/file_format.rs` (where it
belongs — it describes the file format) and have `vault_crypto.rs`
import it. Two definitions of the same concept is a maintenance
hazard: they drift apart, and the compiler cannot catch the
inconsistency.

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

### Crate
Rust's unit of compilation and distribution. A crate is Rust's equivalent 
of a Python package — a reusable unit of code you can add as a dependency.
The [dependencies] section of `Cargo.toml` is directly analogous to 
`requirements.txt` or `pyproject.toml` dependencies.
`cargo add uuid` is equivalent to `pip install uuid`.
Two types of crate:
- library crate (`lib`) — provides code for others to use, like a Python
library. Gabbro's `rust_lib_gabbro` is one.
- binary crate (`bin`) — produces an executable, like a Python script
with `if __name__ == "__main__"`.

`crates.io` is the registry, analogous to PyPI. `Cargo.toml` is the
manifest, analogous to `pyproject.toml`. `Cargo.lock` pins exact 
versions, analogous to `pip freeze`.

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

### .gitignore
A file at the root of a git repository that tells git which files and
folders to ignore — i.e. never track or commit. Essential for excluding
build artefacts, IDE settings, and development-only folders that have
no place in version control. A trailing slash (e.g. `chat_info/`) tells
git the entry is a directory. Flutter projects ship with a
generated `.gitignore`; project-specific exclusions are added manually.

### git remote
A named reference to a remote repository. `origin` is the conventional
name for the primary remote. Set with:
`git remote add origin git@github.com:user/repo.git`
Verify with: `git remote -v`
Push with: `git push -u origin master` (the `-u` sets upstream tracking
so future `git push` commands need no arguments).

### SSH key authentication (GitHub)
An alternative to password authentication for git remotes. Generate a
key pair with `ssh-keygen`, add the public key to GitHub under
Settings → SSH and GPG keys, then use the SSH remote URL
(`git@github.com:user/repo.git`) instead of HTTPS. The private key
never leaves your machine. More secure and more convenient than
passwords for repeated pushes.

### `wc -l`
Unix command to count lines in a file. Used to verify wordlist sizes:
`wc -l wordlist_en.txt` → `7776 wordlist_en.txt`. Essential sanity
check when processing external files before embedding them.

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

## Rust & Bridge Concepts

### Returning failures alongside successes — tuple return pattern
When an operation can partially succeed (some items valid, some not),
return a tuple `(Vec<Success>, Vec<Failure>)` rather than `Result<Vec<Success>, Error>`.
The `Result` wrapper still handles catastrophic failure (malformed JSON),
while the tuple handles per-item validation failures. In Gabbro:
`parse()` returns `Result<(Vec<VaultEntry>, Vec<ParseFailure>), String>` —
`Err` only for unparseable JSON; the tuple for per-item outcomes.
Python analogy: a function returning `(results, errors)` where `errors`
is a list of `(item, reason)` pairs.

### `pub(crate)` — crate-internal visibility
`pub(crate)` makes an item visible anywhere within the current crate but
not to external crates. Used for `ParseFailure` and `parse()` in the
importer modules — they are called by `api/import.rs` (same crate) but
should never be part of the public bridge API. More restrictive than `pub`,
more permissive than private. Python analogy: a leading `_` convention,
but enforced by the compiler.

### `map_err` — transforming error types
`result.map_err(|e| transform(e))` converts a `Result<T, E>` into a
`Result<T, F>` by applying a closure to the error value only. Used to
convert `String` errors from `CardEntry::new()` into `ParseFailure`
structs at the call site in `convert_item`. The success path is
unchanged. Python analogy: wrapping a caught exception in a different
exception type before re-raising.

### `extract_raw_fields` — canonical key mapping at the boundary
When collecting raw field values for failure reporting, map source-specific
field type strings to Gabbro canonical key names at the extraction point
(`"ccNumber"` → `"card_number"`, `"ccName"` → `"cardholder_name"`, etc.).
This keeps the Flutter layer ignorant of source-specific naming — it only
ever sees Gabbro canonical keys. Unknown field types fall back to the
source label. Always include `"title"` as the first entry so `CreateEntryScreen`
can prefill the entry name field.

### `#[cfg(test)]`
A Rust attribute that marks a block as test-only. Code inside
`#[cfg(test)]` is compiled only when running `cargo test` — it
is never included in release builds. The idiomatic place for unit
tests in Rust is directly in the same file as the code under test,
inside a `mod tests { ... }` block gated by this attribute.

### `Result<T, E>` in Rust
Rust's primary error-handling type. A function returning
`Result<String, String>` either succeeds with `Ok(value)` or
fails with `Err(message)`. The caller must handle both cases.
Used in `generate_password()` to signal an empty character pool
rather than panicking. The bridge maps this to a Dart exception.

### `cargo-expand`
A Cargo subcommand that macro-expands Rust source code, showing
what proc-macros (like `flutter_rust_bridge`) generate under the
hood. `flutter_rust_bridge_codegen` installs it automatically on
first run if missing. Not needed for day-to-day development.

### `flutter_rust_bridge_codegen generate`
The command that reads your Rust API surface and regenerates the
Dart bridge files in `lib/src/rust/`. Must be re-run any time you
add, remove, or change a public Rust function or struct that
crosses the bridge. Generated files should never be edited manually.

### `pub` — visibility modifier
In Rust everything is **private by default** — functions, structs, and
fields are invisible outside their module unless explicitly marked `pub`
(public). This is the opposite of Python, where everything is public by
default and a leading `_` is only a convention. In Rust, `pub struct`
makes the type visible, but fields must also be individually marked `pub`
— the struct being public does not automatically make its fields public.

### `struct`
A fixed, named collection of typed fields — closer to a Python dataclass
than a dict. Fields and their types are declared at compile time; the
compiler rejects any code that creates one with missing fields or wrong
types. Unlike a Python dict, you cannot add or remove fields at runtime.

### `enum` in Rust
A type that can be one of a fixed set of named variants. Unlike Python
enums, Rust enums are first-class types used throughout the language —
including in `match` expressions. Each variant can optionally carry
data. Used in Gabbro for `Language` to represent the five supported
wordlist languages as a closed set of valid choices.

### `match` in Rust
Rust's pattern matching expression — like a `switch` statement but
exhaustive: the compiler forces you to handle every possible variant.
Used in `wordlist_for()` to select the correct embedded wordlist
string for each `Language` variant. If you add a new variant to
the enum and forget to update the `match`, the compiler refuses
to compile.

### `..default_config()` — struct update syntax
When constructing a struct in tests, you often want to override just
one or two fields and keep the rest at their defaults. Rust's struct
update syntax `..default_config()` fills in all unspecified fields
from the result of that function call. Reduces repetition and makes
test intent clearer — only the field under test is mentioned explicitly.

### `for bad_count in [0, 1, 2, 3]`
In Rust you can iterate directly over a small array literal in a `for`
loop. Useful in tests to check a function rejects multiple invalid
inputs without writing a separate test for each value.

### `assert!` with custom message
`assert!(condition, "message {}", value)` — the second argument is a
format string printed if the assertion fails. Essential when looping
in tests: without it, a failure only tells you the assertion failed,
not which iteration caused it.

### `const` inside a function
In Rust, `const` can be declared inside a function body, not just at
module level. It is still a compile-time constant — no runtime cost —
but its scope is limited to the enclosing function. Used in
`generate_passphrase` for `MIN_WORD_COUNT` to keep the magic number
close to where it is used.

### `chars()` and Unicode-safe capitalisation
`string.chars()` returns an iterator over Unicode scalar values, not
bytes. To capitalise the first letter of a word safely:
1. Call `.chars()` to get an iterator
2. Take the first char with `.next()`
3. Call `.to_uppercase()` on it (returns a string, not a char, because
   some Unicode characters uppercase to multiple characters)
4. Concatenate with `chars.as_str()` for the remainder
This is more correct than indexing bytes directly, which would panic
on non-ASCII input.

### Test helper / default fixture pattern
When writing multiple tests that share a common setup, define a
helper function (e.g. `default_config()`) that returns a baseline
value. Each test then only overrides the fields relevant to it.
Reduces repetition and makes test intent clearer.

### Testing randomness with large samples
For functions that produce random output, use a large output length
(e.g. 200 characters) to make it statistically near-certain that
all parts of the character pool are sampled. This lets you assert
properties (e.g. "no banned characters appear") without flaky tests.

### `///` — doc comments
Two slash styles in Rust: `//` is a regular comment; `///` is a doc
comment, equivalent to a Python docstring. `cargo doc` reads `///`
comments and generates HTML documentation for your project. Convention
is to use `///` on all public-facing items.

### `//!` — module-level doc comments
Where `///` documents the item that follows it, `//!` documents the
enclosing item — typically the file/module itself. Written at the top
of a file, it appears as the module description in `cargo doc` output.

### Attributes — `#[...]`
Metadata attached to a function, struct, or module that changes how it
is compiled or processed. Examples seen so far:
- `#[cfg(test)]` — compile this block only in test mode
- `#[test]` — mark this function as a test for `cargo test`
- `#[flutter_rust_bridge::frb(sync)]` — instruct the bridge codegen
  to expose this function as synchronous rather than async
- `#[derive(...)]` — auto-generate trait implementations

### `#[flutter_rust_bridge::frb(sync)]`
Tells the bridge code generator to expose a function as synchronous —
the generated Dart function returns a plain value instead of a `Future`.
Appropriate for fast in-memory operations like password generation where
there is no I/O and no reason for Flutter to await the result.

### `fn` and `pub fn`
`fn` declares a function in Rust, equivalent to `def` in Python.
`pub fn` makes it visible outside the current module. Key differences
from Python `def`:
- Parameter types and return type are mandatory, not optional hints
- Return type is declared with `->`
- The last expression in the function body is automatically the return
  value if written without a semicolon — no `return` keyword needed
- `return` is used for early exits only (see below)

### Early return vs final expression
In Rust, `return` is used to exit a function before reaching the end.
The final return value is written as a bare expression without a
semicolon — the semicolon discards the value. Pattern for `Result`-
returning functions: multiple `return Err(...)` early exits for failure
cases, with `Ok(value)` as the final expression for the happy path.
A function can have as many `return Err(...)` as needed.

### `let` and `mut`
`let` declares a variable. Variables are **immutable by default** in
Rust — you cannot change them after binding. `mut` opts in to
mutability: `let mut rng = ...`. This is the opposite of most languages.
The compiler enforces immutability, catching a whole class of bugs at
compile time.

### `use` — imports
Rust code can always refer to anything by its full path (`rand::thread_rng()`).
`use` brings a name into scope so you can use it without the full path,
equivalent to Python's `from x import y`. `use` can appear at the top
of a file or inside a function — it scopes to wherever it is declared.
Sometimes you must `use` a **trait** just to unlock methods on a type,
even if you never write the trait name directly (e.g. `use rand::Rng`
to make `.gen_range()` available).

### `::` — path separator
Rust's path separator for navigating modules, crates, and types.
Equivalent to Python's `.` in imports. Also used to call type-level
(static) functions: `String::from("hi")`, `Vec::new()`. Instance
methods use `.` as in Python: `my_string.len()`.

### Macros — `name!(...)`
A `!` after a name means it is a macro, not a regular function. Macros
generate code at **compile time**, before the compiler processes the
rest of your code. This lets them do things regular functions cannot:
- Accept a variable number of arguments — `println!("{} {}", a, b)` or
  `println!("{}", a)` — a regular function can't do that in Rust
- Accept different types each call — `assert_eq!` works on integers,
  strings, structs, anything
- Inspect the source code itself — `assert_eq!` prints the variable
  names on failure because the macro sees them before they're evaluated

Common macros in Gabbro: `format!`, `println!`, `assert!`, `assert_eq!`,
`assert_ne!`, `vec!`, `panic!`. The `!` is purely a signal meaning
"macro call" — it has nothing to do with negation. This is an
unfortunate collision with how most languages use `!` to mean "not":
Rust uses `!` for two unrelated things — negation (`!true == false`)
and macro invocation (`vec![...]`).

The Python analogy is imperfect, but decorators are the closest thing
— they wrap and transform code. Macros are more powerful but serve a
similar "code that operates on code" purpose.

### `assert!` and `assert_eq!`
Test assertion macros. `assert!(condition)` panics if the condition is
false. `assert_eq!(a, b)` panics if the two values are not equal, and
prints both values in the error message (`eq` = equal). Its counterpart
`assert_ne!(a, b)` asserts the values are not equal (`ne` = not equal).
Both accept an optional format string: `assert!(cond, "message {}", value)`.

### Panicking
A panic is Rust's "unrecoverable error" mechanism — it stops execution
immediately. `assert!` panics when its condition is false. Outside tests
a panic crashes the program. Inside a `#[test]` function the test runner
catches the panic and records that test as failed, then continues running
the remaining tests.

### `#[test]` and `#[cfg(test)]` — how they work together
- `#[test]` marks a function so `cargo test` knows to run it
- `#[cfg(test)]` gates an entire block so the compiler excludes it
  from release builds entirely — the code does not exist in the
  shipped binary
- They are independent: `#[test]` is about the runner finding tests;
  `#[cfg(test)]` is about the compiler stripping them from production
- Convention: wrap all tests in `#[cfg(test)] mod tests { ... }` so
  they live next to the code they test but cost nothing in production

### `use super::*` in tests
`super` refers to the parent module. Inside `mod tests`, `use super::*`
brings everything public from the containing module into scope —
equivalent to Python's `from .. import *`. This is one of the few
places in Rust where wildcard imports are considered idiomatic, because
test modules conventionally want access to everything they are testing.

### snake_case → camelCase (bridge convention)
The bridge automatically translates Rust's `snake_case` naming to
Dart's `camelCase`: `generate_password` → `generatePassword`,
`pool_size` → `poolSize`. Each language gets idiomatic naming
without any manual mapping.

### `impl` block
Attaches functions and methods to a type. Defined separately from the
`struct` or `enum` definition. Functions inside `impl` that don't take
`self` are **associated functions** (called as `MyType::fn_name(...)`).
Functions that take `&self` or `&mut self` are **instance methods**
(called as `value.method()`).

### Associated function / constructor pattern
Rust has no `__init__`. The convention is a `new()` associated function
that returns `Result<T, E>` when construction can fail. This is the
idiomatic way to validate data at creation time — if `new()` returns
`Ok`, the value is guaranteed valid; if it returns `Err`, nothing was
created.

### `Option<T>` — nullable values without null
Rust has no `null` or `None` at the language level. A value that might
be absent is wrapped in `Option<T>`, which is either `Some(value)` or
`None`. The compiler forces you to handle both cases before using the
value. Key methods: `.is_some()`, `.is_none()`, `.unwrap()` (panics on
None — safe in tests after asserting `is_some()`, avoid in production).

### Cloning and the move problem
When you assign a value to a field or variable in Rust, ownership
transfers — the original is gone. If you need to use the same value
twice, `.clone()` makes an explicit deep copy first:

```rust
let now = chrono_now();
created_at: now.clone(),  // copy goes here
updated_at: now,          // original moves here — now is gone after this
```

Convention: move the original into the last use to avoid an unnecessary
clone. You can clone every use if you prefer clarity over micro-efficiency,
but idiomatic Rust avoids cloning more than needed.

In Python this is invisible because objects are reference-counted.
In Rust, ownership makes it explicit.

### `Vec<u8>` — raw binary data
A `Vec` of unsigned 8-bit integers (`u8`). The standard Rust
representation for binary payloads (file contents, encrypted bytes,
etc.). Equivalent to Python's `bytes` or `bytearray`. The `u8` suffix
on a literal (e.g. `255u8`) explicitly types it as an unsigned byte.

### `HashMap<K, V>`
Rust's dictionary type. `HashMap<String, CustomField>` is a map from
`String` keys to `CustomField` values. Create with `HashMap::new()`,
insert with `.insert(key, value)`, access with `map[key]` or
`.get(key)`. Requires `use std::collections::HashMap`.

### Closures — `|param| expression`
Anonymous functions, like Python lambdas. Used heavily with iterators:
`.filter(|c| c.is_ascii_digit())` passes each element to the closure
and keeps only those where it returns true. The `|param|` syntax is the
closure's parameter list.

### Iterator chaining
Rust iterators are lazy and composable. Common pattern:
`.chars().filter(...).count()` — get an iterator over characters, keep
only those matching a predicate, count the results. Nothing is computed
until the chain is consumed (here by `.count()`).

### Struct composition — embedding one struct inside another
Rust has no inheritance. Instead, types share data through composition —
embedding one struct as a named field inside another. In Gabbro, `EntryMeta`
holds the six fields common to every entry type (id, timestamps, folder, tags,
favourite). Each entry type then has a field named `meta` of type `EntryMeta`:

```rust
pub struct NoteEntry {
    pub meta: EntryMeta,   // EntryMeta composed in as a field
    pub title: String,
    pub content: String,
}
```

To reach a composed field you chain the dots: `entry.meta.created_at`,
`entry.meta.id`. This is identical to Python dataclass composition:

```python
@dataclass
class NoteEntry:
    meta: EntryMeta
    title: str

entry.meta.created_at  # same dot-chaining
```

The benefit over flattening all fields directly onto each struct is DRY —
define the shared fields once in `EntryMeta`, compose them into all six entry
types. Change `EntryMeta` once and every entry type picks up the change.

### DTO — Data Transfer Object
A DTO is a plain struct whose only job is to carry data across a boundary —
in Gabbro's case, across the Flutter/Rust bridge. The internal domain types
(`LoginEntry`, `NoteEntry`, etc.) are rich Rust types that flutter_rust_bridge
cannot serialize directly. The DTO equivalents (`LoginEntryData`,
`NoteEntryData`, etc.) in `api/vault.rs` use only bridge-friendly types
(`String`, `Vec`, `bool`, `Option<String>`) and exist solely to move data
to Flutter. The pattern is: build the internal type, do any logic on it,
then convert to the DTO for the return value. Flutter never sees the
internal type.

### `crate` — Rust's unit of compilation and distribution
A crate is Rust's equivalent of a Python package — a reusable unit of code
you can add as a dependency. The `[dependencies]` section of `Cargo.toml`
is directly analogous to `requirements.txt` or `pyproject.toml` dependencies.
`cargo add uuid` is equivalent to `pip install uuid`.

Two types of crate:
- **library crate** (`lib`) — provides code for others to use, like a Python
  library. Gabbro's `rust_lib_gabbro` is one.
- **binary crate** (`bin`) — produces an executable, like a Python script
  with `if __name__ == "__main__"`.

`crates.io` is the registry, analogous to PyPI. `Cargo.toml` is the manifest,
analogous to `pyproject.toml`. `Cargo.lock` pins exact versions, analogous
to `pip freeze`. Many crates ship optional functionality behind **feature
flags** to keep compile times and binary sizes down — enabled with the
`--features` flag: `cargo add uuid --features v4`.

### `#[derive(Debug, Clone, PartialEq)]`
A derive attribute that auto-generates three trait implementations:
- `Debug` — enables `{:?}` formatting; needed for readable test failure
  messages
- `Clone` — generates a `.clone()` method for deep copies
- `PartialEq` — generates `==` and `!=`; required for `assert_eq!` in
  tests. Not added to every type by default — equality semantics should
  be considered deliberately (e.g. do two entries with the same id but
  different timestamps count as equal?). Every field in a struct must
  also implement `PartialEq` for the containing struct to derive it.

### `into_values()` on HashMap
Consumes a `HashMap` and returns an iterator over its values only,
discarding the keys. Used in `custom_entry_to_data()` to flatten
a `HashMap<String, CustomField>` into a `Vec<CustomFieldData>` for
the bridge — the map key is redundant because each `CustomField`
already carries a `label`.

### Entropy estimation — lower-bound approach
When estimating the entropy of a user-typed string, we detect which character
classes are present (lowercase, uppercase, digits, symbols, non-ASCII) and sum
their full pool sizes. We never apply the `exclude_ambiguous` reduction because
the estimator only sees the string, not the generator config. Using the full
pool size is the conservative choice: it may slightly overestimate entropy for
generated passwords, but avoids underestimating for manually typed ones.
Formula: `entropy = length × log₂(pool_size)`. See `rust/src/api/entropy.rs`
for tier thresholds and references.

### `to_be_bytes()` / `from_be_bytes()` — big-endian serialization
`be` stands for **big-endian**, not the verb "to be". Big-endian means the
most significant byte comes first — the same order humans write numbers
(thousands before hundreds before units). Its counterpart is `to_le_bytes()`
for little-endian (least significant byte first).

These are a matched pair: always use `to_be_bytes()` to write and
`from_be_bytes()` to read back, and you recover the original number.
Big-endian is the conventional byte order for file formats and network
protocols (sometimes called "network byte order"). In Gabbro, Argon2id
parameters and the body length field are all written as big-endian bytes
in the `.gabbro` file header.

`to_bytes()` does not exist as a standard method on integers in Rust —
the question "give me the bytes of this number" is ambiguous without
specifying byte order. The explicit `to_be_bytes()` / `to_le_bytes()`
naming removes the ambiguity.

### Binary serialization with a cursor
Hand-written binary serialization reads a flat byte slice by maintaining
a `pos` (position) index that tracks how far through the data we are.
The pattern for each field:
1. Check `data.len() >= pos + field_size` — return `Err` if not enough bytes
2. Read `data[pos..pos + field_size]` — a range slice of exactly the right size
3. Convert the slice to the target type (`try_into().unwrap()` for fixed arrays,
   `u32::from_be_bytes(...)` for integers, `.to_vec()` for owned byte vectors)
4. Advance `pos += field_size`

The `unwrap()` after `try_into()` is safe here because the length check
immediately above it guarantees the bytes are present — we are being
deliberate, not lazy. For variable-length fields (like the body), write
the length as a fixed-size integer first (a "length prefix"), then the
bytes themselves. On reading, read the length integer first, then read
exactly that many bytes.

This is the same pattern used by PNG, ZIP, and most binary file formats.

### Macros vs functions — when the `!` matters
A **function** is compiled to a fixed piece of code that runs at runtime,
with a defined number of parameters each of a specific type.

A **macro** runs at **compile time** and generates code before the
compiler processes it. This enables things functions cannot do:
- Variable number of arguments: `println!` accepts one argument or ten
- Works across different types without generics: `assert_eq!` compares
  integers, strings, or any type that implements `PartialEq`
- Access to source context: `assert_eq!` can print the variable names
  in a failure message because the macro sees the source before evaluation

The `!` suffix is purely syntactic — it marks a macro call, not negation.
Rust uses `!` for two unrelated things: boolean negation (`!true`)
and macro invocation (`vec![1, 2, 3]`). The distinction matters when
reading unfamiliar code: `some_function(x)` is a function call;
`some_macro!(x)` is a macro invocation that may generate arbitrarily
different code depending on its arguments.

### End-to-end testing across two subsystems
A test that exercises only the crypto layer (seal/open) and a test
that exercises only serialization (to_bytes/from_bytes) can both pass
while a bug at their boundary goes undetected. The end-to-end test
catches this: if any header field (e.g. HKDF salt, ML-KEM ciphertext)
is serialized or deserialized incorrectly, `open_vault` fails with a
decryption error — not a deserialization error — because the wrong
bytes are fed to the crypto layer. Neither half-test would surface this.

### Password masking — fixed-length placeholder
When displaying vault entries in a list, sensitive fields (passwords, CVVs,
hidden custom fields) are replaced with a fixed placeholder (`"********"`)
rather than a string of asterisks matching the actual length. The reason:
revealing that a password is exactly 14 characters long reduces the attacker's
search space. A fixed-length placeholder leaks nothing about the actual value.
The constant `MASKED_VALUE` is defined once in `api/vault.rs` and used
consistently across all masking logic.

### SHA-256 hex formatting — `hybrid_array` trait conflict
The `sha2` crate's `finalize()` returns a `GenericArray<u8, N>` type. In
Gabbro's dependency tree, a version conflict with `hybrid_array` (pulled in
by `ml-kem`) means `LowerHex` is not implemented for the returned type —
so `format!("{:x}", hash)` fails to compile. The fix is to convert the
`GenericArray` to a plain `[u8; 32]` with `.into()`, then format each byte
individually: `bytes.iter().map(|b| format!("{:02x}", b)).collect::<String>()`.
This sidesteps the trait conflict entirely and produces standard lowercase
hex output.

### `#[serial]` — test isolation for global state
When tests share a process-wide static (like `VAULT_SESSION`), Cargo's
default parallel test runner causes logical races: one test unlocks the
vault while another expects it to be locked, and they corrupt each
other's assumptions. A `Mutex` prevents data races but not logical ones —
two threads can each acquire the lock at different moments in a multi-step
test and still interfere.

The `serial_test` crate solves this with a `#[serial]` attribute that
forces marked tests to run one at a time, in sequence, even while the
rest of the suite runs in parallel:

```rust
use serial_test::serial;

#[test]
#[serial]
fn unlock_then_list_summaries_returns_entries() { ... }
```

Add it as a dev dependency: `serial_test = "3"` under `[dev-dependencies]`
in `Cargo.toml`.

Python analogy: running pytest with `-n 1` for tests that share
module-level state, or wrapping setUp/tearDown in a `threading.Lock()`
to prevent concurrent fixture mutation.

### `VaultSession` storing the passphrase — design decision
`VaultSession` holds three fields: `Vec<VaultEntry>`, `PathBuf`, and
`Vec<u8>` passphrase. Storing the passphrase feels surprising at first —
why keep a secret in memory longer than necessary?

The reason is mechanical: every mutating bridge call (`session_create_entry`,
`session_update_entry`, `session_delete_entry`, `session_change_passphrase`)
must persist the vault to disk immediately. Persisting means re-sealing from
scratch — Argon2id + ML-KEM + AES-256-GCM — and `seal_vault()` requires the
passphrase. The alternative — asking Flutter to re-supply the passphrase on
every mutating call — would mean it crossing the bridge on every save, which
is a worse exposure pattern.

The honest security accounting: the passphrase is already in Rust heap memory
from the moment `unlock_vault()` runs. Storing it in the session extends the
window slightly, but that window is already bounded by the auto-lock timer
and `lock_vault()`, which drops (and eventually `zeroize`s) the whole session.
This is the same tradeoff made by every desktop password manager that supports
background auto-save. It is intentional and documented.

`session_change_passphrase` updates the stored passphrase after re-sealing,
so the session stays consistent with what is on disk:

```rust
save_vault(&session.entries, new_passphrase, &session.path)?;
session.passphrase = new_passphrase.to_vec();
```

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

---

## Vault Crypto Stack

### The `||` notation in cryptography
In cryptographic specifications, `A || B` means concatenation —
A followed by B joined into a single byte sequence. Not a logical OR.
In Rust: `ikm.extend_from_slice(&a); ikm.extend_from_slice(&b)`.
In Python: `a + b` on byte arrays.

### Seeded RNG for deterministic keypair derivation
The `ml-kem` and `x25519-dalek` v2 crates do not accept raw byte
seeds directly for keypair generation — they require an RNG. To
derive keypairs deterministically from KDF output, we seed `StdRng`
(a cryptographically secure deterministic RNG from the `rand` crate)
with our KDF bytes, then pass it to the keypair generator. Same seed
→ same RNG stream → same keypair. This is the idiomatic approach;
the `ml-kem` crate's direct seed API (`hazmat` feature) is explicitly
marked unsafe for production use.

### Hybrid key exchange — the lock/unlock flow

```
SETUP: passphrase + salt → Argon2id → 96 bytes
bytes [0..32]  → seed StdRng → X25519 keypair
bytes [32..64] → seed StdRng → ML-KEM-1024 keypair
bytes [64..96] → reserved
LOCK:
ML-KEM encapsulate → ml_kem_ciphertext + shared_secret_A
X25519 ephemeral exchange → ephemeral_public + shared_secret_B
HKDF(A || B, salt, "gabbro-hybrid-kex-v1") → vault_key
AES-256-GCM(vault_key, plaintext) → ciphertext + nonce
UNLOCK:
Argon2id(passphrase, stored_salt) → same keypairs
ML-KEM decapsulate(stored_ciphertext) → shared_secret_A
X25519(stored_ephemeral_public) → shared_secret_B
HKDF(A || B, stored_salt, info) → vault_key
AES-256-GCM decrypt → plaintext
```

### Random session key vs passphrase-derived key
The vault body is encrypted with a random session key, not the
passphrase directly. The passphrase derives keypairs that
*encapsulate* the session key. Consequence: changing the passphrase
only requires re-running encapsulation — the vault body need not be
re-encrypted from scratch. This is the standard pattern in encrypted
storage.

### Argon2id benchmarking
Parameters should be benchmarked on target hardware, not just
copied from recommendations. Target range: 0.5–1.0s on the
development machine. On a 2011 desktop, m=65536/t=3/p=4 produced
84ms — too fast. t=25 produced 667ms — in the target range.
The bench_kdf binary in `rust/src/bin/` is the repeatable audit tool.
OWASP source: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html

### `*value` — dereferencing in Rust
The `*` operator dereferences a smart pointer or wrapper type,
giving access to the underlying data. The ml-kem crate returns
shared secrets as `hybrid_array::Array<u8, N>` — a fixed-size
array wrapper. `(*ml_kem_secret).try_into()` dereferences it to
a plain `[u8]` slice that `.try_into()` can then convert to
`[u8; 32]`. In Python this indirection is invisible because
everything is a reference already.

### Dependency version conflicts
When two crates in the dependency tree require different versions
of a shared dependency (e.g. `rand_core` v0.6 vs v0.10), traits
from one version are not compatible with types from the other —
even if the API looks identical. The fix is usually to reduce
dependencies rather than add version constraints. In Gabbro:
`rand_chacha` was removed in favour of `StdRng` from the already-
present `rand` crate, eliminating the conflict entirely.

---

## Flutter/Dart Bridge

### flutter_rust_bridge codegen — what it does
`flutter_rust_bridge_codegen generate` reads your Rust `api/` surface and
produces Dart stubs in `lib/src/rust/api/`. These files are auto-generated —
never edit them manually. Re-run codegen any time you add, remove, or change
a public Rust function or type that crosses the bridge.

### sync vs async across the bridge
- `pub fn` + `#[flutter_rust_bridge::frb(sync)]` → Dart calls it as a plain
  function, returns immediately, blocks the UI thread. Safe only for fast
  in-memory operations.
- `pub async fn` (no annotation needed) → Dart calls it with `await`, runs
  without blocking the UI. Required for anything slow — including Argon2id,
  which takes ~667ms on target hardware.

### Bridge-friendly types
Not all Rust types can cross the bridge. The rules:
- `std::path::Path` → use `String` instead; convert with `Path::new(&s)` inside
  the wrapper
- `&[u8]` → use `Vec<u8>` instead
- Internal domain enums/structs → wrap in bridge-facing DTOs

### `#[flutter_rust_bridge::frb(ignore)]`
Tells the codegen to skip a function entirely. Use this on internal Rust
functions that take non-bridge-friendly types and are not meant to be called
from Flutter. Without it, the codegen attempts to bridge them and fails to
compile.

### Bridge wrapper pattern
Keep pure Rust logic in the internal module (`vault.rs`). Create a separate
`vault_bridge.rs` in `api/` that wraps those functions with bridge-friendly
signatures. The wrapper converts types in, calls the internal function, and
converts types back out. This keeps the domain logic clean and the bridge
boundary explicit.

### Sealed classes in Dart (from Rust enums)
A Rust `pub enum` with data variants (e.g. `VaultEntryData`) is generated
as a Dart `sealed class` with factory constructors for each variant. Dart's
`switch` on a sealed class is exhaustive — the compiler forces you to handle
every variant, the same guarantee Rust's `match` provides.

### freezed and build_runner
flutter_rust_bridge uses `freezed` (a Dart code generation package) to
produce the sealed class hierarchy for Rust enums. `build_runner` is the
tool that runs the Dart code generation step. Both are dev dependencies.
Add them with:
  `flutter pub add --dev freezed`
  `flutter pub add freezed_annotation`
  `flutter pub add --dev build_runner`

### Flutter and Cargo commands — where to run them
- `flutter` commands (build, pub, etc.) → run from the project root (`gabbro/`)
  where `pubspec.yaml` lives
- `cargo` commands (`test`, `build`, `run`, `add`, `check`, etc.) → run from
  `gabbro/rust/` where `Cargo.toml` lives. This applies to every `cargo`
  subcommand without exception.
- `flutter_rust_bridge_codegen generate` → run from the project root (`gabbro/`)
- When in doubt: if the command starts with `cargo`, you're in `gabbro/rust/`;
  if it starts with `flutter`, you're in `gabbro/`.

### simple.rs — leave it alone
The generated `simple.rs` file contains two things: a demo `greet` function
and the required `init_app` boilerplate that Flutter calls once at startup.
Never delete or modify it. It serves as the bridge initialisation hook.

### Regenerating the bridge after API changes
Any time a public Rust function or type in `api/` is added, removed,
or renamed, the generated bridge files must be regenerated. Run from
the project root (`gabbro/`):

```
flutter_rust_bridge_codegen generate
```
This rewrites four files — `rust/src/frb_generated.rs`,
`lib/src/rust/api/vault_bridge.dart`, `lib/src/rust/frb_generated.dart`,
and `lib/src/rust/frb_generated.web.dart`. All four should be included
in the same commit as the Rust API change that triggered the regeneration.
Never edit these files manually — the next codegen run will overwrite them.

The symptom of a stale generated file is a `cargo build` error like:
`cannot find function save_vault_to_disk in module crate::api::vault_bridge`
— the generated code references a function that no longer exists in the
source. The fix is always to rerun codegen, not to edit `frb_generated.rs`.

### `usize` → `BigInt` in generated Dart
Rust's `usize` (used as a return type for counts like `import_from_csv`) is
mapped to Dart's `BigInt` by flutter_rust_bridge — not `int`. When a bridge
function returns `usize`, the generated Dart signature returns `Future<BigInt>`.
Convert to a plain Dart `int` with `.toInt()` at the call site when passing
to Flutter APIs that expect `int` (e.g. `Navigator.pop`, snackbar counts).

---

## Session Model & Memory Security

### Rust-owned session state — `Mutex` + `once_cell`
flutter_rust_bridge functions are stateless by default — each call is an
independent function call with no persistent `self` or instance on the Rust
side. To hold state (e.g. a decrypted vault) between calls, the idiomatic
pattern is a `Mutex<Option<T>>` wrapped in a `once_cell::sync::Lazy` static:

```rust
use once_cell::sync::Lazy;
use std::sync::Mutex;

static VAULT_SESSION: Lazy<Mutex<Option<VaultSession>>> =
    Lazy::new(|| Mutex::new(None));
```

`Lazy` initialises the value on first access (not at program start).
`Mutex` ensures only one thread can access the state at a time — required
because Flutter may call bridge functions from multiple isolates.
`Option` distinguishes "vault is unlocked" (`Some`) from "vault is locked"
(`None`). Locking the vault is then simply replacing the `Some` with `None`
and dropping the contents.

Python analogy: a module-level variable protected by a `threading.Lock()`,
initialised to `None` and set on first use.

### Stateless bridge vs stateful session — the distinction
A flutter_rust_bridge function with no side effects (e.g. `generate_password`)
is truly stateless — call it ten times, get ten independent results. A vault
operation (e.g. `get_entry`) needs to read from a previously-decrypted
in-memory vault — it is stateful. The session model bridges this gap: the
*function* is still a normal Rust function, but it reads from and writes to
a module-level `Mutex` static that persists for the lifetime of the process.
The bridge doesn't need to know about this — it just calls the function.

### Why Dart cannot zeroize memory
Dart is a garbage-collected language running on the Dart VM. The VM controls
object lifetimes, may intern strings (reuse the same allocation for equal
values), and makes no guarantee of zeroing memory before reuse. There is no
`zeroize` equivalent in Dart and no way to force an object to be collected
at a specific time. Any secret that crosses the Flutter/Rust bridge into Dart
is, from a strict security standpoint, uncontrolled — it may persist in the
Dart heap until the process exits. This is a known, accepted limitation shared
by every password manager built on a managed runtime (Bitwarden with
Xamarin/MAUI, 1Password with Electron, etc.). The session model limits Dart's
exposure by design: summaries only for list views, one full entry on demand,
never the whole vault.

### What `zeroize` actually buys — and what it doesn't
`zeroize` explicitly overwrites memory with zeros at a defined point (e.g.
when the vault locks). It uses volatile writes and memory fencing to prevent
the compiler or CPU from optimising the zeroing away. What it buys: a
**narrowed time window** — secrets exist in memory from decryption until the
explicit zero, rather than until the allocator happens to reuse that page.
For Gabbro's realistic threat (device seizure while unlocked, memory
forensics on a running device), this meaningfully reduces exposure.

What it does not guarantee:
- **Swap / hibernation** — the OS may have written the memory page to disk
  before the zero occurs; `zeroize` cannot reach those bytes
- **Cold boot attacks** — DRAM retains data for seconds to minutes after
  power loss; physical attackers with the right tools can recover it
- **OS memory snapshots** — mobile OSes may snapshot app memory for fast
  resume before the zero occurs

The conclusion: `zeroize` is one layer in a defence-in-depth stack, not a
silver bullet. It is worth doing; it is not sufficient alone.

### Full-disk encryption (FDE) as a security prerequisite
The memory security model — both `zeroize` in Rust and the session model's
minimal plaintext exposure — rests on a foundation of full-disk encryption.
Without FDE, an attacker with physical access to a powered-off device can
read the raw storage directly, bypassing all in-process protections. With FDE:
- **Android:** enforced by the OS since Android 10 — all user data partitions
  are encrypted by default. Gabbro can rely on this.
- **Linux:** dm-crypt/LUKS is the standard; it is the user's responsibility.
  Gabbro documents this dependency rather than pretending to solve it.

FDE does not protect against a device seized while unlocked (the key is
in memory). That is precisely the threat that `zeroize` + auto-lock address.
The two layers are complementary, not redundant.

### Lazy loading — summaries vs full entries
A vault with hundreds of entries should not be loaded across the bridge in
full on unlock. The session model enables lazy loading as the natural default:
- **List view:** Flutter requests `list_entry_summaries()` — lightweight DTOs
  with id, type, title, folder, tags, favourite. No passwords, no file data.
- **Detail view:** Flutter requests `get_entry(id)` — one full DTO, only when
  the user explicitly taps an entry.
- **Edit / save:** Flutter sends one entry back via `create_entry` or
  `update_entry` — Rust updates the session and persists the full vault.

This minimises both bridge traffic and Dart-side plaintext exposure. It is
not an optimisation added later — it is the correct default architecture from
the start, made natural by Rust owning the session state.

### `zeroize` — cryptographic memory clearing on lock
When `lock_vault()` runs, two things happen before the session is dropped:

```rust
s.passphrase.zeroize();  // cryptographic-grade zero — volatile writes
s.entries.clear();       // drops all heap-allocated String fields promptly
```

`Vec<u8>` implements `Zeroize` directly — the `zeroize` crate writes zeros
over the bytes using volatile writes and a compiler memory fence, preventing
the compiler or CPU from optimising the operation away. This is the correct
approach; overwriting with random bytes is not meaningfully more secure and
is slower.

`.clear()` on `Vec<VaultEntry>` drops all the nested `String` allocations
(passwords, notes, CVVs etc.) promptly, but does not guarantee byte-level
overwrite — the allocator may reuse those pages without zeroing them. Full
coverage requires deriving `Zeroize` on every struct in `entry.rs`, which
is a backlog item.

The window during which secrets are recoverable in RAM is bounded by the
auto-lock timer plus the time between lock and the next allocator reuse.
`zeroize` narrows this window — it does not eliminate it. Swap, cold boot
attacks, and OS memory snapshots remain outside its reach.

Python analogy: `del my_secret` removes the reference but doesn't touch
the bytes. `zeroize` is the equivalent of explicitly overwriting the
underlying buffer before releasing it — something Python gives you no
mechanism to do.

### Propagating a domain model change — the full blast radius
When you add a field to a core domain type like `CardEntry`, the compiler
finds every place that constructs or pattern-matches it. In Gabbro this
means touching: the struct definition, the validated constructor
(`CardEntry::new()`), all call sites of that constructor, any struct
literals (in tests and in `mask_entry`), the bridge-facing DTO
(`CardEntryData`), the DTO conversion function (`card_entry_to_data`),
the bridge conversion in `vault_bridge.rs`, and the auto-generated
`frb_generated.rs` (fixed by rerunning `flutter_rust_bridge_codegen generate`
from the project root).

The compiler guides you through every call site — treat the error list as
a checklist, not a problem. The correct order is: domain model first,
then callers, then bridge, then codegen. Running `cargo test --lib
vault::entry` after the domain model change confirms that layer is clean
before touching anything else.

### `ZeroizeOnDrop` and the move-out-of-Drop restriction
Deriving `ZeroizeOnDrop` on a type causes Rust to implement the `Drop`
trait for it. Rust enforces a rule: **you cannot move a field out of a
type that implements `Drop`**. This is because the compiler must be able
to run `drop()` on the original value, which requires the fields to still
be present.

Before `ZeroizeOnDrop`, code like this compiled fine:

```rust
fn entry_to_data(e: LoginEntry) -> LoginEntryData {
    LoginEntryData { password: e.password, ... }  // moves e.password out
}
```

After `ZeroizeOnDrop`, the same code fails with `E0509: cannot move out
of type LoginEntry which implements the Drop trait`.

Two fixes depending on context:
- **Conversion functions** — change signature to take `&LoginEntry`
  (a reference) and `.clone()` each field. The original value is never
  consumed, so `Drop` runs normally when it goes out of scope.
- **Match arms that mutate then return** — use `ref mut e` to borrow
  the inner value rather than move it, mutate through the reference,
  then return the outer enum value intact.

Python analogy: there is no direct equivalent, because Python has no
ownership model. The closest mental model is: if an object has a
`__del__` method, Python needs the object to remain whole so `__del__`
can access all its attributes at cleanup time. Rust enforces this
statically at compile time rather than at runtime.

### Holding a mutex lock across a slow operation causes deadlock

`std::sync::Mutex::lock()` returns a `MutexGuard` that holds the lock until
it is dropped. If you call a slow function (e.g. `save_vault()`, which runs
Argon2id) while still holding the guard, any other thread that tries to
acquire the same mutex blocks for the entire duration.

The fix is to clone the data you need out of the protected region, let the
guard drop by closing the block, then call the slow function outside it:

```rust
let (entries, passphrase, path) = {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;
    (session.entries.clone(), session.passphrase.clone(), session.path.clone())
}; // ← MutexGuard dropped here, lock released
save_vault(&entries, &passphrase, &path)?;
```

In Gabbro this surfaced as an apparent freeze when navigating back from
`CreateEntryScreen` while a save was in progress — `list_entry_summaries()`
was blocked waiting for the mutex that `session_create_entry` held across
the full Argon2id computation (~20s in debug builds).

---

## Flutter & Dart Concepts

### Returning a value from a dialog flow
`showDialog<T>` returns `Future<T?>` — the value passed to
`Navigator.of(context).pop(value)` inside the dialog. Use an enum to
distinguish actions: `pop(_FailureAction.edit)` vs `pop(_FailureAction.skip)`.
The caller `await`s the future and branches on the result. `null` means
the dialog was dismissed without a selection (barrier tap) — always guard
against it.

### Tracking side-effect counts across an async loop
When a loop of async operations can each independently produce a result
(e.g. "did the user save this entry?"), accumulate the count in a local
variable and return it from the enclosing function. In Gabbro,
`showImportFailuresDialog` returns `Future<int>` — the number of entries
saved via the Edit path. The caller adds this to `result.imported` before
popping with the total count. Keeping the accumulation inside the dialog
function keeps the call site clean.

### `prefill` vs `existing` on a form screen
`existing` carries a fully valid `VaultEntryData` from the vault — used
for edit mode. `prefill` carries raw `Map<String, String>` from a failed
import — used to pre-populate a new entry form with unvalidated data that
never made it into the vault. They are checked in order in `initState`:
`existing` wins if both are set (should not happen in production, but
defensive). `prefill` keys use Gabbro canonical names (`"card_number"`,
`"cardholder_name"`, `"title"`, etc.) so the form layer never needs to
know about source-specific field naming.

### `StatelessWidget` vs `StatefulWidget`
Every visible element in Flutter is a widget. A `StatelessWidget` is a pure
function of its inputs — it always draws the same thing given the same data.
A `StatefulWidget` has mutable state that can change over time, causing the
widget to redraw. The `UnlockScreen` is a `StatefulWidget` because it holds
changing data: the passphrase text, whether it is obscured, whether unlocking
is in progress, and any error message.

In Flutter, a `StatefulWidget` is always split into two classes: the widget
itself (immutable, describes the configuration) and its `State` object
(mutable, holds the data and builds the UI). The `_` prefix on
`_UnlockScreenState` marks it as private to the file — the same convention
as Python's `_private`.

Python analogy: a `StatelessWidget` is like a pure function; a
`StatefulWidget` is like a class with instance variables that trigger a
re-render when changed.

### `setState()`
The method that tells Flutter "something changed, please redraw this widget."
Without calling `setState()`, changing a variable in a `State` object has
no visible effect — the UI will not update. With it, Flutter schedules a
rebuild of just that widget and its children.

```dart
setState(() {
  _isUnlocking = true;  // change the variable inside the callback
});
```

The callback pattern (passing a function to `setState`) is idiomatic Flutter
— it makes clear exactly which variables are changing. Python has no direct
equivalent; the closest analogy is a reactive framework like React where
setting state triggers a re-render.

### `TextEditingController` and `dispose()`
A `TextEditingController` owns the contents of a text field. It lets you
read the current text (`_controller.text`), set it programmatically, or
listen for changes. Because it allocates resources, it must be explicitly
released when the widget is destroyed — this is done in the `dispose()`
method, which Flutter calls automatically when the widget leaves the screen.

Forgetting to call `_controller.dispose()` causes a memory leak. The
pattern is always: create in the state class, dispose in `dispose()`.

Python analogy: a context manager (`__enter__`/`__exit__`) that must be
closed when finished — except Flutter calls `dispose()` for you as long as
you override it correctly.

### `.codeUnits` — String to List\<int\>
The Rust bridge expects a passphrase as `Vec<u8>` (a list of bytes). Dart
strings are UTF-16 internally. `.codeUnits` converts a Dart `String` to a
`List<int>` of UTF-16 code units, which the bridge then maps to `Vec<u8>`.

```dart
_passphraseController.text.codeUnits  // "hello" → [104, 101, 108, 108, 111]
```

Python equivalent: `"hello".encode("utf-8")` → `b'hello'`. The concept is
identical — convert a human-readable string to raw bytes for a system that
works in bytes.

### `mounted` — safety check after `await`
After any `await` in Flutter, the widget may have been removed from the
screen while the async operation was running (e.g. the user navigated away).
Calling `Navigator` or `setState` on a widget that is no longer mounted
causes an error. The `mounted` property is `true` if the widget is still
in the tree, `false` if it has been disposed.

```dart
await someAsyncOperation();
if (mounted) {
  // safe to call setState or Navigator here
}
```

This is a Flutter-specific safety idiom with no direct Python equivalent —
it arises because Flutter's widget lifecycle and async operations run
concurrently.

### `#[ignore]` — skipping Rust tests by default
The `#[ignore]` attribute marks a test so it is skipped during a normal
`cargo test` run. It only executes when explicitly requested with the
`--ignored` flag:

```bash
cargo test my_test_name -- --ignored
```

Used in Gabbro for `create_test_vault_on_disk` — a test that writes a
real `.gabbro` file to `/tmp/` for development use. Running this on every
`cargo test` would be wasteful and leave files on disk unnecessarily.
`#[ignore]` keeps it available without making it part of the standard
test suite.

### Debug vs release build performance — Rust inside Flutter
Flutter's debug build compiles Rust in `dev` profile — unoptimised, with
debug symbols. Rust's optimiser makes a dramatic difference for
compute-heavy code like Argon2id:

- **Debug build:** ~20s for a single `unlockVault()` call
- **Release build:** ~667ms for the same call

This applies to Android too — `flutter build apk --debug` will be slow
for any vault operation. Always use `flutter build apk --release` for
any user-facing performance assessment on Android. Never tune Argon2id
parameters based on debug build timings on any platform.

This is not a bug — it is the expected behaviour of an unoptimised build.
For development, the slow unlock is an inconvenience we accept in exchange
for faster compile times and better error messages. For users, the release
build is always used. Never tune Argon2id parameters based on debug build
timings — always use `cargo run --bin bench_kdf --release`.

### Sealed classes in Dart — exhaustive switch over generated types
When flutter_rust_bridge generates a Dart type from a Rust `pub enum` with
data variants, it produces a `sealed class` hierarchy. Each variant becomes
a subclass (e.g. `VaultEntryData_Login`, `VaultEntryData_Note`). Dart's
`switch` on a sealed class is exhaustive — the compiler forces every variant
to be handled, the same guarantee Rust's `match` provides.

Destructuring pattern syntax: `VaultEntryData_Login(:final field0)` both
matches the subclass and unpacks the inner DTO in one step.

### `String?` vs `String` — nullable fields in generated Dart
Fields declared `Option<String>` in Rust become `String?` in Dart. You
cannot call `.isNotEmpty` or pass them to a `String` parameter directly.
The safe pattern: `if (e.field != null) _doSomething(e.field!)`.
The `!` asserts non-null after the explicit null check — safe here because
we just checked.

### `createEntry` vs `createLoginEntry` — session-aware vs standalone
`createLoginEntry` (in `vault.dart`) creates a standalone DTO with a new UUID
and timestamps — it does not touch the session or persist anything to disk.
`createEntry` (in `vault_bridge.dart`) adds the entry to the live session and
triggers a full vault save (Argon2id + encrypt + write). Always use `createEntry`
from the UI layer when the intent is to persist a new entry.

### Bottom sheet type picker pattern
`showModalBottomSheet<String>` returns a `Future<String?>` — null if the user
dismisses without selecting. The `<String>` type parameter is what each
`Navigator.of(context).pop(value)` inside the sheet returns. Await it, check
for null, then navigate.

### `VaultEntryData.login(...)` — factory constructor syntax
The generated `VaultEntryData` sealed class uses freezed factory constructors.
`VaultEntryData.login(loginEntryData)` wraps a `LoginEntryData` in the `Login`
variant. The id, createdAt, and updatedAt fields are passed as empty strings
from Flutter — Rust generates the real values inside `session_create_entry`.

### Two-path delete — list and detail screen
Delete is accessible from two places: long press on a `ListTile` and a trash
icon in the `EntryDetailScreen` app bar. Both show the same `AlertDialog`.
The dialog is extracted into a `_confirmDelete()` method to avoid duplication.
`Navigator.pop(true)` signals to the caller that a delete occurred — the list
screen awaits the push and calls `_loadEntries()` if it receives `true`.

### Long press on desktop
On Linux desktop, a long press is triggered by holding the left mouse button.
Right mouse button does not trigger `onLongPress` in Flutter.

### Extending a screen for create/edit — optional `existing` parameter
Rather than duplicating a form screen, add an optional `existing` parameter
of the relevant type. `_isEditing` is a simple getter: `widget.existing != null`.
In `initState`, use a pattern match on `existing` to pre-populate controllers.
In `_save`, branch on `_isEditing` to call `createEntry` or `updateEntry`.
`updateEntry` must preserve the original id, createdAt, folder, tags, and
favourite — only the user-edited fields change. `updatedAt` is passed as an
empty string and stamped by Rust on the session side.

- **Completed:** Onboarding flow. `main.dart` checks for vault existence at
  the default path (`getApplicationSupportDirectory()/gabbro.gabbro`) and
  routes to `OnboardingScreen` or `UnlockScreen` accordingly. `OnboardingScreen`
  shows a path field (with file picker), master passphrase field with real-time
  entropy indicator, and confirm passphrase field. `init_vault` added to Rust
  bridge — creates empty vault and unlocks into session immediately.
  `UnlockScreen` now takes `vaultPath` as a parameter instead of hardcoding
  `/tmp/`. End-to-end confirmed on Linux desktop. 119 Rust tests still passing.
- **Next task:** Fix app ID from `com.example.gabbro` to `app.gabbro.gabbro`
  in `linux/CMakeLists.txt` and `pubspec.yaml`. Then add bulk delete mode to
  bikeshed and consider Android build.

### Dependency injection for testable Flutter widgets
Flutter widget tests run on the host machine with no Rust binary available.
A widget that calls a bridge function directly (e.g. `listEntrySummaries()`)
cannot be tested in isolation — the call crashes with no native library loaded.

The fix is dependency injection: give the widget an optional function parameter
with the real bridge call as its default value:

```dart
class VaultListScreen extends StatefulWidget {
  final List<EntrySummaryData> Function() listEntries;
  const VaultListScreen({
    super.key,
    this.listEntries = listEntrySummaries,
  });
}
```

Production code passes nothing — the default applies. Tests pass a function
that returns fake data. The widget is identical in both cases; only the
data source changes. Python analogy: a function that takes an `http_client`
parameter defaulting to `requests` — tests substitute a mock, production
uses the real thing.

### `find.descendant` — scoping widget finders in tests
`find.text('X')` matches every widget in the tree that displays the text X.
When a search field contains typed text X and a list tile also displays X,
`findsOneWidget` fails because two matches are found.

`find.descendant(of: find.byType(ListTile), matching: find.text('X'))` scopes
the search to only widgets that are descendants of a `ListTile`. Use this
pattern any time a text value could appear in both an input field and
elsewhere in the widget tree.

### The testing pyramid
Unit tests form the broad base — many, fast, isolated. Widget tests sit in
the middle — fewer, test UI behaviour only. Integration tests are the thin
top — few, slow, exercise the full stack including the bridge. Write them
bottom-up: unit tests first, then widget tests once unit tests are solid,
then integration tests once the lower layers are clean.

        /\
       /  \  integration tests — few, slow, full stack
      /----\
     /      \  widget tests — medium, UI behaviour
    /--------\
   /          \  unit tests — many, fast, isolated
  /____________\

### Dependency injection for testable screens — the full pattern
All Gabbro screens follow the same DI pattern. Bridge functions that would
crash in a test environment are extracted as optional parameters with the
real bridge call as the default value. Top-level private functions
(e.g. `_defaultDelete`, `_defaultEstimateEntropy`) hold the defaults —
Dart requires default parameter values to be top-level references, not
instance methods. Production code passes nothing; tests pass fakes.
This applies to all bridge calls including `estimateEntropy`, which fires
on every `onChanged` keystroke and must be injected even when entropy
display is not under test.

## Android Deployment

### `adb` — Android Debug Bridge
The command-line tool for communicating with Android devices and emulators.
`adb install <path>.apk` pushes an APK to a connected device or running
emulator. The emulator registers automatically as an `adb` target when
launched — no extra configuration needed. Lives in
`~/Android/Sdk/platform-tools/adb` on a standard Android Studio install.

### Android emulator on Arch Linux — prerequisites
Two system dependencies are required beyond Android Studio itself:
- `libbsd` — required by the emulator's QEMU binary; install with
  `sudo pacman -S libbsd`. Symptom of missing: emulator exits immediately
  with `error while loading shared libraries: libbsd.so.0`.
- KVM membership — the x86_64 emulator requires hardware virtualisation;
  your user must be in the `kvm` group. On Arch, `/dev/kvm` is
  world-readable by default so this is rarely the blocker, but verify
  with `groups | grep kvm`.

### AOSP emulator image for FOSS testing
When creating an AVD, prefer the **Android Open Source Project** system
image over Google APIs or Google Play variants. Reasons: aligns with
Gabbro's FOSS principles and de-Googled Android compatibility goal
(GrapheneOS/CalyxOS), and avoids any Google Play Services dependency
creeping into the testing baseline. If Gabbro works on AOSP, it will
work on de-Googled devices.

### Debug vs release APK performance on emulator
The ~20s Argon2id latency observed in debug builds on the Linux desktop
is reproduced (and slightly worse) on the Android emulator, which adds
emulation overhead on top of the unoptimised Rust `dev` profile. This
is expected and not a bug. Always use `flutter build apk --release` for
any user-facing test where performance matters.

### Two APK output locations
`flutter build apk --debug` writes the APK to two locations:
`build/app/outputs/flutter-apk/app-debug.apk` (Flutter's own output
path) and `build/app/outputs/apk/debug/app-debug.apk` (Gradle's standard
output path). Both files are identical — `diff` confirms this. Use either
for `adb install`; the Flutter path is the more memorable one.

---

## Distribution & Licensing

### GPL-3.0 and commercial distribution
GPL-3.0-only explicitly permits charging money for distribution. The
copyleft constraint is on the *source* — anyone you distribute to gets
the code and the right to redistribute it. They could theoretically build
it themselves, but in practice almost nobody does. This means:
- Free on Arch/Debian and F-Droid: standard FOSS distribution
- Paid on the Play Store: fully GPL-3.0 compatible — charge to recoup
  Google's $25 registration fee (or more)
- F-Droid's anti-features policy covers things like telemetry and
  proprietary network services; a paid Play Store version of the same
  app is not an F-Droid concern

### Android vault file location during development
Flutter's `getApplicationSupportDirectory()` resolves to
`/data/data/<app-id>/files/` on Android. For Gabbro with app ID
`app.gabbro.gabbro`, the vault lives at:
`/data/data/app.gabbro.gabbro/files/gabbro.gabbro`

Direct filesystem access requires root. During testing, use `adb`:
```bash
# Delete just the vault file
adb shell rm /data/data/app.gabbro.gabbro/files/gabbro.gabbro

# Wipe all app data (vault + SharedPreferences + any other state)
# Preferred for onboarding testing
adb shell pm clear app.gabbro.gabbro
```

### Gabbro vault magic bytes — reading the hexdump
`hexdump -C ~/.local/share/app.gabbro.gabbro/gabbro.gabbro` on a real
vault file shows:

```
00000000  47 41 42 42 52 4f 01 00  01 00 ...
```

`47 41 42 42 52 4f` is ASCII for `GABBRO` — the magic bytes hardcoded
in `file_format.rs` to identify valid vault files. `01 00` is the version
field (v1, big-endian u16). The Argon2id parameters follow immediately.
Confirming these bytes in a real vault file validates that serialization
is working correctly end-to-end.

### `SafeArea` — avoiding system UI intrusions on mobile
On Android (and iOS), system UI elements — the navigation bar, notches,
status bar — can overlap app content if not accounted for. The idiomatic
Flutter solution is to wrap scrollable screen bodies in `SafeArea`:

```dart
body: SafeArea(
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    ...
  ),
),
```

`SafeArea` automatically insets its child to avoid all system UI
intrusions at runtime — it adapts to any device, launcher, or form
factor without hardcoded pixel values. Apply it to any screen with
scrollable content. `MediaQuery.of(context).padding.bottom` is the
manual alternative but `SafeArea` is cleaner and handles all four
sides.

### `mainAxisSize: MainAxisSize.min` — enabling scroll in forms
A `Column` inside a `SingleChildScrollView` only triggers scrolling if
its natural height exceeds the viewport. Without `mainAxisSize: MainAxisSize.min`,
a `Column` expands to fill available space — it never overflows and
scroll never activates. Adding `mainAxisSize: MainAxisSize.min` tells
the column to size itself to its children, enabling scroll when the
content is taller than the screen.
### `ListView.builder` is lazy — `GlobalKey` fails for off-screen items
`ListView.builder` only builds widgets that are currently visible (or near
the viewport). A `GlobalKey` attached to a section header that has never
scrolled into view will have `currentContext == null` — the widget simply
does not exist in the render tree yet.

Consequence: using `GlobalKey` to look up the position of an arbitrary
section header and scroll to it fails silently for any header that is
off-screen. `_sectionKeys[letter]` returns null for letters whose sections
are below the current scroll position and have never been rendered.

The correct solution for "scroll to index N in a lazy list" is
`scrollable_positioned_list`, a BSD-3-licensed package that wraps
`ListView.builder` and provides `ItemScrollController.scrollTo(index:)`.
This sidesteps the lazy-render problem entirely because the scroll is
driven by index, not by pixel position derived from a rendered widget.

### `Row` vs `Stack` for side-by-side list + index bar
A `Stack` overlays children — the index bar sits on top of the list and
competes for tap events at the same screen coordinates. This makes it
impossible to reliably distinguish a tap on the index bar from a tap on
a list item, especially on desktop where click targets are small.

A `Row` places children side by side — the list takes `Expanded` (all
remaining width) and the index bar takes a fixed `SizedBox` width. No
overlap, no ambiguity, no competing tap targets.

### FAB clearance — padding not layout tricks
The `FloatingActionButton` floats above the body at the bottom-right by
default. Content behind it is obscured. The correct fix is to add
`padding: EdgeInsets.only(bottom: 80)` to the widget that would otherwise
extend behind the FAB. No layout restructuring needed — the FAB's default
position is ~56px tall with ~16px margin, so 80px bottom padding is
sufficient clearance.

### `LayoutBuilder` for responsive letter bar
`LayoutBuilder` gives a widget access to its own constraints at build time.
Used in `AlphabetIndexBar` to compute how many letters fit at the minimum
readable height, then window the full 27-letter list to that count centred
on the active letter. This avoids overflow on small screens without
shrinking font size below readable limits.

### `HitTestBehavior.opaque` on `GestureDetector`
By default a `GestureDetector` only receives hit tests where its child has
painted pixels. `HitTestBehavior.opaque` makes the entire bounding box
receive hits regardless of whether the child painted there. Required for
the index bar so that taps in the gaps between letters are still captured
by the bar rather than falling through to the list behind it.

### `ScrollConfiguration` — suppressing the platform scrollbar
`ScrollConfiguration.of(context).copyWith(scrollbars: false)` removes the
platform scrollbar from any scroll view wrapped in a `ScrollConfiguration`
widget with that behaviour. Used in `VaultListScreen` to suppress the
default scrollbar on `ScrollablePositionedList` — the alphabet index bar
is the navigation mechanism and a separate scrollbar is redundant.

### `Clipboard` — writing to the system clipboard in Flutter
`Clipboard.setData(ClipboardData(text: value))` writes a string to the
system clipboard. Lives in `package:flutter/services.dart`. The call is
async — `await` it before showing any confirmation UI. Always check
`mounted` after the await before calling `ScaffoldMessenger`, because the
widget may have been disposed while the clipboard write was in progress.
The `SnackBar` is the standard Flutter confirmation pattern: brief
(2 seconds), non-blocking, dismissible.

For sensitive fields that have a show/hide toggle (passwords, CVV, PIN),
copy always uses the real underlying value — never the bullet placeholder.
The user's intent when tapping copy is unambiguous.

### `file_picker` v11 — static API, no `.platform`
`file_picker` v11 introduced a breaking change: the instance-based
`FilePicker.platform.pickFiles()` pattern was replaced with direct
static calls. The correct v11 API is:
- `FilePicker.pickFiles(...)` — open a file picker dialog
- `FilePicker.saveFile(...)` — open a save dialog (desktop only)
- `FilePicker.getDirectoryPath()` — open a directory picker

`PathField` (`lib/widgets/path_field.dart`) wraps these into a
reusable widget with two modes (`PathFieldMode.open` / `.save`),
a read-only `TextFormField` displaying the selected path, and a
folder icon button that opens the native dialog. Used by
`ImportScreen` (open mode) and `ExportScreen` (save mode).
The widget's `onPathSelected` callback is the DI hook for tests —
production code uses the real picker; tests inject a pre-set path
via `initialPath`.

### `Wrap` vs `Row` for accessible button groups
`Row` with `Expanded` children is a common pattern for segmented button groups, but it breaks at large text sizes — labels wrap mid-word inside fixed-width buttons. `Wrap` is the accessible alternative: it lays out children horizontally and reflows to a new line when space runs out, so each button stays legible at any text scale. No `Expanded` needed — children take their natural size. The tradeoff is that buttons are no longer equal-width, but for a settings control this is acceptable and preferable to illegible labels.

### `ScrollController` for dynamic scroll affordances
A `ScrollController` attached to a `SingleChildScrollView` exposes `position.pixels` (current scroll offset), `position.maxScrollExtent` (total scrollable distance), and `position.viewportDimension` (visible width). Adding a listener via `addListener` lets a parent widget react to scroll changes — e.g. showing/hiding chevron affordances. Key patterns:
- Add listener in `initState`, remove in `dispose`.
- Use `WidgetsBinding.instance.addPostFrameCallback` to read scroll extents after the first frame — they are not available during `build`.
- Use a meaningful threshold (e.g. `> 80.0`) to avoid showing affordances when content is only marginally wider than the viewport (padding rounding artifacts).
- `animateTo()` with a `curve` and `duration` gives smooth programmatic scrolling on tap.

### `retain` — in-place filtering of a `Vec` in Rust
`vec.retain(|item| condition)` removes all elements for which the condition
returns false, in a single pass, without allocating a new `Vec`. Used in
`session_delete_entries_no_save` to remove multiple entries by UUID in one
operation: `session.entries.retain(|e| !ids.contains(&entry_id(e).to_string()))`.
The mirror image of `.filter()` on an iterator — `retain` mutates in place
while `filter` produces a new collection.

### BOM — Byte Order Mark
A BOM is a Unicode character (`\u{FEFF}`) that some tools prepend to
UTF-8 files to signal the encoding. Microsoft Excel on Windows prepends
a BOM to every CSV it exports. It is invisible in most text editors but
causes the first column header to read as `"\u{FEFF}name"` instead of
`"name"`, silently breaking any field mapping that references it by name.

The fix is to strip the BOM as the first operation on any untrusted
text input: `input.strip_prefix('\u{FEFF}').unwrap_or(input)`. This
is a no-op if no BOM is present, and costs nothing. Applied in both
`sniff_csv()` and `import_csv()` in `rust/src/import/csv.rs`.

### Trait imports required for method dispatch
In Rust, a method defined by a trait is only callable if that trait is
in scope — even if you never write the trait name directly in your code.
Example: `EncodedSizeUser` provides `as_bytes()` on `EncapsulationKey`
from the `ml-kem` crate. Removing the `use ml_kem::EncodedSizeUser`
import silences a spurious "unused import" warning but immediately
breaks every call site that uses `.as_bytes()` on that type.

The correct fix when a trait import appears unused but removing it
breaks compilation: add `#[allow(unused_imports)]` with an explanatory
comment rather than removing the import. This documents the intent
explicitly for the next reader.

```rust
// EncodedSizeUser provides `as_bytes()` on EncapsulationKey — must stay in scope
#[allow(unused_imports)]
use ml_kem::{MlKem1024, MlKem1024Params, KemCore, EncodedSizeUser};
```

Python has no equivalent — method availability is checked at runtime,
not compile time, so a missing import only fails when the method is
actually called.

### Android 16 edge-to-edge enforcement
Android 16 makes edge-to-edge rendering mandatory — apps draw behind the
status bar and bottom navigation bar with no opt-out. The `windowOptOutEdgeToEdgeEnforcement`
flag and `SystemChrome` mode overrides are both ignored. The correct Flutter
fix is to preserve system insets in `MediaQuery`: use `MediaQuery.of(context).copyWith(...)`
rather than `MediaQueryData(...)` when overriding only one field (e.g. `textScaler`).
`MediaQueryData()` constructs a fresh object with all inset fields zeroed,
silently discarding the status bar and navigation bar padding that `Scaffold`
needs to position `AppBar` and `FloatingActionButton` correctly.

### `FilePicker.saveFile()` not supported on Android
`FilePicker.saveFile()` silently returns `null` on Android — it is a
desktop-only API. On Android, vault path should be fixed to
`getApplicationSupportDirectory()` and shown as read-only text. Use
`Platform.isAndroid` to branch between the two behaviours.

### Closure capture in Flutter list builders
In a `ListView` or `ScrollablePositionedList` builder, any value computed
outside the `builder` callback is captured once at build time, not per tap.
The fix: move the computation inside the callback. Classic example: calling
`getEntry(id: entry.id)` outside `MaterialPageRoute builder` captures the
last computed value for all tiles — move it inside so it runs on tap.

### Bulk operations — no-save + single save pattern
When multiple entries need to be added or removed, calling a save function
per entry is expensive: each save runs Argon2id + encryption + disk write
(~667ms in release). The correct pattern is to mutate the in-memory session
N times without saving, then call save once at the end. In Gabbro this is
implemented as paired functions: `session_add_entry_no_save` /
`session_delete_entries_no_save` for the mutations, and `session_save` for
the single persist. Both import and bulk delete use this pattern.

---

## Dart — `listEquals` for value equality on lists

Dart's `==` operator on `List` is reference equality, not value equality.
Two separately constructed lists with identical contents are not `==`:

```dart
[1, 2, 3] == [1, 2, 3] // false — different objects
```

To compare list contents, use `listEquals` from `package:flutter/foundation.dart`.
This is important anywhere a list is rebuilt from form state and compared to
the original — for example, detecting whether custom fields changed during
an edit. Without `listEquals`, the diff always returns "changed" even when
the user changed nothing.

Python analogy: Python's `==` on lists IS value equality (`[1,2,3] == [1,2,3]`
is `True`). Dart's behaviour is the exception, not the rule.

---

## Dart — re-fetching entry after bridge save

After calling `updateEntry` (or any bridge save), the Flutter-side DTO is
stale — it does not reflect fields stamped by Rust (`updated_at`, populated
`previous_password`). Always call `getEntry(id: id)` immediately after a
save to get the fresh DTO before navigating or updating state. Displaying
the pre-save DTO causes "Saved Unknown" timestamps and missing history.

---

## Rust — `frb_generated.rs` manual patching pattern

When a Rust function signature changes (new parameter, new struct field),
`frb_generated.rs` becomes out of sync and the test suite fails to compile.
The correct sequence:
1. Patch `frb_generated.rs` manually with a placeholder (e.g. `None` for a
   new `Option<u32>` parameter) to unblock `cargo test`.
2. Run the affected tests to confirm they pass.
3. Run `flutter_rust_bridge_codegen generate` from `gabbro/` to regenerate
   all bridge files correctly.
4. Run `cargo test` and `flutter test` again to confirm nothing broke.

Never leave a manual patch in place — codegen is the source of truth.

---

## Rust — date arithmetic without chrono

Adding days to an ISO 8601 timestamp without the `chrono` crate requires
converting to a day count (days since epoch), adding, then converting back.
Key points: the conversion must handle leap years correctly; use `u64` not
`u32` for year values to avoid type mismatches with existing helpers; and
keep time-of-day suffix intact by parsing only the date portion (`[0..10]`)
and appending the original suffix unchanged.

The `is_leap` helper must only be defined once per module — Rust does not
allow duplicate function names even with different signatures. Check for
existing helpers before adding new ones.

---

## Rust — `vault_entry_to_data` masking boundary

`vault_entry_to_data` in `vault_bridge.rs` masks sensitive history fields
at the bridge boundary using `MASKED_VALUE` (`"********"`). This is correct
for fields that are never displayed directly — but `PreviousSecretData.value`
is rendered directly in `PasswordHistoryScreen` via `prev.value`, unlike the
live `password` field which is held in full in the DTO and masked only in the
UI via `_toggleField`. The fix: pass `p.value.clone()` for
`previous_password.value` so the history screen can show/hide the real value.

Rule of thumb: mask at the bridge boundary only when the Flutter layer will
never need the plaintext. If the UI has a show/hide toggle that needs the real
value, it must arrive from Rust in plaintext — the UI layer is responsible for
the obscured display.

---

## Flutter/Dart — `getEntry` is synchronous

`getEntry` in the flutter_rust_bridge API is a synchronous function (no
`async` on the Rust side). Adding `await` to a synchronous bridge call is a
compile error: "Uses 'await' on an instance of 'VaultEntryData', which is not
a subtype of 'Future'." Always check the Rust function signature before adding
`await` on the Dart side — `async fn` in Rust becomes `Future` in Dart;
non-async `fn` becomes a direct return value.

---

## Flutter — `flutter_rust_bridge_codegen generate` frozen — fix with `build_runner clean`

If `flutter_rust_bridge_codegen generate` hangs indefinitely (30+ minutes,
no output), the cause is usually a stale `build_runner` cache that conflicts
with the codegen step. The fix:

1. Kill the hanging process.
2. Run `dart run build_runner clean` from `gabbro/` — this wipes the
   `.dart_tool/build` cache that `build_runner` maintains.
3. Re-run `flutter_rust_bridge_codegen generate` from `gabbro/` — it should
   complete in under a minute.
4. Run `flutter test` and `cargo test -q` to confirm nothing broke.

`dart run build_runner clean` is safe to run at any time — it only removes
generated/cached artefacts, never source files. Worth trying as a first
response to any inexplicable codegen hang before reaching for more invasive
fixes like reinstalling the codegen tool.

---

## Rust — Expiry purge on unlock (`is_expired` + `purge_expired_history`)

Password history expiry is enforced at unlock time, not at write time.
The pattern: `purge_expired_history` iterates all entries, calls
`is_expired` on each `PreviousSecret.expires_at`, and nulls out any
expired history before the session is stored in memory.

`is_expired` parses the ISO 8601 UTC string (`YYYY-MM-DDTHH:MM:SSZ`)
into epoch days using the existing `days_from_ymd` helper and compares
to today. `None` means keep-forever — never expired. An unparseable
string is treated conservatively as not expired (no silent data loss).

Both functions are `pub(crate)` in `api/vault.rs`, co-located with the
timestamp helpers they depend on. `purge_expired_history` is called as
the first step inside `unlock_vault` in `vault/session.rs`, so Flutter
never sees stale expired history regardless of when the vault was last
opened.

TDD: three serial tests in `vault::session::tests` —
`expired_history_is_purged_on_unlock` (backdated `expires_at: 2000-01-02`),
`unexpired_history_is_preserved_on_unlock` (future `expires_at: 2099-12-31`),
`keep_forever_history_is_preserved_on_unlock` (`expires_at: None`).

---

## Dependency licence audit — procedure

Before each v1 release candidate, cross-check `_kComponents` in
`lib/screens/about_screen.dart` against `rust/Cargo.toml` and
`pubspec.yaml` manually:

1. Every direct runtime dependency in both files must have a
   corresponding `_Component` entry.
2. Dev-dependencies (`serial_test`, `tokio`, `flutter_lints`,
   `freezed`, `build_runner`, `integration_test`) are excluded —
   they ship no code to the user.
3. Licence strings must match each project's own `LICENSE` file.
   Dual-licence projects (Apache-2.0 / MIT is the RustCrypto standard)
   should be listed as such, not just one half.
4. The three language/runtime entries (Rust, Dart, Flutter) are stable
   and do not need re-checking unless a major version changes the licence.

First audit (May 2026): found `once_cell` and `base64` missing — both
added as `Apache-2.0 / MIT`.

---

## Android — SAF directory picker for file export

`FilePicker.saveFile()` is desktop-only. On Android it silently returns
`null`, making export appear to succeed while writing nothing accessible
to the user.

The correct approach for Android is `FilePicker.getDirectoryPath()`,
which invokes the Storage Access Framework (SAF) system picker. The user
selects a destination directory; the app then constructs the full output
path by appending the filename:

```dart
final dir = await FilePicker.getDirectoryPath();
// dir is e.g. '/storage/emulated/0/Documents'
final exportPath = '$dir/vault.gabbro';
```

Key design points:

- The Export button must remain **disabled** (`onPressed: null`) until a
  directory has been chosen — there is no pre-populated default on Android.
- `PathField` is not used on Android for export — the Android branch calls
  `getDirectoryPath()` directly and shows an `OutlinedButton.icon` instead.
- The Rust `export_vault(path)` bridge receives the full file path
  (directory + filename) unchanged — no Rust changes needed.
- Use a distinct icon (`Icons.folder`) for the "Choose folder" button so
  widget tests can distinguish it from `PathField`'s `Icons.folder_open`.

Python analogy: like `tkinter.filedialog.askdirectory()` vs
`asksaveasfilename()` — one returns a folder, the other a full path.
You then join the folder with your chosen filename yourself.

---

## Flutter — stale widget state after vault mutation

When a vault-mutating operation (import, delete, passphrase change) completes,
any widget state that holds a reference to a vault entry ID must be explicitly
cleared. If it is not, the next layout pass will call `getEntry()` with a stale
ID that no longer exists in the Rust session. Rust correctly returns an `Err`;
the flutter_rust_bridge codec throws a Dart exception; Flutter logs a full stack
trace to console but the UI falls back silently to the empty-state placeholder.
No visible crash — but the log noise is a real bug.

The pattern appears in `TabletVaultLayout`: `_selectedEntryId` is set when
the user taps a list entry, but is not reset when `onRefresh()` is called after
an import. Fix: wherever a vault-mutating operation triggers a list reload,
also reset `_selectedEntryId = null` so the detail pane returns to the
empty state cleanly.

General rule: **any widget that caches a vault entry ID must subscribe to the
same lifecycle events that mutate the vault**, and reset its cached ID on those
events. This is the tablet-layout equivalent of the list-pane-not-refreshing
bug fixed in the previous session — the same root cause, different symptom.

Python analogy: like holding a reference to a list index after the list has
been sorted or filtered in place — the index is stale the moment the underlying
data changes.
