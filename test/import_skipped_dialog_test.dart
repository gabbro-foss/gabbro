import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/text_scale.dart';

void main() {
  testWidgets('skipped-entries dialog does not overflow at large text',
      (tester) async {
    // Phone surface (360dp) at the 2x device ceiling — the worst case for the
    // old fixed height:300 box (ADR-016 Phase 2).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final skipped = List.generate(
      8,
      (i) => SkippedEntryData(
        title: 'A rather long skipped entry title number $i that wraps at 2x',
        reason: 'Skipped because its UUID already exists in the target vault',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Apply the scale above the root navigator so the dialog inherits it.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(kPhoneMaxScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showSkippedEntriesDialog(context, skipped),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('each skipped row exposes its title and reason to a screen reader',
      (tester) async {
    // Linux reads only the semantic label, so the reason must be part of a
    // label — not a hint, and not a decoration a reader skips. Without this a
    // blind user hears the entry name and never learns why it was skipped.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showSkippedEntriesDialog(context, [
                  SkippedEntryData(
                    title: 'Dupe Entry',
                    reason: 'UUID already exists',
                  ),
                ]),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Dupe Entry'),
      findsOneWidget,
      reason: 'the skipped entry title must be readable',
    );
    expect(
      find.bySemanticsLabel('UUID already exists'),
      findsOneWidget,
      reason: 'the reason must reach the reader as a label',
    );

    handle.dispose();
  });
}
