import 'package:flutter/material.dart';

// Default (Latin) canon used when no locale-specific alphabet is supplied.
const _kLatinCanon = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
];

// Minimum slot height that keeps letters readable.
const _kMinSlotHeight = 28.0;
// Height consumed by one chevron button (including its SizedBox wrapper).
const _kChevronHeight = 32.0;

class AlphabetIndexBar extends StatefulWidget {
  // Ordered canonical slot set (locale's alphabet + '#'). The full set is always
  // rendered; absent letters are greyed. Defaults to the Latin canon.
  final List<String> letters;
  final Set<String> presentLetters;
  final void Function(String letter) onLetterSelected;
  // The letter the window should be centred on at first build.
  // Defaults to the first present letter if null.
  final String? initialLetter;
  // A11y labels for the windowed-mode scroll chevrons. The screen passes
  // localized strings; the English defaults are for the widget in isolation.
  final String scrollUpLabel;
  final String scrollDownLabel;

  const AlphabetIndexBar({
    super.key,
    this.letters = _kLatinCanon,
    required this.presentLetters,
    required this.onLetterSelected,
    this.initialLetter,
    this.scrollUpLabel = 'Scroll up',
    this.scrollDownLabel = 'Scroll down',
  });

  @override
  State<AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<AlphabetIndexBar> {
  String? _activeLetter;
  int _windowStart = 0;
  bool _windowInitialised = false;

  @override
  void didUpdateWidget(AlphabetIndexBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLetter != widget.initialLetter ||
        oldWidget.presentLetters != widget.presentLetters) {
      _windowInitialised = false;
    }
  }

  // Compute the first visible index so that initialLetter (or the first
  // present letter) is centred in the window. Called once we have a real
  // windowSize from LayoutBuilder.
  int _initialWindowStart(int windowSize) {
    final anchor = widget.initialLetter ??
        widget.letters.firstWhere(
          (l) => widget.presentLetters.contains(l),
          orElse: () => widget.letters.first,
        );
    final anchorIndex = widget.letters.indexOf(anchor);
    final half = windowSize ~/ 2;
    final maxStart =
        (widget.letters.length - windowSize).clamp(0, widget.letters.length - 1);
    return (anchorIndex - half).clamp(0, maxStart);
  }

  // How many letter slots fit in windowed mode given availableHeight.
  // Reserves space for 2 chevrons and 2 ellipsis slots (worst case); the
  // ellipsis slots are only shown when needed but we reserve space for both
  // unconditionally so the layout height is stable regardless of window position.
  int _windowSize(double availableHeight) {
    final forLetters =
        availableHeight - 2 * _kChevronHeight - 2 * _kMinSlotHeight;
    return (forLetters / _kMinSlotHeight).floor().clamp(1, widget.letters.length);
  }

  List<String> _windowedLetters(int size) {
    final end = (_windowStart + size).clamp(0, widget.letters.length);
    return widget.letters.sublist(_windowStart, end);
  }

  void _shiftWindow(bool down, int windowSize) {
    final step = (windowSize ~/ 2).clamp(1, windowSize);
    final maxStart =
        (widget.letters.length - windowSize).clamp(0, widget.letters.length - 1);
    setState(() {
      _windowStart = down
          ? (_windowStart + step).clamp(0, maxStart)
          : (_windowStart - step).clamp(0, maxStart);
    });
  }

  bool get _canScrollUp => _windowStart > 0;
  bool _canScrollDown(int windowSize) =>
      _windowStart + windowSize < widget.letters.length;

  void _handleLetterTap(String letter) {
    if (!widget.presentLetters.contains(letter)) return;
    if (letter != _activeLetter) {
      setState(() => _activeLetter = letter);
      widget.onLetterSelected(letter);
    }
  }

