import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/autotype_listener.dart';

// A unique socket path per test (distinct name + pid) under the system temp
// dir, so parallel tests never collide.
String _uniqueSock(String name) =>
    '${Directory.systemTemp.path}/gabbro-3-4b-$name-$pid.sock';

const _token = 'gabbro-autotype-trigger';

Future<void> _send(String path, List<int> bytes) async {
  final s = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix), 0);
  s.add(bytes);
  await s.flush();
  await s.close();
  await s.done;
}

void main() {
  group('AutotypeListener', () {
    test('fires onTrigger when the exact token arrives', () async {
      final path = _uniqueSock('fires');
      var fired = 0;
      final l = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () => fired++);
      expect(await l.start(), isTrue);
      await _send(path, utf8.encode(_token));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fired, 1);
      await l.stop();
    });

    test('does not fire on wrong bytes', () async {
      final path = _uniqueSock('wrong');
      var fired = 0;
      final l = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () => fired++);
      await l.start();
      await _send(path, utf8.encode('garbage'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fired, 0);
      await l.stop();
    });

    test('fires once per trigger', () async {
      final path = _uniqueSock('twice');
      var fired = 0;
      final l = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () => fired++);
      await l.start();
      await _send(path, utf8.encode(_token));
      await _send(path, utf8.encode(_token));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fired, 2);
      await l.stop();
    });

    test('start clears a stale socket file and binds', () async {
      final path = _uniqueSock('stale');
      File(path).writeAsBytesSync(const [0]); // a leftover file, nobody listening
      final l = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () {});
      expect(await l.start(), isTrue);
      await l.stop();
    });

    test('start declines and does not clobber a live listener', () async {
      final path = _uniqueSock('live');
      var firstFired = 0;
      final first = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () => firstFired++);
      expect(await first.start(), isTrue);

      final second = AutotypeListener(
          socketPath: path, token: _token, onTrigger: () {});
      expect(await second.start(), isFalse); // another instance owns it

      // The original listener still works.
      await _send(path, utf8.encode(_token));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(firstFired, 1);
      await first.stop();
    });
  });
}
