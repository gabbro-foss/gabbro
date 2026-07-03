# ADR-016: Large-Text and Target Scaling as a Tested Accessibility Requirement

## Status
Accepted.

## Date
2026-07-02

## Context

Accessibility is core to Gabbro's identity — *accessible, transparent, safe*. It is
not an afterthought: [ADR-015](ADR-015-screen-reader-accessibility.md) made
screen-reader operation a tested requirement, and ADR-003 covers colour-blind
password display. ADR-015 explicitly deferred **visual / low-vision accessibility**
(a larger continuous text-size control) to the backlog. This ADR is that follow-up,
and ADR-015 is its birth.

The existing text-size control is a discrete list (`TextSizeChoice`: small → xxLarge)
topping out at **1.5×**. That is far too timid: severely vision-impaired users read at
sizes where a single short word spans the screen, and they disproportionately rely on
tablets for the larger display. The current control also *itself* breaks at large text
(a `SegmentedRow` of five labels overflows).

Two facts shape the design:

1. **Text and targets are separate problems.** Flutter's `textScaler` grows *text*
   only — not icons, the FAB, chevrons, checkboxes, the alphabet-bar letter circles,
   or drag handles. A user who cannot read small text also cannot *hit* small targets,
   so controls must grow too.
2. **The same scale means different things per device.** Logical pixels (dp) are
   density-independent, so `textScale = 2.0` is physically ~2× text on any device.
   What differs is screen *room*: a phone's short side is ~380 dp, a tablet's ~920 dp
   (~2.4× more). The tablet carries a larger scale comfortably; a phone strains sooner
   (but a low-vision user accepts one-word-per-line and scrolling).

A survey of all ~25 screens found most bodies already scroll (so vertical growth is
fine), but a set of **fixed-size boxes** clip scaled text, and several **fixed-size
controls** become untappable — most severely the alphabet index bar and the password
breakdown sheet. Gabbro also sets `FLAG_SECURE` (no screenshots), so a low-vision user
cannot capture and magnify the help screens externally.

## Decision

Adopt large-text and proportional target scaling as a first-class, **tested**
accessibility requirement.

1. **One knob, everything in unison.** A single absolute `textScale` (1.0 = normal),
   stored in settings, drives both text and control/target sizing. No second "large
   controls" toggle.

2. **Screen-derived maximum, reusing the 600 dp breakpoint** (the same phone-vs-tablet
   split used for the two-pane layout). **Phase-0 hardware readings (2026-07-02):**
   phones — **S23 = 360 dp** (dpr 3.0), **GrapheneOS = 411 dp** (dpr 2.63); tablet —
   **Idea Tab Pro = 866 dp** (dpr 2.125, 1840×2944 @ 340 dpi). Phone tier spans
   **360–411 dp** (360 dp = worst case → the phone surface for the overflow probe);
   tablet has ~2.1–2.4× the room.
   - **Phone tier (<600 dp): max 2×** (the WCAG 1.4.4 resize bar; severe low-vision
     belongs on a tablet, where the phone form factor stops fighting back).
   - **Tablet tier (≥600 dp): max 3×.**
   Phase 0 fixed the tiers and the ratio; the ceilings were **dialled in live on the
   slider in Phase 1-2** — each hardware pass (2026-07-03) found the top of the range
   unusable / still clipping, so the ceilings were trimmed in stages
   (6×/8× -> 4×/6× -> 3.5×/5× -> 3.0×/5× -> 2×/4×) to the final **2× / 3×**.
   A stored value is **clamped to the current device's max on load**, so a large value
   set on a tablet cannot break the UI when the vault is opened on a phone.

3. **Targets scale proportionally, capped.** Control/target size grows off the same
   `textScale` on a gentler curve, reaching **~2×** at the device's maximum text scale
   (`targetScale = lerp(1.0 → 2.0)` across the device's text range) — big enough to
   hit, never large enough to consume the screen. Cap calibrated on hardware.

4. **Continuous slider with a perceptual (exponential) slope.** Replaces the discrete
   list: a slider bracketed by **letter-free zoom glyph icons** (`Icons.zoom_out` /
   `Icons.zoom_in`, not localized words and — unlike the originally-planned
   `Icons.text_decrease` / `Icons.text_increase`, which depict a Latin **A** — carrying
   no letter, so nothing foreign for Cyrillic/Greek/CJK users and no l10n), with
   live-preview sample text (the brand word in onboarding, a full sample sentence on the
   appearance screen). The position → scale mapping is exponential so the
   everyday range (~0.8–2.0) occupies most of the track for fine control, accelerating
   toward the device max. Minimum 0.8×.

5. **Onboarding surfaces it prominently.** The accessibility toggle, when ON, sets a
   strong (~3×) scale, **reveals the slider inline**, and **hides the logo** to reclaim
   vertical space; OFF hides the slider, restores the logo, and returns to 1×. The same
   reusable slider widget appears on the appearance screen.

6. **Device-aware component fallbacks.** Where a control cannot scale sensibly:
   - **Alphabet index bar:** on the **phone tier**, hidden above a scale threshold
     (reusing the existing CJK "no orderable index → plain scroll + search" fallback);
     on the **tablet tier**, kept and its cells/chevrons scaled (there is room).
   - **Help screens:** gain **in-app pinch-to-zoom** on their content, because
     `FLAG_SECURE` blocks external screenshot magnification.

7. **Enforced in tests.** Beyond ADR-015's labelling guidelines:
   - A headless **overflow probe** renders key screens at the maximum scale on phone-
     and tablet-size surfaces and asserts **no RenderFlex overflow and no clipped
     text** (the FAB and alphabet bar are explicit cases).
   - Key touch targets meet a **minimum size at every scale** (≥48 dp; targets grow,
     never shrink — `VisualDensity.compact` is removed from accessibility-relevant
     controls).
   - Settings **migration** from the old `TextSizeChoice` strings to the new `double`
     is pinned (backward-compat), and out-of-range values clamp.

## Consequences

- **Positive:** low-vision users can operate the whole app at genuinely large sizes,
  sized appropriately to their device; regressions (overflow, shrunken targets) are
  caught mechanically; accessibility becomes a measured property, not a hope.
- **Cost / breadth:** this is an initiative, not a single change. The slider + model is
  one focused pass; hardening every screen's layout and scaling every control is a
  multi-session, screen-by-screen effort, each hardware-verified. Delivered in phases
  (tracked in `ARCHITECTURE.md` → Current Focus); the slider ships first and becomes
  the probe for the rest.
- **Calibration dependency:** the ADR fixes the *model*, not the constants. Measured on
  the maintainer's phone and tablet (2026-07-03): phone 2× / tablet 3× / target cap 2×;
  earlier 6×/8×, 4×/6×, 3.5×/5×, 3.0×/5×, 2×/4× were all too large / still clipping.
- **Not covered here:** contrast (a high-contrast theme already exists) and
  screen-reader labelling (ADR-015) — this ADR composes with both.

## References
- Sibling: [ADR-015](ADR-015-screen-reader-accessibility.md) (screen-reader), ADR-003
  (colour-blind password display).
- Two-layout split (600 dp): phone list vs tablet two-pane — reused for the scale tier.
- Flutter: `MediaQuery.textScaler` / `TextScaler.linear`; `MediaQuery.sizeOf` +
  `devicePixelRatio` for the device tier; `meetsGuideline(androidTapTargetGuideline)`.
- `FLAG_SECURE` (screenshot suppression) — the reason help needs in-app zoom.
