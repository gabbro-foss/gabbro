import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';

void main() {
  testWidgets('skipped-entries dialog does not overflow at large text',
      (tester) async {
    // Phone surface (360dp) at 4x text — the worst case for the old fixed
    // height:300 box (ADR-016 Phase 2).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final skipped = List.generate(
      8,
      (i) => SkippedEntryData(
        title: 'A rather long skipped entry title number $i that wraps at 4x',
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
              .copyWith(textScaler: const TextScaler.linear(4.0)),
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
}
