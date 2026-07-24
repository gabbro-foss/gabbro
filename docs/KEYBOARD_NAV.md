# Keyboard Navigation — Design Spec (DRAFT, for approval)

Status: DRAFT for maintainer review. Branch `keyboard_accessibility_sweep`.
Not yet built. Supersedes the ad-hoc Tab behaviour surfaced in round-2 hardware
testing (illogical order, no visible focus during traversal).

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
- Region order (maintainer-specified):
  1. Alphabet / index bar (left or right icon bar) — *only when shown*
  2. Search bar
  3. Folder list
  4. Entry category chips
  5. Entry list
  6. Detail view — *two-pane (tablet) only*
- The **FAB is never** in the cycle.
- Single-pane (phone): the detail view is a separate pushed screen, so it is not
  a Tab region on the list screen; `Enter` on an entry pushes it, `Esc` pops it.

## Arrows — within the focused region

| Region | Keys | Behaviour |
|---|---|---|
| Alphabet / index bar | ↑ / ↓ | move between letters; Enter jumps the list to it |
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

- **D1 — Index bar is a Tab-stop only when it is shown** (indexable locale;
  left or right). Skipped from the cycle when absent.
- **D2 — List arrows STOP at the ends** (no wrap): Down on the last item and Up
  on the first are no-ops.
- **D3 — Search + ↓ does NOTHING.** The convenience of jumping into the list
  isn't naturally discoverable in the UI, so for consistency the search box has
  no arrow behaviour — use Tab to reach the list.
- **D4 — Esc on a sub-screen: unfocus first, then back.** One uniform rule: the
  first Esc clears the region frame (→ Unfocused), a second Esc pops the screen.

## Accessibility (non-negotiable, every phase)

The visual frame is one cue among several — this work is not done until it works
for assistive tech too:

- **Semantics label + hint on every region and control**, so a screen reader
  (Orca on Linux, TalkBack on Android) announces *what* it is and *what Enter /
  the arrows do* there. The focus frame must never be the sole indicator.
- **Tooltips on every icon-only control** (back arrows, index bar, chips).
- **Entering a region announces it** to the screen reader (e.g. "Folder list").
- Extend the a11y net (`test/a11y_net_test.dart` — labeled-tap-target + contrast
  sweeps) to the new controls; the keyboard net covers traversal.
- The **focus-frame colour passes contrast** in light, dark, and both
  high-contrast themes (the a11y net's contrast modes).

## Build sequence (after approval)

1. **Global Esc model + physical-key shortcut fix.** Small, high-value, testable
   now; fixes the two round-2 Esc gaps and the non-Latin bug.
2. **Region FocusTraversalGroups + Tab cycle + focus frame.**
3. **Within-region arrows.**

Each phase: extend the keyboard net (`test/keyboard_net_test.dart`), then
hardware-test before moving on.
