import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/text_size_slider.dart';

void main() {
  Widget host(TextSizeSlider slider) =>
      MaterialApp(home: Scaffold(body: slider));

  TextSizeSlider make({
    double scale = 1.0,
    double deviceMax = kTabletMaxScale,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) =>
      TextSizeSlider(
        scale: scale,
        deviceMax: deviceMax,
        onChanged: onChanged ?? (_) {},
        onChangeEnd: onChangeEnd,
        previewText: 'Sample',
        semanticLabel: 'Text size',
      );

  testWidgets('D1 renders letter-free zoom glyphs', (tester) async {
    await tester.pumpWidget(host(make()));
    expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
  });

  testWidgets('D2 slider value is posForScale of the current scale', (tester) async {
    for (final scale in [0.8, 1.0, 2.0, 3.0]) {
      await tester.pumpWidget(host(make(scale: scale, deviceMax: kTabletMaxScale)));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, closeTo(posForScale(scale, kTabletMaxScale), 1e-9),
          reason: 'scale=$scale');
    }
  });

  testWidgets('D3 dragging invokes onChanged with scaleForPos', (tester) async {
    double? got;
    await tester.pumpWidget(host(make(deviceMax: kTabletMaxScale, onChanged: (s) => got = s)));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
    expect(got, closeTo(scaleForPos(0.5, kTabletMaxScale), 1e-9));
  });

  testWidgets('D4 release invokes onChangeEnd with scaleForPos', (tester) async {
    double? committed;
    await tester.pumpWidget(
      host(make(deviceMax: kTabletMaxScale, onChangeEnd: (s) => committed = s)),
    );
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1.0);
    expect(committed, closeTo(scaleForPos(1.0, kTabletMaxScale), 1e-9));
  });

  testWidgets('D5 preview text scales with the current scale', (tester) async {
    await tester.pumpWidget(host(make(scale: 2.5)));
    final preview = tester.widget<Text>(find.byKey(const Key('textSizePreview')));
    expect(preview.textScaler, const TextScaler.linear(2.5));
  });

  testWidgets('D6 stored value above device max seeds slider at 1.0', (tester) async {
    await tester.pumpWidget(host(make(scale: 4.0, deviceMax: kTabletMaxScale)));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(1.0, 1e-9));
  });
}
