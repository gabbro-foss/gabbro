import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/settings.dart';
import 'test_helpers.dart';

// A minimal host that adopts the mixin, so its behaviour can be driven directly.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with ClipboardClearMixin<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<_HostState> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Host()));
  return tester.state<_HostState>(find.byType(_Host));
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

  group('ClipboardClearMixin', () {
    testWidgets('copyThenClear writes the value, then wipes after the delay',
        (tester) async {
      final writes = recordClipboardWrites(tester);
      final state = await _pumpHost(tester);
      await state.copyThenClear('secret', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      expect(writes, ['secret'], reason: 'the value is written, not yet wiped');
      await tester.pump(const Duration(seconds: 30));
      expect(writes, ['secret', ''], reason: 'wiped once the delay elapses');
    });

    testWidgets('never schedules no wipe', (tester) async {
      final writes = recordClipboardWrites(tester);
      final state = await _pumpHost(tester);
      await state.copyThenClear('secret', ClipboardClearTimeout.never);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(writes, ['secret'], reason: 'never must not wipe the clipboard');
    });

    testWidgets('a second copy cancels the first pending wipe', (tester) async {
      final writes = recordClipboardWrites(tester);
      final state = await _pumpHost(tester);
      await state.copyThenClear('first', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await state.copyThenClear('second', ClipboardClearTimeout.thirtySeconds);
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

    testWidgets('dispose cancels a pending wipe', (tester) async {
      final writes = recordClipboardWrites(tester);
      final state = await _pumpHost(tester);
      await state.copyThenClear('secret', ClipboardClearTimeout.thirtySeconds);
      await tester.pump();
      // Tear the host down before the wipe is due.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 30));
      expect(writes, ['secret'], reason: 'dispose cancelled the pending wipe');
    });
  });
}