  Widget _letterSlot(String letter, Color primary, double slotHeight,
      {required int winSize}) {
    final isActive = letter == _activeLetter;
    final isPresent = widget.presentLetters.contains(letter);
    final circleSize = (slotHeight * 0.85).clamp(20.0, 36.0);
    final slot = SizedBox(
      height: slotHeight,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleLetterTap(letter),
          onTapUp: (_) => setState(() => _activeLetter = null),
          onVerticalDragUpdate: (details) =>
              _onDragUpdate(details, winSize, slotHeight),
          onVerticalDragEnd: (_) {
            _dragAccumulator = 0.0;
            setState(() => _activeLetter = null);
          },
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: isActive
                ? BoxDecoration(color: primary, shape: BoxShape.circle)
                : null,
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimary
                      : isPresent
                          ? primary
                          : primary.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Absent letters are skipped by screen readers; present ones announce as a
    // button labelled with the letter (the visual glyph is excluded so it is
    // not read twice).
    if (!isPresent) return ExcludeSemantics(child: slot);
    return Semantics(
      button: true,
      label: letter,
      excludeSemantics: true,
      child: slot,
    );
  }

  Widget _chevron({
    required bool up,
    required bool enabled,
    required String label,
    required VoidCallback onTap,
  }) {
    final icon = up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down;
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
      height: _kChevronHeight,
      child: Center(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: enabled ? primary : primary.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _ellipsis(Color primary, double slotHeight) => SizedBox(
        height: slotHeight,
        child: Center(
          child: Text(
            '…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: primary.withValues(alpha: 0.4),
            ),
          ),
        ),
      );

  double _dragAccumulator = 0.0;

  void _handleDragOver(String letter) {
    if (!widget.presentLetters.contains(letter)) return;
    if (letter == _activeLetter) return;
    setState(() => _activeLetter = letter);
    widget.onLetterSelected(letter);
  }

  void _shiftWindowAndNotify(bool down, int windowSize) {
    _shiftWindow(down, windowSize);
    final visible = _windowedLetters(windowSize);
    final first = visible.firstWhere(
      (l) => widget.presentLetters.contains(l),
      orElse: () => '',
    );
    if (first.isNotEmpty) _handleDragOver(first);
  }

  void _onDragUpdate(DragUpdateDetails details, int winSize, double slotHeight) {
    _dragAccumulator += details.delta.dy;
    if (_dragAccumulator.abs() >= slotHeight) {
      final steps = (_dragAccumulator / slotHeight).truncate();
      _dragAccumulator -= steps * slotHeight;
      // Dragging down (positive dy) shifts window down toward Z.
      _shiftWindowAndNotify(steps > 0, winSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight = constraints.maxHeight;

      // ── Full mode ──────────────────────────────────────────────────────────
      // Enough room to show every slot: distribute available height evenly
      // across all of them so children exactly fill the box — no overflow.
      final fullModeThreshold = widget.letters.length * _kMinSlotHeight;
      if (availableHeight >= fullModeThreshold) {
        final slotHeight = availableHeight / widget.letters.length;
        return Column(
          mainAxisSize: MainAxisSize.max,
          children: widget.letters
              .map((l) => _letterSlot(l, primary, slotHeight,
                  winSize: widget.letters.length))
              .toList(),
        );
      }

      // ── Windowed mode ──────────────────────────────────────────────────────
      final winSize = _windowSize(availableHeight);

      // Initialise window position once we have a real winSize from layout.
      if (!_windowInitialised) {
        _windowStart = _initialWindowStart(winSize);
        _windowInitialised = true;
      }

      // Clamp in case availableHeight shrank (e.g. rotation).
      final maxStart =
          (widget.letters.length - winSize).clamp(0, widget.letters.length - 1);
      if (_windowStart > maxStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _windowStart = maxStart);
        });
      }

      final visible = _windowedLetters(winSize);
      final showEllipsisTop = _canScrollUp;
      final showEllipsisBottom = _canScrollDown(winSize);

      // Always reserve space for 2 ellipsis slots so layout height is stable.
      // When an ellipsis is absent its space is absorbed by a spacer below.
      final forSlots =
          availableHeight - 2 * _kChevronHeight - 2 * _kMinSlotHeight;
      final slotHeight =
          winSize > 0 ? (forSlots / winSize).clamp(_kMinSlotHeight, 48.0) : _kMinSlotHeight;
      const ellipsisHeight = _kMinSlotHeight;
      // Spacer fills the gap when an ellipsis is absent, keeping total height stable.
      final topSpacer = showEllipsisTop ? null : const SizedBox(height: _kMinSlotHeight);
      final bottomSpacer = showEllipsisBottom ? null : const SizedBox(height: _kMinSlotHeight);

      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          _chevron(
            up: true,
            enabled: _canScrollUp,
            label: widget.scrollUpLabel,
            onTap: () => _shiftWindowAndNotify(false, winSize),
          ),
          if (showEllipsisTop)
            _ellipsis(primary, ellipsisHeight)
          else
            topSpacer!,
          ...visible.map((l) =>
              _letterSlot(l, primary, slotHeight, winSize: winSize)),
          if (showEllipsisBottom)
            _ellipsis(primary, ellipsisHeight)
          else
            bottomSpacer!,
          _chevron(
            up: false,
            enabled: _canScrollDown(winSize),
            label: widget.scrollDownLabel,
            onTap: () => _shiftWindowAndNotify(true, winSize),
          ),
        ],
      );
    });
  }
}
