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
/// in normal modes; a dashed, thicker border in high-contrast - a non-colour cue
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

/// Strokes a rounded-rect border for [style] - solid, or dashed when
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

/// An [OutlineInputBorder] drawn with dashes - Flutter can't dash an input
/// border out of the box. Used for the search field's focus border in
/// high-contrast, so its own outline "lights up" dashed (matching the
/// [FocusRegion] frame) with no second line.
class DashedOutlineInputBorder extends OutlineInputBorder {
  const DashedOutlineInputBorder({
    super.borderSide,
    super.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  DashedOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => DashedOutlineInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  DashedOutlineInputBorder scale(double t) => DashedOutlineInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final paint = borderSide.toPaint();
    final rrect = borderRadius.toRRect(rect).deflate(borderSide.width / 2);
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
}

/// Draws a "which area am I in" frame around a Tab region while a control
/// inside holds focus, and names the region to a screen reader. [label] is a
/// name on a Semantics container, not a `SemanticsService` announcement: the
/// Linux embedder sends announcements as ATK "polite" and Orca discards those
/// while speaking, which it always is right after a focus change; a named
/// panel ancestor cannot be discarded. Accepted cost: Orca repeats the region
/// name on each arrow press inside the list. [showFrame] is false for the
/// search box, which lights its own outline.
class FocusRegion extends StatefulWidget {
  final Widget child;
  final double radius;
  final String? label;
  final bool showFrame;
  const FocusRegion({
    super.key,
    required this.child,
    this.radius = 8,
    this.label,
    this.showFrame = true,
  });

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
    Widget content = CustomPaint(
      foregroundPainter: style == null || !widget.showFrame
          ? null
          : FocusFramePainter(style, radius: widget.radius),
      child: widget.child,
    );
    // liveRegion only while focused, so exactly one region carries it. It is
    // inert on Linux (the embedder maps no live-region flag) and kept only for
    // the platforms that do read it; the NAME is what Orca actually speaks.
    if (widget.label != null) {
      content = Semantics(
        container: true,
        label: widget.label,
        liveRegion: _focused,
        child: content,
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus != _focused) setState(() => _focused = hasFocus);
      },
      child: content,
    );
  }
}
