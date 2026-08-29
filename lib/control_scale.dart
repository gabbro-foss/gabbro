import 'package:flutter/widgets.dart';
import 'package:gabbro/text_scale.dart';

/// `MediaQuery.textScaler` grows text only; controls scale off it too so a
/// low-vision user gets proportionally larger targets (ADR-016).
double controlScaleFor(BuildContext context) {
  final mq = MediaQuery.of(context);
  return targetScaleFor(
    mq.textScaler.scale(1),
    deviceMaxScale(mq.size.shortestSide),
  );
}

/// An icon/target size scaled by [controlScaleFor] - [base] (the Material
/// default 24) at normal text, up to `2 * base` at the device's max text scale.
/// Use for `IconButton.iconSize`, FAB child icons, etc. (ADR-016 Phase 3).
double scaledIconSize(BuildContext context, [double base = 24]) =>
    base * controlScaleFor(context);

/// Capped at 1.4x so the glyph cannot clip or balloon a [TextField]'s fixed
/// suffix box; use [scaledIconSize] in unconstrained rows.
double scaledSuffixIconSize(BuildContext context, [double base = 24]) =>
    base * controlScaleFor(context).clamp(1.0, 1.4);

/// Scales a 48dp control (a selection [Checkbox]) up at large text - but only
/// *gently* (capped at 1.4x, well below the full control factor) so it stays
/// visible without dominating/crowding a list row. Returns [child] unchanged at
/// normal text. Reserves the scaled footprint so it can't overlap its
/// neighbours (ADR-016 Phase 3 Slice C).
Widget scaledSelectionCheckbox(BuildContext context, Widget child) {
  final s = controlScaleFor(context).clamp(1.0, 1.4).toDouble();
  if (s <= 1.0) return child;
  return SizedBox.square(
    key: const Key('scaledSelectionCheckbox'),
    dimension: 48 * s,
    child: Center(child: Transform.scale(scale: s, child: child)),
  );
}
