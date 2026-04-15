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
- `cargo` commands (test, build, etc.) → run from `gabbro/rust/` where
  `Cargo.toml` lives
- `flutter_rust_bridge_codegen generate` → run from the project root

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

---

## Flutter & Dart Concepts

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

This is not a bug — it is the expected behaviour of an unoptimised build.
For development, the slow unlock is an inconvenience we accept in exchange
for faster compile times and better error messages. For users, the release
build is always used. Never tune Argon2id parameters based on debug build
timings — always use `cargo run --bin bench_kdf --release`.