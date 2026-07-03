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
| create_entry_screen | in-probe (pass) | `isExpanded:true` on 3 dropdowns (stops throw). **NOT the reported bug** (that was vault_list). Selected value still one-line -> also needs `selectedItemBuilder` ellipsis like vault_list; apply after that verifies | pending |
| vault_list_screen (phone) | todo (probe) | **folder-filter dropdown FIXED** (the actual maintainer report): `selectedItemBuilder` ellipsis on BOTH phone (~1629) + tablet (~1548) paths, else the one-line selection hard-clips at 4x | **re-verify** |
| csv_mapping_screen | todo | **fixed `width:88` cell — silent clip** | |
| entry_detail_screen | todo | AppBar action crowding | |
| export_screen | todo | | |
| generator_screen | todo | embeds generator_widget | |
| help_screen | **fixed** | pages now fill-or-scroll (was 728px phone / 168px tablet bottom), image capped 50%; page-dot spacing minor/open; Phase 2b pinch-zoom separate | pending |
| import_screen | todo | `SegmentedButton` may overflow | |
| language_screen | todo | | |
| manage_folders_screen | todo | folder-name row clip? | |
| manage_vaults_screen | todo | | |
| manage_yubikeys_screen | todo | | |
| onboarding_screen | **fixed** | a11y-button row: Spacer->spaceBetween + Flexible ellipsizing button (was 457/315px right) | pending |
| recovery_history_screen | todo | | |
| review_changes_screen | todo | embeds sync_review | |
| save_confirm_screen | todo | | |
| security_screen | todo | | |
| unlock_screen | todo | | |
| tablet_vault_layout (two-pane) | todo | tablet-only 6x path (folder-filter dropdown covered above) | |

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

- **create_entry_screen folder chooser** — FIXED: `isExpanded: true` on all 3
  `DropdownButtonFormField`s (folder ~1686, `_dropdownField` ~1726, card-status ~1304) so a
  long value wraps instead of clipping. Not test-assertable (silent) -> pending hardware.
- csv_mapping_screen `width:88` cell.
- import_skipped_dialog `height:300` box.
- (continue triaging the 339-hit sweep; add each real risk here.)
