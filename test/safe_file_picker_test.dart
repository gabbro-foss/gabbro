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
}
