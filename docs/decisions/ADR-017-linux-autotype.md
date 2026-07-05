# ADR-017: Linux Desktop Auto-Type (Global-Hotkey Autofill, X11-only)

## Status
Accepted — Phases 1–3 implemented 2026-07-05 (Phase 4 deferred; see the Bikeshed).
**Amended 2026-07-05** (see Amendment below): the trigger-time picker was reverted for
per-entry direct-type.

## Date
2026-07-05

## Amendment (2026-07-05): picker -> per-entry direct-type

This supersedes every reference to the **picker** in this ADR (notably §6 and §8).

The trigger-time picker was implemented then removed after hardware testing: showing
Gabbro's own window to choose an entry steals X focus, and handing focus back to the
browser to type proved unreliable on qtile (especially across virtual desktops) — the
fill frequently failed or landed in the wrong place.

Replacement — **per-entry direct-type**: the user opens a Login in Gabbro (it becomes the
auto-type target); the hotkey then types that entry into the **already-focused** window,
so no window is shown and no focus is stolen. If the login's `username` is empty its
`email` is typed instead. A trigger with no Login open, or a locked/closed Gabbro, does
nothing — cold-start (unlock-then-type) is Phase 4, deferred.

The username-only / password-only sequences (two-step forms) were removed with the
picker; re-add if a concrete need returns. Everything else here stands: X11-only, no
extension, `XTEST` injection, secret-stays-in-Rust, capture-window + wrong-window abort,
opt-in, auto-lock unchanged.

## Context

Gabbro has OS-level autofill on Android (the platform Autofill framework:
`GabbroAutofillService`). The Linux desktop has had nothing comparable — only
copy-to-clipboard (with deterministic auto-clear). The goal is a desktop autofill
experience *similar in spirit* to Android's, under one hard rule from the
maintainer:

> **No browser extension — ever.** Rely entirely on OS-level capabilities. If that
> means fewer autofill capabilities than Android, so be it.

