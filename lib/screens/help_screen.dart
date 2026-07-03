import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _kAssets = [
    'assets/help/help_000_onboarding.png',
    'assets/help/help_001_new_empty_vault.png',
    'assets/help/help_002_detail_view_password_detail_view.png',
    'assets/help/help_003_title_search.png',
    'assets/help/help_004_all_fields_search.png',
    'assets/help/help_005_card_filter.png',
    'assets/help/help_006_folder_list_view.png',
    'assets/help/help_007_item_select.png',
    'assets/help/help_008_move_to_letter.png',
    'assets/help/help_009_password_generator_show_password_breakdown.png',
    'assets/help/help_010_manage_vaults_main.png',
    'assets/help/help_011_unlock_screen.png',
    'assets/help/help_012_vault_sync.png',
  ];

  List<String> _captions(AppLocalizations l) => [
    l.helpCaptionCreate,
    l.helpCaptionEmpty,
    l.helpCaptionDetail,
    l.helpCaptionTitleSearch,
    l.helpCaptionFullSearch,
    l.helpCaptionFilter,
    l.helpCaptionFolders,
    l.helpCaptionSelect,
    l.helpCaptionJumpToLetter,
    l.helpCaptionBreakdown,
    l.helpCaptionManageVaults,
    l.helpCaptionUnlock,
    l.helpCaptionVaultSync,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Full-screen pinch-zoom/pan of a help screenshot. A separate route owns all
  // gestures cleanly (an in-place InteractiveViewer would fight the PageView's
  // horizontal swipe and the vertical scroll). ADR-016 Phase 2b.
  void _openZoom(BuildContext context, String asset) {
    final l = AppLocalizations.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.close,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.asset(asset, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final captions = _captions(l);
    final count = _kAssets.length;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: count,
                itemBuilder: (context, i) => LayoutBuilder(
                  // Fill the page when content fits; scroll when it doesn't (large
                  // text). The image is capped so the caption always has room.
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * 0.5,
                              ),
                              // The screenshot is a PNG: textScaler can't grow
                              // it and FLAG_SECURE blocks an external magnifier,
                              // so tap to open a full-screen pinch-zoom viewer
                              // (ADR-016 Phase 2b).
                              child: Tooltip(
                                message: l.helpEnlargeImage,
                                child: InkWell(
                                  onTap: () => _openZoom(context, _kAssets[i]),
                                  child: Stack(
                                    children: [
                                      Image.asset(
                                        _kAssets[i],
                                        fit: BoxFit.contain,
                                      ),
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              captions[i],
                              style: textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Navigation row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: l.tooltipPreviousPage,
                    onPressed: _currentPage > 0 ? () => _goTo(_currentPage - 1) : null,
                  ),
                  // ── Dot indicators ────────────────────────────────────────
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(count, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 10 : 6,
                        height: active ? 10 : 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                        ),
                      );
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: l.tooltipNextPage,
                    onPressed: _currentPage < count - 1 ? () => _goTo(_currentPage + 1) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
