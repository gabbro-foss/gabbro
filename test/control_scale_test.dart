import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/control_scale.dart';

// ADR-016 Phase 3: controlScaleFor reads the current text scale + device tier
// from MediaQuery and returns the control/target multiplier (1.0..2.0), so
// controls grow with text. It is the context-aware wrapper over the pure
// targetScaleFor/deviceMaxScale (which text_scale.dart keeps Flutter-free).

// shortestSide 360 -> phone tier (max 2.0x); 866 -> tablet tier (max 3.0x).
const _phone = Size(360, 800);
const _tablet = Size(866, 1200);

Future<double> _scaleAt(
  WidgetTester tester, {
  required double textScale,
  required Size size,
}) async {
  late double result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        size: size,
      ),
      child: Builder(
        builder: (context) {
          result = controlScaleFor(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('normal text scale yields 1.0 (no growth) on both tiers',
      (tester) async {
    expect(await _scaleAt(tester, textScale: 1.0, size: _phone),
        closeTo(1.0, 1e-9));
    expect(await _scaleAt(tester, textScale: 1.0, size: _tablet),
        closeTo(1.0, 1e-9));
  });

  testWidgets('below-normal text still floors the control scale at 1.0',
      (tester) async {
    expect(await _scaleAt(tester, textScale: 0.8, size: _phone),
        closeTo(1.0, 1e-9));
  });

  testWidgets('phone at its max (2.0x) hits the 2.0 target cap', (tester) async {
    expect(await _scaleAt(tester, textScale: 2.0, size: _phone),
        closeTo(2.0, 1e-9));
  });

  testWidgets('tablet tracks targetScaleFor between 1.0 and the cap',
      (tester) async {
    // targetScaleFor(2.0, 3.0) = 1.5
    expect(await _scaleAt(tester, textScale: 2.0, size: _tablet),
        closeTo(1.5, 1e-9));
    // at the tablet max (3.0x) -> 2.0 cap
    expect(await _scaleAt(tester, textScale: 3.0, size: _tablet),
        closeTo(2.0, 1e-9));
  });

  // ── scaledIconSize (Slice B) ───────────────────────────────────────────────

  group('scaledIconSize', () {
    Future<double> sizeAt(
      WidgetTester tester, {
      required double textScale,
      required Size size,
      double? base,
    }) async {
      late double result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: size,
          ),
          child: Builder(
            builder: (context) {
              result = base == null
                  ? scaledIconSize(context)
                  : scaledIconSize(context, base);
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('defaults to 24 at normal text', (tester) async {
      expect(await sizeAt(tester, textScale: 1.0, size: _phone),
          closeTo(24.0, 1e-9));
    });

    testWidgets('doubles to the cap at the device max', (tester) async {
      expect(await sizeAt(tester, textScale: 2.0, size: _phone),
          closeTo(48.0, 1e-9));
    });

    testWidgets('scales a custom base by the control factor', (tester) async {
      // tablet @2.0x -> factor 1.5, so base 20 -> 30
      expect(await sizeAt(tester, textScale: 2.0, size: _tablet, base: 20),
          closeTo(30.0, 1e-9));
    });
  });

  // ── scaledSuffixIconSize (reveal-eye toggles in bounded field boxes) ────────
  // Grows gently and is capped at 1.4x so a scaled eye can't clip / balloon a
  // TextField's suffix box (ADR-016; same gentle-cap idea as the selection
  // checkbox).
  group('scaledSuffixIconSize', () {
    Future<double> suffixAt(
      WidgetTester tester, {
      required double textScale,
      required Size size,
      double? base,
    }) async {
      late double result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: size,
          ),
          child: Builder(
            builder: (context) {
              result = base == null
                  ? scaledSuffixIconSize(context)
                  : scaledSuffixIconSize(context, base);
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('defaults to 24 at normal text', (tester) async {
      expect(await suffixAt(tester, textScale: 1.0, size: _phone),
          closeTo(24.0, 1e-9));
    });

    testWidgets('tracks the control factor while below the cap', (tester) async {
      // phone @1.2x -> factor 1.2 (< 1.4 cap), so 24 -> 28.8
      expect(await suffixAt(tester, textScale: 1.2, size: _phone),
          closeTo(28.8, 1e-9));
    });

    testWidgets('caps at 1.4x on a phone at max text', (tester) async {
      // phone @2.0x -> factor 2.0, clamped to 1.4, so 24 -> 33.6
      expect(await suffixAt(tester, textScale: 2.0, size: _phone),
          closeTo(33.6, 1e-9));
    });

    testWidgets('caps at 1.4x on a tablet at large text', (tester) async {
      // tablet @2.0x -> factor 1.5, clamped to 1.4, so 24 -> 33.6
      expect(await suffixAt(tester, textScale: 2.0, size: _tablet),
          closeTo(33.6, 1e-9));
    });

    testWidgets('applies the cap to a custom base', (tester) async {
      // phone @1.2x -> factor 1.2, base 18 -> 21.6
      expect(await suffixAt(tester, textScale: 1.2, size: _phone, base: 18),
          closeTo(21.6, 1e-9));
    });
  });
}
