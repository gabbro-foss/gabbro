import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/text_size_slider.dart';

void main() {
  Widget host(TextSizeSlider slider) =>
      MaterialApp(home: Scaffold(body: slider));

  TextSizeSlider make({
    double scale = 1.0,
    double deviceMax = 6.0,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) =>
      TextSizeSlider(
        scale: scale,
        deviceMax: deviceMax,
        onChanged: onChanged ?? (_) {},
        onChangeEnd: onChangeEnd,
        previewText: 'Sample',
      );

  // ── D1 end glyphs ──────────────────────────────────────────────────────────

  testWidgets('D1 renders letter-free zoom glyphs', (tester) async {
    await tester.pumpWidget(host(make()));
    expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
  });

  // ── D2 position reflects scale ─────────────────────────────────────────────

  testWidgets('D2 slider value is posForScale of the current scale', (tester) async {
    for (final scale in [0.8, 1.0, 2.0, 6.0]) {
      await tester.pumpWidget(host(make(scale: scale, deviceMax: 6.0)));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, closeTo(posForScale(scale, 6.0), 1e-9),
          reason: 'scale=$scale');
    }
  });

  // ── D3 onChanged mapping ───────────────────────────────────────────────────

  testWidgets('D3 dragging invokes onChanged with scaleForPos', (tester) async {
    double? got;
    await tester.pumpWidget(host(make(deviceMax: 6.0, onChanged: (s) => got = s)));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
    expect(got, closeTo(scaleForPos(0.5, 6.0), 1e-9));
  });

  // ── D4 onChangeEnd mapping ─────────────────────────────────────────────────

  testWidgets('D4 release invokes onChangeEnd with scaleForPos', (tester) async {
    double? committed;
    await tester.pumpWidget(
      host(make(deviceMax: 6.0, onChangeEnd: (s) => committed = s)),
    );
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1.0);
    expect(committed, closeTo(scaleForPos(1.0, 6.0), 1e-9));
  });

  // ── D5 preview scales ──────────────────────────────────────────────────────

  testWidgets('D5 preview text scales with the current scale', (tester) async {
    await tester.pumpWidget(host(make(scale: 2.5)));
    final preview = tester.widget<Text>(find.byKey(const Key('textSizePreview')));
    expect(preview.textScaler, const TextScaler.linear(2.5));
  });

  // ── D6 above-device-max seeds at 1.0 ───────────────────────────────────────

  testWidgets('D6 stored value above device max seeds slider at 1.0', (tester) async {
    await tester.pumpWidget(host(make(scale: 8.0, deviceMax: 6.0)));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(1.0, 1e-9));
  });
}
