import 'package:flutter/material.dart';

const _kAllLetters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
];

class AlphabetIndexBar extends StatefulWidget {
  final Set<String> presentLetters;
  final void Function(String letter) onLetterSelected;

  const AlphabetIndexBar({
    super.key,
    required this.presentLetters,
    required this.onLetterSelected,
  });

  @override
  State<AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<AlphabetIndexBar> {
  String? _activeLetter;

  // Returns a window of letters centred on _activeLetter that fits the
  // available height. Each letter slot is sized to fill available space
  // evenly — no fixed pixel height, so font size governs readability.
  List<String> _visibleLetters(double availableHeight, double itemHeight) {
    final maxVisible = (availableHeight / itemHeight).floor();
    if (maxVisible >= _kAllLetters.length) return _kAllLetters;

    final activeIndex = _activeLetter != null
        ? _kAllLetters.indexOf(_activeLetter!)
        : _kAllLetters.length ~/ 2;

    final half = maxVisible ~/ 2;
    final start =
        (activeIndex - half).clamp(0, _kAllLetters.length - maxVisible);
    return _kAllLetters.sublist(start, start + maxVisible);
  }

  void _handleGesture(Offset localPosition, List<String> visible,
      double itemHeight) {
    final index =
        (localPosition.dy / itemHeight).floor().clamp(0, visible.length - 1);
    final letter = visible[index];
    // Dimmed letters do nothing.
    if (!widget.presentLetters.contains(letter)) return;
    if (letter != _activeLetter) {
      setState(() => _activeLetter = letter);
      widget.onLetterSelected(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(builder: (context, constraints) {
      // Use a minimum item height that keeps letters readable, then
      // distribute evenly across available space if there's more room.
      const minItemHeight = 18.0;
      final naturalHeight = _kAllLetters.length * minItemHeight;
      final itemHeight = constraints.maxHeight >= naturalHeight
          ? constraints.maxHeight / _kAllLetters.length
          : minItemHeight;

      final visible = _visibleLetters(constraints.maxHeight, itemHeight);
      final totalHeight = visible.length * itemHeight;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _handleGesture(d.localPosition, visible, itemHeight),
        onTapUp: (_) => setState(() => _activeLetter = null),
        onVerticalDragUpdate: (d) {
          // Update _activeLetter for ALL letters during drag (including dimmed)
          // so the window follows the finger, but only scroll for present ones.
          final index = (d.localPosition.dy / itemHeight)
              .floor()
              .clamp(0, visible.length - 1);
          final letter = visible[index];
          if (letter != _activeLetter) {
            setState(() => _activeLetter = letter);
          }
          _handleGesture(d.localPosition, visible, itemHeight);
        },
        onVerticalDragEnd: (_) => setState(() => _activeLetter = null),
        child: SizedBox(
          width: double.infinity,
          height: totalHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: visible.map((letter) {
              final isActive = letter == _activeLetter;
              final isPresent = widget.presentLetters.contains(letter);
              return SizedBox(
                height: itemHeight,
                child: Center(
                  child: Container(
                    width: itemHeight,
                    height: itemHeight,
                    decoration: isActive
                        ? BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 12,
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
              );
            }).toList(),
          ),
        ),
      );
    });
  }
}