Linux desktop reality forces the shape of the design: two display servers, **X11**
and **Wayland**, behave completely differently for the three primitives autofill
needs — a global hotkey, knowing which window/app is focused, and injecting
keystrokes into another app. X11 exposes all three; Wayland deliberately denies
them to ordinary clients. (Prior art: KeePassXC's auto-type is full on X11 and only
*partial* on Wayland, for exactly these reasons — and KeePassXC needs a browser
extension precisely because the window manager cannot see a browser's URL.)

This ADR records the scope and rationale agreed in a design discussion. It fixes
*what and why*; the *how* (phasing, test seams) is tracked in `ARCHITECTURE.md`.

## Decision

### 1. No browser extension — ever
- **Different targets, unbounded maintenance:** an extension is a separate product
  per browser family (Chromium, Firefox, …), each with its own store, review, and
  update cadence — a large, permanent maintenance surface.
- **Supply-chain / trust risk:** a browser extension is a recurring compromise and
  impersonation target; a bad one can exfiltrate every credential. It is the exact
  opposite of Gabbro's self-contained, minimal-trust posture.
- **Consequence (accepted):** no page-level field detection, so desktop autofill is
  coarser than Android's. That trade is deliberate.

### 2. Clipboard stays; auto-clear is *more* trustworthy on Linux than Android
- Auto-type synthesizes keystrokes and **never touches the clipboard**, so it is the
  preferred path for a secret. Copy-paste remains for everything auto-type cannot
  cover (cards, Wayland sessions, awkward forms).
- On **Linux/X11** the clipboard is a normal selection Gabbro owns and can clear
  deterministically. On **Android** the clipboard is a shared system service with
  cross-app access, system clipboard history, and (13+) a paste preview, so a clear
  is best-effort there. So desktop copy-paste is already a solid fallback, and
  auto-type — bypassing the clipboard entirely — is better still.

### 3. X11 only; Wayland deferred (not rejected)
- X11 gives us the grab (`XGrabKey`), the active-window identity
  (`_NET_ACTIVE_WINDOW` + window properties), and synthetic input (`XTEST`).
- Wayland denies all three to ordinary clients by design: no cross-client
  active-window inspection; synthetic input only via the RemoteDesktop portal
  (`libei`) behind a per-session grant; global shortcuts only via a portal with
  uneven compositor support.
- **YAGNI:** the maintainer runs X11 (qtile + picom); near-term testers are X11.
  Wayland users keep copy-paste. Revisit only on real user demand.
- **Detection:** if the session is Wayland (`XDG_SESSION_TYPE=wayland` /
  `WAYLAND_DISPLAY` with no usable X), the feature is hidden/disabled with a short
  explanation; copy-paste is unaffected. (Browsers under XWayland *may* still be
  drivable, but the design does not rely on it.)

### 4. Save / update new logins is out of scope
- Android's framework delivers a "a dataset was submitted, here are the fields"
  callback. Linux OS-level has **no equivalent**. Without an extension or fragile
  AT-SPI accessibility scraping (both rejected), Gabbro has no signal that a login
  was entered or changed in another app — so no save/update prompts on desktop.
- The only credentials Gabbro can still offer to save are ones **it generated
  itself** (the existing generator flow) — unchanged by this ADR.

### 5. User-bound trigger (no Gabbro key grab), no default hotkey, no system tray
- **The user owns the key, not Gabbro.** Gabbro does **not** grab a global hotkey.
  Instead it exposes a trigger command — `gabbro-autotype` — that pokes the
  already-running instance over a small local socket, which then performs the fill on
  the currently-focused window. The user binds their own chosen key to that command
  in whatever they already use for shortcuts.
- **Why not a Gabbro-owned grab?** On X11 a key grab is effectively exclusive: on a
  tiling WM (qtile) all bindings are registered at WM startup, so a Gabbro grab would
  either fail (WM got there first) or silently steal a combo from the user's config.
  Letting the WM own the key avoids the conflict entirely and is idiomatic for the
  Linux/tinkerer audience — combos are personal, and they already manage every other
  binding in one place.
- **No default hotkey shipped.** Nothing to collide with; trivial to change (it lives
  in the user's own config). The effect is identical to a global hotkey — only the
  key's *owner* differs.
- **Documentation, not a per-WM matrix.** The command is universal. We document it
  plus two examples: a tiling-WM line (qtile `config.py`:
  `Key([mod], "slash", lazy.spawn("gabbro-autotype"))`) and a desktop-environment
  note (GNOME/KDE/XFCE: add a custom keyboard shortcut running `gabbro-autotype`).
  Every environment can bind a command to a key; users map it onto their own setup.
- **No tray:** the trigger works whenever the Gabbro *process* is alive, regardless of
  window focus. A tray only buys "survive window close" — which KISS does not need:
  the user keeps Gabbro's window open (any qtile group) beside the browser. A tray
  adds a dependency (StatusNotifier/appindicator) and interplay to verify, for no
  essential gain. Deferred as possible later polish.
- **Built-in self-grab deferred** — a fallback only a non-config-editing user could
  want, and even they have their DE's custom-shortcut GUI, so likely never (YAGNI).

### 6. Browser-focused; no window->entry matching; login typing sequences
- Desktop targets are overwhelmingly **browsers** (the maintainer confirmed
  native-app sign-in is a non-need).
- **No matching:** browsers do not expose their URL to the window manager — the
  title bar shows a page title at best — so reliable entry-to-site matching is
  impossible without the banned extension. Instead the hotkey opens **Gabbro's own
  picker** listing **all** Login entries with type-to-filter (mirroring the existing
  vault search). Listing *all* entries is deliberate: never hide the entry the user
  wants behind a wrong guess.
- **Typing sequences** for the selected entry:
  - **Default (primary action):** `{username}{TAB}{password}{ENTER}` — the
    near-universal single-page login form.
  - **Username-only** and **password-only** secondary actions — to drive **two-step
    forms** (identifier page, then password page, e.g. Google/Microsoft) where one
    sequence cannot work.
- **No field-label ambiguity to resolve:** a Login has exactly one `username` and
  one `password` value; Gabbro types those regardless of what the site labels the
  fields (username/login/email, password/passphrase). The vault-unlock *passphrase*
  is unrelated app-access terminology, not a login field.
- The trailing `{ENTER}` (auto-submit) is on by default; making it optional is a
  possible later refinement.

### 7. Logins only; cards deferred
- **Logins:** username + password map cleanly onto the Tab-separated sequence.
- **Cards deferred:** payment forms split expiry (MM/YY or dropdowns), reorder
  fields unpredictably, and run auto-advance JavaScript that fights synthesized
  keystrokes — a blind fixed sequence rarely aligns, so it would be unreliable and
  frustrating. Cards keep their existing **per-field copy-paste**. A future
  "type one field at a time" model can revisit.
- **No TOTP** typing — Gabbro has no TOTP by design (YubiKey covers 2FA).

### 8. Security model and the "keys live in Rust" boundary
- **Secret never crosses the bridge for typing.** The picker deals only in entry
  *titles*. On selection, Flutter tells Rust "type entry `<id>` into window `<id>`
  with sequence `<S>`"; Rust reads the secret from its in-memory decrypted session
  and injects via `XTEST`. The password never reaches Dart for auto-type — a
  *stronger* posture than the display path (which does surface secrets to Dart).
- **Auto-lock preserved, unchanged.** 30 s default; keys zeroized on lock. A hotkey
  on a **locked** vault pops the normal unlock prompt first, then performs the queued
  type. We never extend the unlock lifetime or hold keys longer to smooth auto-type.
- **Wrong-window leak mitigation.** Capture the target window id at hotkey-press; if
  the picker/unlock dialog takes focus, restore focus to *that exact* window before
  typing; if the target window changed or vanished, **abort** rather than type the
  secret into the wrong place.
- **X11 has no input isolation.** Any local X client can already read keystrokes and
  inject via `XTEST`, so Gabbro's use of `XTEST` is consistent with — and no worse
  than — the platform's existing model. But it means X11 auto-type is only as safe as
  the X11 session (a pre-existing local keylogger sees the password, exactly as if
  typed by hand). Documented honestly; not a regression Gabbro introduces.
- **Opt-in.** The feature is disabled by default and enabled explicitly in settings,
  given it is a new synthetic-input surface.

### 9. Keyboard layout / Unicode injection (the main implementation risk)
- Synthesized keystrokes must reproduce the exact characters of arbitrary passwords —
  symbols and **non-Latin scripts included** (Gabbro's generator can produce Greek /
  Cyrillic, CJK). `XTEST` sends keycodes, so each character must be mapped to a keysym,
  temporarily binding an unused keycode when the active layout lacks the character
  (the `xdotool` / KeePassXC technique), and restored afterward. This is the part to
  prove on hardware first.

### 10. Implementation split and dependency
- **Rust** owns the X11 surface via `x11rb` (a Cargo crate, not a system package;
  its default backend speaks the X11 wire protocol directly over the socket, so **no
  system X library is linked** — nicer for the self-contained bundle than the
  Xlib/xcb bindings). Rust does the active-window read and the `XTEST` injection.
  **Linux-only**, gated behind `cfg(target_os = "linux")` and excluded on Android —
  mirroring the existing `libfido2` gating. Note: **no `XGrabKey`** — the key is owned
  by the user's WM/DE (see §5), so there is no grab, no `BadAccess` handling, and no
  in-app hotkey picker to build.
- **Trigger IPC:** the running instance listens on a local unix socket (under
  `$XDG_RUNTIME_DIR`); `gabbro-autotype` is a thin client that connects, sends
  "trigger", and exits. Single-instance pattern; the socket is the trigger surface.
- **Flutter** owns the config UI (enable/disable, sequence defaults) and the picker
  window.
- `picom` (compositor) is irrelevant to `XTEST`; **no portal is used**, so bare
  window managers (qtile) that run no portal are fine.

### 11. Testing
- **Host-testable (deterministic):** sequence building (full / username-only /
  password-only), settings, the trigger-IPC message handling, character-to-keysym
  planning, and Wayland-vs-X11 session detection.
- **Hardware-only:** the live trigger -> read-active-window -> inject path and the
  focus dance — verified on the maintainer's X11/qtile box. Unit-green is explicitly
  **not** "done"; the hardware pass is the gate.

## Consequences

- **Positive:** a genuinely useful, extension-free desktop autofill for the common
  case (browser logins) that keeps secrets in Rust and off the clipboard, and
  degrades cleanly to copy-paste where it cannot apply.
- **Limits accepted:** no browser site-matching (manual pick from an all-logins
  picker), no Wayland for now, no save/update, no cards, no TOTP.
- **New surface:** synthetic input into arbitrary windows — mitigated by
  target-window capture/verify and the honest X11 threat note; opt-in.
- **User binds their own key** (no shipped default, no Gabbro grab) — idiomatic for
  the audience, and it sidesteps WM keybinding conflicts entirely.
- **Deferred, not rejected:** Wayland (portal / `libei`), built-in key self-grab,
  system tray, cards (field-at-a-time), per-entry custom sequences, optional trailing
  Enter.
- **Dependency:** `x11rb` added, Linux-gated like `libfido2`.

## References
- Origin: `ARCHITECTURE.md` -> Bikeshed "Autofill via auto-type", now Current Focus.
- Core principle "all keys and cryptography live in Rust" (`ARCHITECTURE.md`); the
  clipboard auto-clear it complements.
- Contrast: Android platform autofill (`GabbroAutofillService`); [ADR-013](ADR-013-vault-export-security-posture.md)
  (security posture of a secret leaving the app).
- Prior art: KeePassXC auto-type (X11 full / Wayland partial); the `xdotool`
  keycode-remap technique for arbitrary characters.
- X11: `_NET_ACTIVE_WINDOW`, `XTEST` (no `XGrabKey` — the key is WM/DE-owned); Rust
  crate `x11rb` (pure-Rust backend, no system X lib linked).
