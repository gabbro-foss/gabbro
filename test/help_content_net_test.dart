// Net for the help carousel content: every card the screen lists is on disk,
// captions and cards are in step, and the dot row shows one dot per card.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/help_screen.dart';

import 'test_helpers.dart';

List<String> _lines(RegExp re) => File('lib/screens/help_screen.dart')
    .readAsLinesSync()
    .where(re.hasMatch)
    .toList();

void main() {
  test('every listed card is on disk, one caption per card', () {
    final assets = _lines(RegExp(r"^\s*'assets/help/help_\d{3}_.*\.png',$"))
        .map((l) => l.trim().replaceAll(RegExp(r"^'|',$"), ''))
        .toList();
    final captions = _lines(RegExp(r'^\s*l\.helpCaption\w+,$'));
    expect(assets, isNotEmpty);
    expect(captions.length, assets.length,
        reason: 'captions and cards out of step');
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: '$a missing');
    }
    expect(assets.toSet().length, assets.length, reason: 'duplicate card');
    expect(captions.toSet().length, captions.length,
        reason: 'a caption key used twice');
  });

  testWidgets('one dot per card', (tester) async {
    final assets = _lines(RegExp(r"^\s*'assets/help/help_\d{3}_.*\.png',$"));
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedContainer), findsNWidgets(assets.length));
  });
}
