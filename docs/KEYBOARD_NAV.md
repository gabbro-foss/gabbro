# Keyboard Navigation — Design Spec

Status: built. Every phase, D5 (highlight gated to Linux) and the a11y layer are
hardware-passed on branch `keyboard_accessibility_sweep` (rounds 13-31; NOT yet
merged). Why each mechanism is what it is — and what failed on hardware first —
is in LEARNINGS.md. Supersedes the ad-hoc Tab behaviour surfaced in round-2
hardware testing (illogical order, no visible focus).

## Model in one sentence

**Tab** escalates into and through a fixed, wrapping cycle of **regions**;
**arrows** move within the focused region; **Esc** de-escalates back out to the
initial unfocused state. Esc is the inverse of Tab — the `break` out of the
cycle. Ctrl shortcuts (L, F) are global and matched on the **physical** key.

## Three states

1. **Unfocused** (on open): no region framed. The neutral resting state.
2. **Region-focused**: exactly one region carries a visible frame (see Focus
   frame). Reached by Tab from Unfocused.
3. **Editing** (search only): the search field holds a text cursor; typing
   filters. A sub-state of Region-focused.

## Tab / Shift+Tab — between regions

- From **Unfocused**, `Tab` focuses the **first** region; `Shift+Tab` focuses
  the **last**.
- The cycle **wraps** (last → first, first → last). It never "falls out" — Esc
  is the only way back to Unfocused.
- Region order (as built):
  1. Search bar
  2. Folder list — *only when the vault has folders*
  3. Entry category chips
  4. Entry list
  5. Detail view — *wide (two-pane) only, and only when an entry is selected*
- **Not a stop:** the search-mode toggle icon (Ctrl+F / Ctrl+Shift+F reach and
  set it directly — DRY), and the alphabet/index bar (Up/Down in the list already
  covers it — DRY). Both dropped from the original order.
- **Excluded** (never a Tab stop): FAB, select-entries, lock, overflow menu, nav
  rail. Consequence — since Tab is the only traversal (the default is absorbed),
  excluded controls are keyboard-*unreachable*, so the ones a keyboard user still
  needs get a shortcut: **Ctrl+N** opens the new-entry picker (the FAB), **Ctrl+M**
  opens the overflow menu, **Ctrl+L** locks, **Ctrl+Q** raises the menu's own
  lock-and-quit confirm. Select-entries stays mouse-only for now.
- Narrow (single-pane): the detail view is a separate pushed screen, so it is not
  a Tab region on the list screen; `Enter` on an entry pushes it, `Esc` pops it.

## Mechanism (as built)

