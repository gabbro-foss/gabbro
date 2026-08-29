import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';

// A dialog's buttons live in a fixed strip that never scrolls, and its message
// shrinks to whatever is left over. Measured on a 360dp phone at the 2x device
// ceiling: the message is silently cut short - the user cannot read the whole
// question. showGabbroDialog puts the whole dialog in a scroll view to fix
// that, and must leave normal text exactly as it was.

const _body = 'This cannot be undone. The vault file and every entry inside it '
    'will be removed from this device permanently.';

Future<void> _pump(
  WidgetTester tester, {
  required double scale,
  required Widget dialog,
  bool viaHelper = true,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => viaHelper
            ? showGabbroDialog<void>(context: ctx, builder: (_) => dialog)
            : showDialog<void>(context: ctx, builder: (_) => dialog),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Widget _confirm() => AlertDialog(
      title: const Text('Delete vault?'),
      content: const Text(_body),
      actions: [
        TextButton(onPressed: () {}, child: const Text('Cancel')),
        TextButton(onPressed: () {}, child: const Text('Delete')),
      ],
    );

void main() {
  // Net: at normal text nothing moves. The wrapper only earns its place if a
  // user at 1x cannot tell it is there.
  testWidgets('1x text: laid out exactly as an unwrapped dialog',
      (tester) async {
    await _pump(tester, scale: 1.0, dialog: _confirm(), viaHelper: false);
    final stockButton = tester.getRect(find.text('Delete'));
    final stockBody = tester.getRect(find.text(_body));

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, scale: 1.0, dialog: _confirm());

    expect(tester.getRect(find.text('Delete')), stockButton);
    expect(tester.getRect(find.text(_body)), stockBody);
  });

  for (final scale in <double>[kPhoneMaxScale]) {
    testWidgets('${scale}x text: the question is readable in full',
        (tester) async {
      await _pump(tester, scale: scale, dialog: _confirm());
      expect(tester.takeException(), isNull);
      // Cut short, the message renders shorter than its own text needs.
      expect(
        tester.getRect(find.text(_body)).height,
        greaterThan(200 * scale),
        reason: 'the message is being truncated to fit the leftover space',
      );
    });

    testWidgets('${scale}x text: both answers can be reached', (tester) async {
      await _pump(tester, scale: scale, dialog: _confirm());
      for (final label in ['Cancel', 'Delete']) {
        await tester.dragUntilVisible(
          find.text(label),
          find.byType(Scrollable).last,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        final r = tester.getRect(find.text(label));
        expect(r.top, lessThan(800));
        expect(r.bottom, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
    });
  }

  // A dialog that already scrolls its own content must not end up with an
  // unbounded height and blow up.
  testWidgets('a dialog with scrollable: true still lays out', (tester) async {
    await _pump(
      tester,
      scale: kPhoneMaxScale,
      dialog: AlertDialog(
        scrollable: true,
        title: const Text('Delete vault?'),
        content: const Text(_body),
        actions: [TextButton(onPressed: () {}, child: const Text('Delete'))],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // Same for one holding a list.
  testWidgets('a dialog holding a list still lays out', (tester) async {
    await _pump(
      tester,
      scale: kPhoneMaxScale,
      dialog: AlertDialog(
        title: const Text('Pick one'),
        content: SizedBox(
          width: 200,
          height: 300,
          child: ListView(
            children: const [Text('one'), Text('two'), Text('three')],
          ),
        ),
        actions: [TextButton(onPressed: () {}, child: const Text('Delete'))],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // The wrapper covers the whole screen, so the barrier behind it must still
  // get the tap: a user who taps beside a dialog expects it to go away.
  testWidgets('tapping outside still dismisses it', (tester) async {
    await _pump(tester, scale: 1.0, dialog: _confirm());
    expect(find.text('Delete vault?'), findsOneWidget);

    await tester.tapAt(const Offset(180, 30));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsNothing);
  });

  testWidgets('barrierDismissible: false still ignores an outside tap',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showGabbroDialog<void>(
            context: ctx,
            barrierDismissible: false,
            builder: (_) => _confirm(),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(180, 30));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsOneWidget);
  });

  testWidgets('the dialog still returns what it pops', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showGabbroDialog<String>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dctx).pop('chosen'),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, 'chosen');
  });

  // The fix is only worth anything if nothing bypasses it.
  test('no screen calls showDialog directly', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('widgets/gabbro_dialog.dart')) continue;
      final src = f.readAsStringSync();
      for (final line in src.split('\n')) {
        if (line.contains('showDialog<') || line.contains('showDialog(')) {
          offenders.add('${f.path}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these bypass the scroll wrapper and lose their buttons at large '
          'text — use showGabbroDialog',
    );
  });
}
