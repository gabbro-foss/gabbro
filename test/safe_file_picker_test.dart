import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/safe_file_picker.dart';

void main() {
  group('runPicker', () {
    test('returns the value when the picker op succeeds', () async {
      final result = await runPicker<String>(() async => '/home/u/v.gabbro');
      expect(result, '/home/u/v.gabbro');
    });

    // A null return is the user cancelling the dialog - it must pass straight
    // through, never be confused with the portal being unavailable.
    test('returns null when the op returns null (user cancelled)', () async {
      final result = await runPicker<String>(() async => null);
      expect(result, isNull);
    });

    // The real failure from the trace: file_picker talks to the XDG portal over
    // the DBus session bus; in a bubblewrap sandbox the socket is missing and
    // DBusClient._openSocket throws SocketException.
    test('converts a SocketException into FilePickerUnavailable', () async {
      expect(
        () => runPicker<String>(
          () async => throw const SocketException('no /run/user/1000/bus'),
        ),
        throwsA(isA<FilePickerUnavailable>()),
      );
    });

    // Defensive: depending on the environment the portal layer can throw other
    // exception types (e.g. DBusException). All become FilePickerUnavailable.
    test('converts any other Exception into FilePickerUnavailable', () async {
      expect(
        () => runPicker<String>(() async => throw Exception('boom')),
        throwsA(isA<FilePickerUnavailable>()),
      );
    });

    test('FilePickerUnavailable exposes the underlying cause', () async {
      const cause = SocketException('no bus');
      try {
        await runPicker<String>(() async => throw cause);
        fail('expected FilePickerUnavailable');
      } on FilePickerUnavailable catch (e) {
        expect(e.cause, same(cause));
      }
    });
  });

  // R-04 keeps the process non-dumpable so a same-uid peer cannot ptrace it.
  // But xdg-desktop-portal must read /proc/<pid> to open a native dialog, which
  // a non-dumpable process forbids. runPicker therefore raises dumpability for
  // the picker window and lowers it again afterwards.
  group('runPicker dumpable window', () {
    tearDown(resetDumpableToggle);

    test('raises dumpable before the op and lowers it after success', () async {
      final events = <String>[];
      dumpableToggle = (raise) async => events.add(raise ? 'raise' : 'lower');
      await runPicker<String>(() async {
        events.add('op');
        return '/home/u/v.gabbro';
      });
      expect(events, ['raise', 'op', 'lower']);
    });

    test('lowers dumpable even when the op throws', () async {
      final events = <String>[];
      dumpableToggle = (raise) async => events.add(raise ? 'raise' : 'lower');
      await expectLater(
        runPicker<String>(() async {
          events.add('op');
          throw Exception('boom');
        }),
        throwsA(isA<FilePickerUnavailable>()),
      );
      expect(events, ['raise', 'op', 'lower']);
    });

    test('nested calls keep dumpable raised until the outermost completes',
        () async {
      final events = <String>[];
      dumpableToggle = (raise) async => events.add(raise ? 'raise' : 'lower');
      await runPicker<String>(() async {
        events.add('outer');
        await runPicker<String>(() async {
          events.add('inner');
          return null;
        });
        return null;
      });
      expect(events, ['raise', 'outer', 'inner', 'lower']);
    });
  });
}
