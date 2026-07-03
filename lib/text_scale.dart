import 'dart:math' as math;

/// Pure text- and target-scaling helpers for the large-text accessibility
/// initiative (ADR-016). No Flutter / MediaQuery dependency: callers pass the
/// screen's shortest side in logical pixels (dp) so every function is a plain,
/// unit-testable mapping.

/// Lowest selectable text scale (also the storage floor in [AppSettings]).
const double kMinTextScale = 0.8;

/// Device-tier maximum text scales. Phones have less screen room than tablets,
/// so they cap lower. Reused 600dp breakpoint (same as the two-pane layout).
/// Calibrated on hardware (S23 / GrapheneOS / Idea Tab Pro, 2026-07-03): the
/// original 6x/8x left too little content on screen at the far end.
const double kPhoneMaxScale = 4.0;
const double kTabletMaxScale = 6.0;
const double kTabletBreakpointDp = 600.0;

/// Controls/targets grow to at most this multiple at the device's max text
/// scale — big enough to hit, never large enough to consume the screen.
const double kMaxTargetScale = 2.0;

/// The largest text scale this device can carry, from its shortest side (dp).
double deviceMaxScale(double shortestDp) =>
    shortestDp >= kTabletBreakpointDp ? kTabletMaxScale : kPhoneMaxScale;

/// Slider position [0, 1] -> text scale, on an exponential slope so the
/// everyday range (~0.8-2.0) occupies most of the track and it accelerates
/// toward [deviceMax]. Inverse of [posForScale].
double scaleForPos(double pos, double deviceMax) =>
    kMinTextScale * math.pow(deviceMax / kMinTextScale, pos).toDouble();

/// Text scale -> slider position [0, 1]. Exact inverse of [scaleForPos].
double posForScale(double scale, double deviceMax) =>
    math.log(scale / kMinTextScale) / math.log(deviceMax / kMinTextScale);

/// Control/target size multiplier for a given text scale: lerp 1.0 -> 2.0
/// across the device's text range, clamped. Targets grow, never shrink — a
/// below-normal text scale still yields 1.0.
double targetScaleFor(double textScale, double deviceMax) {
  final t = ((textScale - 1.0) / (deviceMax - 1.0)).clamp(0.0, 1.0);
  return 1.0 + (kMaxTargetScale - 1.0) * t;
}

/// Clamp a stored scale to what the current device can carry: never above the
/// device max (so a tablet-set value can't break a phone), never below the
/// minimum.
double clampToDevice(double stored, double shortestDp) =>
    stored.clamp(kMinTextScale, deviceMaxScale(shortestDp)).toDouble();
