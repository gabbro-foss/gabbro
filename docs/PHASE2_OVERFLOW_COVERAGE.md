# Phase 2 — Large-text overflow coverage ledger

Living checklist so **nothing falls through** during ADR-016 Phase 2 (text overflow
hardening). Every user-facing surface is listed. Delete this file when Phase 2 closes.

**Probe** = `test/overflow_probe_test.dart`: renders the surface at max scale on phone
(360dp -> 4x) and tablet (866dp -> 6x) and asserts `tester.takeException()` is null.
It catches **RenderFlex/layout overflow** (throws), NOT **silent fixed-box clips** (a
child clipped inside a fixed `width`/`height` throws nothing) — those are in the
watchlist and need a targeted check/fix each.

Status: `todo` / `in-probe` (added, passing) / `fixed` (had a defect, fixed+verified) /
`n/a`. **Hardware** column = maintainer confirmed on device.

## Standalone screens

| Screen | Probe | Silent-clip / notes | Hardware |
|--------|-------|---------------------|----------|
| about_screen | in-probe (pass) | | |
| appearance_screen | in-probe (pass) | P1 slider holds at 4x/6x | |
| change_passphrase_screen | todo | | |
| create_entry_screen | in-probe (pass) | throws nothing, BUT folder chooser is a **silent clip** (not a RenderFlex overflow — corrected 2026-07-03); see watchlist | |
| csv_mapping_screen | todo | **fixed `width:88` cell — silent clip** | |
| entry_detail_screen | todo | AppBar action crowding | |
| export_screen | todo | | |
| generator_screen | todo | embeds generator_widget | |
| help_screen | **overflow found (skip)** | pages don't scroll at max (728px phone / 168px tablet bottom); + page-dot spacing; Phase 2b pinch-zoom separate | |
| import_screen | todo | `SegmentedButton` may overflow | |
| language_screen | todo | | |
| manage_folders_screen | todo | folder-name row clip? | |
| manage_vaults_screen | todo | | |
| manage_yubikeys_screen | todo | | |
| onboarding_screen | **overflow found (skip)** | accessibility-button row overflows right (457px phone / 315px tablet) | |
| recovery_history_screen | todo | | |
| review_changes_screen | todo | embeds sync_review | |
| save_confirm_screen | todo | | |
| security_screen | todo | | |
| unlock_screen | todo | | |
| vault_list_screen (phone) | todo | | |
| tablet_vault_layout (two-pane) | todo | tablet-only 6x path | |

## Overlays / dialogs / sheets

| Surface | Probe | Silent-clip / notes | Hardware |
|---------|-------|---------------------|----------|
| import_failures_dialog | todo | | |
| import_skipped_dialog | todo | **fixed `height:300` — silent clip** | |
| password_breakdown_sheet | todo | (also a Phase 3 target-scaling item) | |
| sync_review (widget) | todo | | |
| yubikey_tap (widget) | todo | | |
| generator_widget | todo | | |

## Deferred (NOT Phase 2 overflow — tracked so they aren't forgotten)

- **alphabet_index_bar** — Phase 3 (hide on phone tier / scale on tablet), not an
  overflow fix.
- **help_screen pinch-to-zoom** — Phase 2b (its own feature).
- **Target/control scaling** (FABs, checkboxes, chevrons, `VisualDensity.compact`) —
  Phase 3.

## Silent-clip watchlist (probe blind spots — must be checked by hand/targeted test)

Strategy (agreed 2026-07-03): grep-sweep all of `lib/` for fixed
`width:`/`height:`/`maxWidth:`/`maxHeight:` wrapping text; a targeted test/fix per hit.
Sweep run 2026-07-03: 339 raw hits, the large majority `SizedBox(height:/width:)` Row/Column
**spacers** (benign). Real clip-risk = a fixed dimension on a box *containing text*. Triage
ongoing — confirmed/suspected below:

- **create_entry_screen folder chooser** — `DropdownButtonFormField` (line ~1686) + the
  `_dropdownField` helper (~1726): selected text clips at max scale (maintainer saw it on
  Android). Candidate fix `isExpanded: true` — VERIFY it's a clip first (probe throws nothing).
- csv_mapping_screen `width:88` cell.
- import_skipped_dialog `height:300` box.
- (continue triaging the 339-hit sweep; add each real risk here.)
