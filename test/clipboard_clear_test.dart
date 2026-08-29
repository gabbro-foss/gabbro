import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/settings.dart';
import 'test_helpers.dart';

// A minimal host standing in for a screen that copies a secret, so the wiper can
// be driven through a real widget lifecycle (mount, copy, tear down).
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Host()));
}

/// Tears the host down without ending the test, the way leaving a screen does.
Future<void> _disposeHost(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
}

void main() {
  group('clipboardClearDelay', () {
    test('never maps to null (no wipe scheduled)', () {
      expect(clipboardClearDelay(ClipboardClearTimeout.never), isNull);
    });
    test('finite timeouts map to their durations', () {
      expect(clipboardClearDelay(ClipboardClearTimeout.thirtySeconds),
          const Duration(seconds: 30));
      expect(clipboardClearDelay(ClipboardClearTimeout.sixtySeconds),
          const Duration(seconds: 60));
      expect(clipboardClearDelay(ClipboardClearTimeout.twoMinutes),
          const Duration(minutes: 2));
    });
  });

  group('clipboardWiper', () {
    tearDown(clipboardWiper.cancelPending);

    testWidgets('copyThenClear writes the value, then wipes after the delay',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'secret', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      expect(writes, ['secret'], reason: 'the value is written, not yet wiped');
      await tester.pump(const Duration(seconds: 30));
      expect(writes, ['secret', ''], reason: 'wiped once the delay elapses');
    });

    testWidgets('never schedules no wipe', (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'secret', ClipboardClearTimeout.never);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(writes, ['secret'], reason: 'never must not wipe the clipboard');
    });

    testWidgets('a second copy cancels the first pending wipe', (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'first', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await clipboardWiper.copyThenClear(
          'second', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      // 35s after the first copy (its wipe would have fired at 30s) but only
      // 20s after the second: nothing wiped yet.
      await tester.pump(const Duration(seconds: 20));
      expect(writes, ['first', 'second'],
          reason: 'first wipe cancelled, second not yet due');
      await tester.pump(const Duration(seconds: 10)); // 30s after the second
      expect(writes, ['first', 'second', ''],
          reason: 'the reset wipe fires once its own delay elapses');
    });

    // RT-4: a wipe that dies with its screen leaves a copied password on the
    // clipboard for good.
    testWidgets('the wipe still fires after the copying screen is gone',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'secret', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      await _disposeHost(tester);

      await tester.pump(const Duration(seconds: 30));
      expect(writes, ['secret', ''],
          reason: 'leaving the screen must not cancel the wipe the user chose');
    });

    testWidgets('a copy from a second screen governs the pending wipe',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'first', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      await _disposeHost(tester);
      await tester.pump(const Duration(seconds: 15));

      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'second', ClipboardClearTimeout.thirtySeconds);
      await tester.pump(const Duration(seconds: 20));
      expect(writes, ['first', 'second'],
          reason: 'one pending wipe across screens, not two');
      await tester.pump(const Duration(seconds: 10));
      expect(writes, ['first', 'second', '']);
    });

    // Auto-lock means the user walked away, so the clipboard goes with the
    // session. Manual lock does not call this (they are present, and may be
    // about to paste) - pinned in lock_timer_test.dart.
    testWidgets('wipeNow wipes a pending clipboard immediately',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'secret', ClipboardClearTimeout.twoMinutes);
      await tester.pump();

      clipboardWiper.wipeNow();
      await tester.pump();
      expect(writes, ['secret', ''], reason: 'auto-lock takes the clipboard too');

      await tester.pump(const Duration(minutes: 2));
      expect(writes, ['secret', ''],
          reason: 'the original timer must not fire a second wipe');
    });

    testWidgets('wipeNow writes nothing when the user chose never',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);
      await clipboardWiper.copyThenClear(
          'secret', ClipboardClearTimeout.never);
      await tester.pump();

      clipboardWiper.wipeNow();
      await tester.pump();
      expect(writes, ['secret'],
          reason: 'never means never, auto-lock included');
    });

    testWidgets('wipeNow is a no-op when nothing was copied', (tester) async {
      final writes = recordClipboardWrites(tester);
      await _pumpHost(tester);

      clipboardWiper.wipeNow();
      await tester.pump();
      expect(writes, isEmpty,
          reason: 'locking must not clear a clipboard Gabbro never wrote');
    });
  });
}
