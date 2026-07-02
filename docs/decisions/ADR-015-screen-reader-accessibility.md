# ADR-015: Screen-Reader Accessibility as a Tested Requirement

## Status
Accepted.

## Date
2026-07-02

## Context

Gabbro is a security tool people must be able to operate confidently — including
blind and low-vision users who navigate entirely by screen reader (TalkBack on
Android, Orca on Linux/GTK). A control that announces a bare role — "button",
"text field", "tick box" — is unusable to them, and the flows where that hurts
most are exactly the security-critical ones: unlock, onboarding, passphrase/PIN
entry, autofill, generation.

Support so far has been added reactively. The alpha.10 a11y sweep labelled the
show/hide eye toggles and many icon buttons across ~12 screens, and some widget
tests assert `labeledTapTargetGuideline`. But there is **no documented standard**,
so coverage drifts: a new screen or control can ship with bare announcements
whenever someone forgets, and "is this accessible?" has no crisp acceptance bar.

Visual / low-vision accessibility (contrast, and a larger continuous text-size
control) is a separate concern tracked in the backlog and is **out of scope for
this ADR**.

## Decision

Adopt screen-reader accessibility as a first-class, **tested** requirement.

1. **Every interactive control carries a meaningful semantic label.** No control
   may announce only its role. User-visible labels are localized.
2. **Enforced in widget tests.** Each screen with interactive controls asserts the
   Flutter accessibility guidelines — `labeledTapTargetGuideline` (plus
   `androidTapTargetGuideline` / `textContrastGuideline` where applicable) — so an
   unlabelled control fails the suite, not the user.
3. **Reference readers:** TalkBack (Android) and Orca (Linux/GTK). A flow is
   "accessible" when it is fully operable and comprehensible with the screen reader
   on and the display unseen.
4. **State changes and errors are announced.** Transient feedback (SnackBars,
   inline auth errors) and dynamic content carry labels / live-region semantics so
   a non-visual user learns an action's outcome — wrong passphrase, "vault synced",
   copied-to-clipboard.
5. **New work must pass before merge.** Any new screen or interactive widget lands
   with the guideline assertion alongside its behaviour tests.

## Consequences

- **Positive:** the app is operable by screen-reader users across every
  security-critical flow; regressions are caught mechanically in the test suite
  rather than relying on a sighted reviewer; gives a crisp, reusable acceptance bar.
- **Cost:** every new interactive widget needs a label plus a guideline assertion;
  some widgets (custom painters, icon-only buttons, per-digit PIN boxes) need
  explicit `Semantics` wrapping. Localized labels add l10n strings.
- **Retro-active, not big-bang:** existing screens are swept opportunistically when
  touched (e.g. the current Enter-submit pass double-checks every passphrase/PIN
  field's labelling); no full audit is mandated, but no new gaps are permitted.
- **Not covered here:** visual/low-vision accessibility (contrast, larger
  text-size slider). A high-contrast theme already exists; the slider is a backlog
  item.

## References
- Flutter test guidelines: `labeledTapTargetGuideline`, `androidTapTargetGuideline`,
  `textContrastGuideline` via `meetsGuideline` (`flutter_test`).
- Semantics in tests: `SemanticsNode.flagsCollection` (post Flutter 3.32).
- alpha.10 a11y sweep — screen-reader labels across ~12 screens (eye toggles,
  browse, folder add/edit/delete, vault-list, help navigation, chevrons).
- Reference readers: Android TalkBack; Linux Orca (GTK / AT-SPI).
