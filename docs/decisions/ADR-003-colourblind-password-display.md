# ADR-003 — Colour-Blind-Friendly Password Character Display

**Date:** 2026-03-18
**Status:** Accepted

---

## Context

Gabbro's password generator displays generated passwords with
character-type coding to help users visually distinguish character
classes (symbols, digits, lowercase, uppercase). The original concept
used colour circles as shorthand (🔵 🔴 🟢 🟡).

The concern raised: colour alone is not accessible. Approximately 8% of
men and 0.5% of women have some form of colour vision deficiency (CVD).
The most common forms — deuteranopia and protanopia — cause difficulty
distinguishing red from green, which rules out the most obvious palette
choices.

We must not use colour as the *only* differentiator.

---

## Decision

Character type coding will use **both colour and a symbol marker**,
so that users who cannot distinguish the colours can still read the
type from the symbol alone.

### Default markers

| Character type | Symbol | Default colour | Colour-blind safe? |
|---|---|---|---|
| Uppercase | `A` (bold/large) | Blue `#5B9BD5` | ✅ |
| Lowercase | `a` (regular) | Teal `#2E9B8F` | ✅ (distinct from blue) |
| Digit | `#` | Amber `#E6A817` | ✅ (yellow-orange, distinct from blue/teal) |
| Symbol | `@` | Purple `#9B6BBF` | ✅ |

The default palette avoids the red/green pair that causes the most
failures. Blue, teal, amber, and purple are distinguishable under
the most common CVD simulations (deuteranopia, protanopia,
tritanopia).

### User override

Users may override the colour for each character type individually
via a colour picker in Settings → Appearance → Password colours.
The marker symbols are not overridable (they are the accessibility
fallback).

### Implementation note

The colour + symbol rendering lives in Flutter (pure UI concern).
The character classification (which class a character belongs to)
lives in Rust, returning a typed enum across the bridge. Flutter
maps the enum to the display style. This respects the
Flutter:Rust::Frontend:Backend separation.

---

## Principle: Never colour alone

This decision encodes a general accessibility principle for the
whole app: **colour may be used to reinforce meaning, but never
as the sole carrier of meaning.** All colour coding elsewhere in
the app (folder colours, status indicators, etc.) should follow
the same rule.

---

## Alternatives Considered

| Option | Reason rejected |
|---|---|
| Keep original RGB emoji circles | Not accessible; emoji rendering inconsistent across platforms |
| Greyscale only | Accessible but loses the UX benefit of quick visual scanning |
| User chooses everything from scratch | Too much friction; good defaults serve most users |
| Shapes only, no colour | Works but misses the speed advantage colour gives users with normal vision |

---

## References

- WCAG 2.1 Success Criterion 1.4.1: Use of Colour
- Colour Universal Design (CUD) palette by Masataka Okabe & Kei Ito
- CVD prevalence: ~8% male, ~0.5% female (Colour Blind Awareness)
