import 'package:flutter/material.dart';
import 'package:gabbro/gabbro_contrast.dart';

/// Resolved look of a region's focus frame. Null means "not focused, no frame".
@immutable
class FocusFrameStyle {
  final Color color;
  final double width;
  final bool dashed;
  const FocusFrameStyle({
    required this.color,
    required this.width,
    required this.dashed,
  });

  @override
  bool operator ==(Object other) =>
      other is FocusFrameStyle &&
      other.color == color &&
      other.width == width &&
      other.dashed == dashed;

  @override
  int get hashCode => Object.hash(color, width, dashed);
}

/// The frame a focused region should draw: none when unfocused; a solid border
/// in normal modes; a dashed, thicker border in high-contrast — a non-colour cue
/// (texture) for users who need more than colour and width alone.
FocusFrameStyle? focusFrameStyle({
  required bool focused,
  required bool highContrast,
  required Color color,
}) {
  if (!focused) return null;
  return FocusFrameStyle(
    color: color,
    width: highContrast ? 3 : 2,
    dashed: highContrast,
  );
}

/// Strokes a rounded-rect border for [style] — solid, or dashed when
/// [FocusFrameStyle.dashed] is set (high-contrast).
class FocusFramePainter extends CustomPainter {
  final FocusFrameStyle style;
  final double radius;
  const FocusFramePainter(this.style, {this.radius = 8});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.width
      ..color = style.color;
    final inset = style.width / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - style.width, size.height - style.width),
      Radius.circular(radius),
    );
    if (!style.dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }
    const dash = 6.0;
    const gap = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = (d + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(FocusFramePainter old) =>
      old.style != style || old.radius != radius;
}

/// Wraps a traversal "region" (search box, a list, the chips row, the detail
/// pane) and draws a focus frame around it while any control inside it holds
/// focus. The frame is the qtile-style "which area am I in" cue; individual
/// items keep their own selection highlight. Colour is the theme primary; the
/// high-contrast variant is dashed and thicker (see [focusFrameStyle]).
class FocusRegion extends StatefulWidget {
  final Widget child;
  final double radius;
  const FocusRegion({super.key, required this.child, this.radius = 8});

  @override
  State<FocusRegion> createState() => _FocusRegionState();
}

class _FocusRegionState extends State<FocusRegion> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast =
        theme.extension<GabbroContrast>()?.highContrast ?? false;
    final style = focusFrameStyle(
      focused: _focused,
      highContrast: highContrast,
      color: theme.colorScheme.primary,
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus != _focused) setState(() => _focused = hasFocus);
      },
      child: CustomPaint(
        foregroundPainter:
            style == null ? null : FocusFramePainter(style, radius: widget.radius),
        child: widget.child,
      ),
    );
  }
}
