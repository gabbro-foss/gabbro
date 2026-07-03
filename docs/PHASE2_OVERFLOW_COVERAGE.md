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
| change_passphrase_screen | in-probe (pass) | | |
| create_entry_screen | in-probe (pass) | **fixed** all dropdowns (folder + card-status + `_dropdownField`/payment-network): `isExpanded:true` + `itemHeight:null` + `selectedItemBuilder` ellipsis | pending |
| vault_list_screen (phone) | todo (probe) | **folder-filter dropdown FIXED** (the actual maintainer report): `selectedItemBuilder` ellipsis on BOTH phone (~1629) + tablet (~1548) paths, else the one-line selection hard-clips at 4x | **re-verify** |
| csv_mapping_screen | **fixed** | mapping rows stack label-above-dropdown at >1.5x (was illegible `width:88`); dropdown gets 3-part fix; preview DataTable row-height cap removed (`dataRowMaxHeight: infinity`) | pending |
| entry_detail_screen | todo | AppBar action crowding | |
| export_screen | in-probe (pass) | | |
| generator_screen | in-probe (pass) | embeds generator_widget | pending |
| help_screen | **fixed** | pages now fill-or-scroll (was 728px phone / 168px tablet bottom), image capped 50%; page-dot spacing minor/open; Phase 2b pinch-zoom separate | pending |
| import_screen | todo | `SegmentedButton` may overflow | |
| language_screen | in-probe (pass) | **fixed**: note moved inside the scroll list (was Column+Expanded, overflowed 48px at 4x) | pending |
| manage_folders_screen | todo | reassign dropdown + delete-dialog content scroll fixed | pending |
| manage_vaults_screen | todo | | |
| manage_yubikeys_screen | todo | | |
| onboarding_screen | **fixed** | a11y-button row: Spacer->spaceBetween + Flexible ellipsizing button (was 457/315px right) | pending |
| recovery_history_screen | todo | | |
| review_changes_screen | todo | embeds sync_review | |
| save_confirm_screen | todo | | |
| security_screen | in-probe (pass) | dialogs scrollable:true | pending |
| unlock_screen | todo | vault-alias dropdown fixed (large-text pattern) | |
| tablet_vault_layout (two-pane) | todo | tablet-only 6x path (folder-filter dropdown covered above) | |

## Overlays / dialogs / sheets

| Surface | Probe | Silent-clip / notes | Hardware |
|---------|-------|---------------------|----------|
| import_failures_dialog | todo | | |
| import_skipped_dialog | **fixed** | was `SizedBox(height:300)` -> `scrollable:true` + plain Column of items (a ListView breaks scrollable's intrinsic-width pass); targeted test at 4x | pending |
| password_breakdown_sheet | todo | (also a Phase 3 target-scaling item) | |
| sync_review (widget) | todo | | |
| yubikey_tap (widget) | todo | | |
| generator_widget | in-probe (pass) | language dropdown fixed; length/words label-value Rows now Expanded+ellipsis (were spaceBetween, overflowed 122px) | pending |

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
- **Dropdown fix pattern (ADR-016):** at large text a `DropdownButton`/`FormField` needs
  ALL THREE: `isExpanded:true` (fill width), `itemHeight:null` (open-menu items grow to
  wrapped height, else clipped mid-height at 48px), `selectedItemBuilder` with
  `maxLines:1, overflow: ellipsis` (collapsed selection truncates cleanly, not hard-clip).
  DONE: vault_list (both paths), create_entry (all), unlock_screen, manage_folders_screen,
  generator_widget. **TODO:** csv_mapping_screen dropdown (deferred to its own pass with the
  `width:88` label fix below).
- ~~csv_mapping_screen `width:88` cell~~ DONE (stack label-above-dropdown at large text;
  also removed the preview DataTable fixed row height).
- ~~import_skipped_dialog `height:300`~~ DONE (scrollable:true + a plain Column of items;
  a ListView throws in scrollable's intrinsic-width pass — for a short list-in-dialog use a
  Column and let the dialog's own scroll own it).
- (continue triaging the 339-hit sweep; add each real risk here.)

## AlertDialog scrollability (another probe blind spot — dialogs are action-triggered)

At large text a multi-widget dialog overflows past the dialog bounds. **CORRECTED FIX
(2026-07-03): use `AlertDialog(scrollable: true)` with a plain Column** — NOT a
`SingleChildScrollView` around `content`. Content-only wrapping scrolls the content but
leaves the title + action buttons fixed, so a dialog taller than the screen still strands
the buttons off-screen (maintainer hit this on the biometric-consent dialog, which already
had the content wrap). `scrollable: true` scrolls title + content + actions together. Do
NOT combine it with an inner `SingleChildScrollView` (nested scroll -> unbounded-height
throw); remove the manual wrap when adding `scrollable: true`.

Audit every `AlertDialog` with Column/ListView content:

- **ALL dialogs now use `scrollable: true`** (verified pattern; biometric-consent
  hardware-confirmed). Converted: security (consent + enroll), manage_folders (delete),
  manage_vaults (YubiKey-auth-delete + backup-info), manage_yubikeys (add-key steps,
  add-key transport+PIN [+ chip `Row`->`Wrap`], remove-key warning), entry_detail
  (export-file), import_failures, vault_list (sync-summary + sync-from-file). No
  `content: SingleChildScrollView` remains in lib/. Chip `Row`->`Wrap` stays.
- Skipped (short single-TextField / plain-Text content, won't strand buttons): rename-vault,
  rename/add-folder, edit-alias, delete-vault-warning, delete-entry-confirm.
- **Enumeration gap learned:** grep for `content: Column(` MISSES content built into a
  variable (e.g. yubikeys `warningContent`) — re-audit with `content: <ident>` too.
