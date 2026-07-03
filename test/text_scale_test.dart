import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/text_scale.dart';

void main() {
  // ── deviceMaxScale (B1) ────────────────────────────────────────────────────

  group('deviceMaxScale', () {
    test('phone tier (<600dp) maxes at 4.0', () {
      expect(deviceMaxScale(360), 4.0);
      expect(deviceMaxScale(411), 4.0);
      expect(deviceMaxScale(599.9), 4.0);
    });

    test('tablet tier (>=600dp) maxes at 6.0', () {
      expect(deviceMaxScale(600), 6.0);
      expect(deviceMaxScale(866), 6.0);
    });
  });

  // ── scaleForPos (B2) ───────────────────────────────────────────────────────

  group('scaleForPos', () {
    test('pos 0 is the minimum scale 0.8', () {
      expect(scaleForPos(0.0, 6.0), closeTo(0.8, 1e-9));
      expect(scaleForPos(0.0, 8.0), closeTo(0.8, 1e-9));
    });

    test('pos 1 is the device max', () {
      expect(scaleForPos(1.0, 6.0), closeTo(6.0, 1e-9));
      expect(scaleForPos(1.0, 8.0), closeTo(8.0, 1e-9));
    });

    test('is monotonic increasing across the track', () {
      var prev = scaleForPos(0.0, 6.0);
      for (var p = 0.05; p <= 1.0; p += 0.05) {
        final s = scaleForPos(p, 6.0);
        expect(s, greaterThan(prev), reason: 'pos=$p');
        prev = s;
      }
    });

    test('pos 0.5 sits below the linear midpoint (exponential slope)', () {
      // Linear midpoint would be (0.8 + 6.0) / 2 = 3.4.
      expect(scaleForPos(0.5, 6.0), lessThan(3.4));
    });
  });

  // ── posForScale (B3) ───────────────────────────────────────────────────────

  group('posForScale', () {
    test('min scale maps to pos 0, device max to pos 1', () {
      expect(posForScale(0.8, 6.0), closeTo(0.0, 1e-9));
      expect(posForScale(6.0, 6.0), closeTo(1.0, 1e-9));
    });

    test('is the exact inverse of scaleForPos', () {
      for (final x in [0.8, 1.0, 2.0, 6.0]) {
        expect(scaleForPos(posForScale(x, 6.0), 6.0), closeTo(x, 1e-9),
            reason: 'x=$x');
      }
    });
  });

  // ── targetScaleFor (B4) ────────────────────────────────────────────────────

  group('targetScaleFor', () {
    test('normal text scale gives normal targets (1.0)', () {
      expect(targetScaleFor(1.0, 6.0), closeTo(1.0, 1e-9));
    });

    test('device-max text scale gives 2x targets', () {
      expect(targetScaleFor(6.0, 6.0), closeTo(2.0, 1e-9));
    });

    test('midpoint text scale gives 1.5x targets', () {
      expect(targetScaleFor(3.5, 6.0), closeTo(1.5, 1e-9));
    });

    test('below-normal text scale never shrinks targets', () {
      expect(targetScaleFor(0.8, 6.0), closeTo(1.0, 1e-9));
    });

    test('above device-max clamps at 2x', () {
      expect(targetScaleFor(9.0, 6.0), closeTo(2.0, 1e-9));
    });
  });

  // ── clampToDevice (B5) ─────────────────────────────────────────────────────

  group('clampToDevice', () {
    test('caps a tablet-set value on a phone', () {
      expect(clampToDevice(8.0, 411), 4.0);
    });

    test('leaves an in-range value untouched', () {
      expect(clampToDevice(2.0, 411), 2.0);
      expect(clampToDevice(1.0, 360), 1.0);
    });

    test('caps at the tablet max on a tablet', () {
      expect(clampToDevice(8.0, 866), 6.0);
    });

    test('floors at the minimum 0.8', () {
      expect(clampToDevice(0.5, 360), 0.8);
    });
  });
}
