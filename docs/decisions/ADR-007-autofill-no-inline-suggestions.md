# ADR-007 — Autofill: no inline keyboard suggestions

## Status
Accepted

## Date
2026-05-12

## Context
Android 11 introduced inline autofill suggestions — credentials appear as
chips in the keyboard suggestion bar rather than as a floating overlay below
the focused field. This is opt-in for autofill service providers and requires
explicit cooperation from the keyboard app.

Gabbro's core principle is that secrets are never exposed through untrusted
channels. Android keyboards are a known risk vector:

- Keyboard apps have full access to every keystroke typed into any field.
- Several major keyboards (Samsung Keyboard, Gboard) maintain proprietary
  clipboard history rings that survive `Clipboard.setData('')` clear calls —
  a limitation already documented in LEARNINGS.md.
- Delegating credential display to a keyboard app introduces a third party
  into the credential delivery path that Gabbro cannot audit or control.
- Inline suggestions require the keyboard to render Gabbro's credential data
  inside its own process. This is architecturally incompatible with the
  principle of minimising plaintext exposure outside trusted boundaries.

## Decision
Gabbro will never implement inline autofill suggestions. All autofill
credential presentation uses the standard Android `FillResponse` dropdown
overlay, which is rendered by the Android framework itself — not by any
keyboard app.

This applies permanently, not just for v1. It is not a resourcing decision;
it is a security stance.

## Consequences
- Users on Android 11+ will not see credentials in the keyboard suggestion
  bar. This is intentional.
- The dropdown overlay is the only autofill presentation surface.
- Users who prefer the inline UX can use any other autofill provider;
  Gabbro documents this limitation honestly.
- No dependency on keyboard app behaviour, no exposure to keyboard clipboard
  managers, no third-party process in the credential delivery path.
- Users who prefer not to use autofill at all retain full copy/paste
  functionality from the entry detail screen at all times. Autofill is
  an opt-in convenience layer, never a replacement for manual credential
  access.