Tab / Shift+Tab is driven by the **global `HardwareKeyboard` handler** in
`main.dart` (the same path as Ctrl+L/F), routed to a vault-list hook that moves
focus to the next/previous region stop. Flutter's built-in Tab→Next/Previous-
FocusIntent traversal is **not** suppressed by that handler, so an **app-root
absorber** (an `Actions` at `MaterialApp.builder`, below WidgetsApp's defaults and
above every route's `ModalScope`) swallows it while the vault list owns Tab, and
performs normal traversal everywhere else. The earlier body-scoped `Actions`
approach was abandoned (it silently failed on hardware, round 10).

## Arrows — within the focused region

| Region | Keys | Behaviour |
|---|---|---|
| Search bar | (none) | text cursor; type to filter |
| Folder list | ↑ / ↓ | move selection; Enter selects the folder |
| Category chips | ← / → | move between chips; Enter/Space toggles the filter |
| Entry list | ↑ / ↓ | move selection; Enter opens the entry |
| Detail view | ↑ / ↓ | scroll the detail pane |

## Enter / Space

Activate the focused item (open entry, select folder, toggle chip, jump letter,
press a button). Standard Flutter button activation already covers buttons.

## Esc — de-escalate one level (the `break`)

Precedence, most-local first:

1. A **modal dialog / popup** is open → close it. Special dialogs keep their own
   result (sync review cancels with **rollback**, not a bare pop).
2. A **region is focused** (incl. the search field) → return to **Unfocused**
   (clear the frame / blur the field).
3. **Unfocused on a pushed sub-screen** (has a back arrow) → **go back** (pop).
4. **Unfocused on the root screen** → nothing.

Consequence: **every back-arrow and every Cancel affordance is reachable by Esc.**

## Focus frame — the qtile-border metaphor

qtile styles the focused window with `border_focus` / `border_normal` /
`border_width`. The direct analogue here: draw a **colored border around the
focused region** (the search box, a list's box, the chips row, the detail pane)
— **not** around individual items.

- Shown **only** in Region-focused state; absent when Unfocused.
- Colour from the theme, legible in light, dark, and both high-contrast modes;
  width ~2–3 dp.
- The *selected item within* a list keeps its existing highlight (maintainer
  confirmed that is already fine) — the frame answers "which region," the item
  highlight answers "which item."

## Shortcuts on non-Latin layouts

Match `PhysicalKeyboardKey.keyL` / `.keyF`, **not** the logical key. On a
Cyrillic/Greek layout the physical F-key emits a non-Latin letter, so a logical
match silently fails — currently Ctrl+L and Ctrl+F break on those layouts. CJK
IMEs pass Ctrl-chords through, so the physical match reaches the app regardless.

## Resolved decisions (maintainer, 2026-07-24)

- **D1 — Index bar is NOT a Tab-stop** (revised 2026-07-25): dropped from the
  cycle entirely (Up/Down in the list already scrolls it — DRY). Same call
  dropped the search-mode toggle as a stop (Ctrl+F reaches it).
- **D2 — List arrows STOP at the ends** (no wrap): Down on the last item and Up
  on the first are no-ops.
- **D3 — Search + ↓ does NOTHING.** The convenience of jumping into the list
  isn't naturally discoverable in the UI, so for consistency the search box has
  no arrow behaviour — use Tab to reach the list.
- **D4 — Esc on a sub-screen: unfocus first, then back.** One uniform rule: the
  first Esc clears the region frame (→ Unfocused), a second Esc pops the screen.
- **D5 — the focus highlight is Linux-only** (2026-07-25): it exists to serve
  keyboard navigation, so on Android *nothing* of it appears — no region frames
  in the tree, and the search field gets no focused outline (Material's default
  one is suppressed too). A tablet-width Android device gains nothing from it;
  gestures still drive. Consequence: no unfocus-on-tap-outside logic and no
  keyboard-visibility observer — Android behaviour is simply untouched. It also
  splits the a11y layer below: control labels everywhere, regions on Linux only.

## Accessibility (non-negotiable, every phase)

A screen-reader user hears the app instead of seeing it, so the visual frame can
never be the only cue. D5 splits this in two, because regions only exist on Linux:

**Both platforms — every control speaks its name.**
- **Semantics label + hint on every control**, so Orca (Linux) and TalkBack
  (Android) say *what it is* and *what Enter / the arrows do*.
- **Tooltips on every icon-only control** (back arrows, index bar, chips).
- Extend the a11y net (`test/a11y_net_test.dart` — labeled-tap-target + contrast
  sweeps) to the new controls; the keyboard net covers traversal.

**Linux only — the regions speak too.**
- **Semantics label + hint on each region**, and **entering one announces it**
  (e.g. "Folder list"). There is nothing to announce on Android: no regions.
- The **focus-frame colour passes contrast** in light, dark, and both
  high-contrast themes (the a11y net's contrast modes).

## Build sequence

1. **Global Esc model + physical-key shortcut fix — DONE, hardware-passed.**
2. **Focus frame** (qtile-style region border) — DONE, hardware-passed.
3. **Region Tab-cycle + within-region arrows (both layouts) + Ctrl+N/Ctrl+M —
   DONE, hardware-passed (round 13).** Rounds 10–12 each found one defect on
   hardware that no headless test could see; causes are in LEARNINGS.md.
4. **a11y layer** — control labels/hints on both platforms; region Semantics,
   region-entry announcement and focus-frame contrast on Linux only (D5); a11y-net
   extension; Orca pass. **Net-first floor done; canon-TDD not started** — see
   ARCHITECTURE.md `### Next task`.

Each phase: net-first (pin current behaviour), then canon-TDD, then hardware-test
before moving on.
