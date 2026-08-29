import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'screen_catalog.dart';
import 'package:gabbro/main.dart';

// The passkey daemon shows its consent dialog through [rootNavigatorKey]. The
// key must target the mounted GabbroApp (consent can appear) and be null once
// it is gone (consent no-ops as a cancel instead of crashing) - and it must be
// per-instance, or pumping a second GabbroApp in one test silently fails to
// build (that blinded the theme/high-contrast a11y net).

void main() {
  testWidgets('rootNavigatorKey tracks the mounted app and clears on dispose',
      (tester) async {
    expect(rootNavigatorKey, isNull, reason: 'no app is mounted yet');

    await tester.pumpWidget(appShell(const SizedBox(), textScale: 1.0));
    await tester.pumpAndSettle();
    expect(rootNavigatorKey?.currentContext, isNotNull,
        reason: 'the daemon can reach the live navigator for consent');

    await tester.pumpWidget(const SizedBox());
    expect(rootNavigatorKey, isNull,
        reason: 'consent after shutdown must no-op, not crash');
  });
}
