import 'package:flutter/material.dart';
import 'package:gabbro/text_scale.dart';

/// Continuous text-size control for the large-text accessibility initiative
/// (ADR-016). Reused on the appearance screen and in onboarding.
///
/// Controlled widget: the caller owns [scale] and [deviceMax]. The slider runs
/// on an exponential position->scale map (see text_scale.dart), bracketed by
/// language-neutral zoom glyphs (no letters, so no "foreign A" for non-Latin
/// scripts, and no localized words). [onChanged] fires
/// live during a drag (drive a live preview); [onChangeEnd] fires on release
/// (persist there to avoid writing settings every frame). A sample line
/// previews the candidate [scale] directly via its own textScaler.
class TextSizeSlider extends StatelessWidget {
  /// Current absolute text scale (1.0 = normal).
  final double scale;

  /// Largest scale this device can carry (from `deviceMaxScale`).
  final double deviceMax;

  /// Fired continuously as the slider moves — for live preview.
  final ValueChanged<double> onChanged;

  /// Fired once when the drag ends — the point to persist.
  final ValueChanged<double>? onChangeEnd;

  /// Localized sample text shown scaled to [scale].
  final String previewText;

  const TextSizeSlider({
    super.key,
    required this.scale,
    required this.deviceMax,
    required this.onChanged,
    required this.previewText,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the slider position in [0, 1] even if a stored value exceeds this
    // device's max (e.g. a tablet-set scale opened on a phone).
    final clamped = scale.clamp(kMinTextScale, deviceMax).toDouble();
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.zoom_out),
            Expanded(
              child: Slider(
                value: posForScale(clamped, deviceMax),
                onChanged: (pos) => onChanged(scaleForPos(pos, deviceMax)),
                onChangeEnd: onChangeEnd == null
                    ? null
                    : (pos) => onChangeEnd!(scaleForPos(pos, deviceMax)),
              ),
            ),
            const Icon(Icons.zoom_in),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            previewText,
            key: const Key('textSizePreview'),
            textScaler: TextScaler.linear(scale),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
