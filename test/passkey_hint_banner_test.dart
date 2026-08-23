import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/widgets/passkey_hint_banner.dart';

// The vault-list hint shown when the Linux passkey daemon could not start:
// without it passkeys fail silently and the user never learns the one-time
// fix. Each reason names its own cause so the README steps the user reaches
// for are the right ones; X hides it for the session, "Don't show again"
// hides it forever (persisted by the caller).

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('missing module names the uhid module and points at the README',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PasskeyHintBanner(
          reason: PasskeyFailureReason.moduleMissing,
          onDismiss: () {},
          onDismissForever: () {},
        ),
      ),
    );
    expect(find.textContaining('uhid'), findsOneWidget);
    expect(find.textContaining('README'), findsOneWidget);
  });

  testWidgets('missing access names the udev rule', (tester) async {
    await tester.pumpWidget(
      _host(
        PasskeyHintBanner(
          reason: PasskeyFailureReason.noAccess,
          onDismiss: () {},
          onDismissForever: () {},
        ),
      ),
    );
    expect(find.textContaining('udev'), findsOneWidget);
    expect(find.textContaining('README'), findsOneWidget);
  });

  testWidgets('the X dismisses for the session only', (tester) async {
    var dismissed = false;
    var forever = false;
    await tester.pumpWidget(
      _host(
        PasskeyHintBanner(
          reason: PasskeyFailureReason.other,
          onDismiss: () => dismissed = true,
          onDismissForever: () => forever = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, isTrue);
    expect(forever, isFalse);
  });

  testWidgets('banner controls are labelled and meet tap targets',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        PasskeyHintBanner(
          reason: PasskeyFailureReason.moduleMissing,
          onDismiss: () {},
          onDismissForever: () {},
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('"Don\'t show again" dismisses forever', (tester) async {
    var dismissed = false;
    var forever = false;
    await tester.pumpWidget(
      _host(
        PasskeyHintBanner(
          reason: PasskeyFailureReason.other,
          onDismiss: () => dismissed = true,
          onDismissForever: () => forever = true,
        ),
      ),
    );
    await tester.tap(find.text("Don't show again"));
    expect(forever, isTrue);
    expect(dismissed, isFalse);
  });
}
