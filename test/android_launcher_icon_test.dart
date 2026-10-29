import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Android adaptive launcher icon: the launcher crops it to its own shape
/// but must not pick the colours. Black background, green mark, no
/// monochrome layer (a themed-icon launcher would recolour it).

const _res = 'android/app/src/main/res';

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  final adaptive = File('$_res/mipmap-anydpi-v26/ic_launcher.xml');

  test('adaptive icon exists for Android 8+', () {
    expect(adaptive.existsSync(), isTrue);
  });

  test('background is the fixed black colour', () {
    final xml = adaptive.readAsStringSync();
    expect(
      xml,
      contains('<background android:drawable="@color/ic_launcher_background"'),
    );
    final colors =
        File('$_res/values/ic_launcher_background.xml').readAsStringSync();
    expect(
      colors,
      contains('<color name="ic_launcher_background">#FF000000</color>'),
    );
  });

  test('foreground is the padded mark, no separate inset', () {
    // A dp inset shrank the mark to ~30% of the tile on the S23 (the
    // launcher rasterises small, where a fixed 18dp eats most of the
    // layer). The padding lives in the PNG instead, so it scales.
    final xml = adaptive.readAsStringSync();
    expect(
      xml,
      contains('<foreground android:drawable="@mipmap/ic_launcher_foreground"'),
    );
    expect(xml, isNot(contains('inset')));
  });

  test('no monochrome layer: a themed-icon launcher must not recolour it', () {
    expect(adaptive.readAsStringSync(), isNot(contains('monochrome')));
  });

  test('foreground PNG is the full 108dp layer at every density', () {
    const px = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    px.forEach((d, size) {
      final p = '$_res/mipmap-$d/ic_launcher_foreground.png';
      expect(File(p).existsSync(), isTrue, reason: p);
      expect(_pngSize(p), (size, size), reason: p);
    });
  });

  test('legacy icon kept for Android 7 and older', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final p = '$_res/mipmap-$d/ic_launcher.png';
      expect(File(p).existsSync(), isTrue, reason: p);
    }
  });
}
