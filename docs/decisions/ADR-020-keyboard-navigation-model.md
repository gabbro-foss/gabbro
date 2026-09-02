# ADR-020: Keyboard Navigation Model (Linux Desktop)

## Status
Accepted — built, merged (`keyboard_accessibility_sweep`), hardware-passed.
Records the rationale from the retired design spec `docs/KEYBOARD_NAV.md`.

## Date
2026-07-24 (decisions) / 2026-09-02 (recorded as ADR)

## Context

Round-2 hardware testing surfaced ad-hoc Tab behaviour: illogical order, no
visible focus. A keyboard-only user could not tell where they were or reach
what they needed.

## Decision

**Tab** escalates into and through a fixed, wrapping cycle of **regions**
(search bar, folder list, category chips, entry list, detail pane); **arrows**
move within the focused region; **Esc** de-escalates one level back to the
unfocused resting state — the inverse of Tab. The focused region carries a
visible border (the qtile `border_focus` metaphor); the item highlight inside
answers "which item", the frame answers "which region".

Resolved sub-decisions and why:

- **D1 — index bar and search-mode toggle are not Tab stops.** Up/Down in the
  list and Ctrl+F already reach them (DRY).
- **D2 — list arrows stop at the ends**, no wrap.
- **D3 — search + Down does nothing.** The jump-to-list convenience is not
  discoverable, so the search box has no arrow behaviour at all — Tab reaches
  the list.
- **D4 — Esc on a sub-screen unfocuses first, then pops.** One uniform rule;
  every back arrow and Cancel is reachable by Esc.
- **D5 — the focus highlight is Linux-only.** It exists to serve keyboard
  navigation; Android renders no frames and suppresses the search outline, so
  gesture behaviour is untouched and no unfocus-on-tap logic is needed. Splits
  the a11y layer: control labels everywhere, region semantics Linux-only.
- **FAB, lock, overflow, nav rail are excluded from the cycle**; since Tab is
  the only traversal, each gets a shortcut instead (Ctrl+N, Ctrl+L, Ctrl+M,
  Ctrl+Q).
- **Shortcuts match the physical key** (`PhysicalKeyboardKey`), not the logical
  one — a logical match silently breaks on Cyrillic/Greek layouts.

## Mechanism note

Tab is driven by the global `HardwareKeyboard` handler in `main.dart` plus an
app-root absorber `Actions` at `MaterialApp.builder`: it swallows Flutter's
built-in Tab traversal while the vault list owns Tab and performs normal
traversal everywhere else. A body-scoped `Actions` silently failed on hardware
(round 10) — do not revert to it.

## Consequences

- Keyboard-only operation of the whole vault list; screen readers announce
  regions on entry (Linux).
- Excluded controls are keyboard-unreachable by design; anything new outside
  the cycle needs its own shortcut.
- Pinned by the keyboard/a11y nets (`test/keyboard_region_cycle_test.dart`,
  `test/a11y_net_test.dart`).

## References
- ADR-015 (screen-reader accessibility), ADR-016 (large-text scaling).
