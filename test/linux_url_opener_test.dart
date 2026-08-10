import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/linux_url_opener.dart';

// Opening a link on Linux hands the URL to the desktop's own handler. The URL
// comes from vault data, so it is passed as one argument to `xdg-open` and
// never through a shell, where its punctuation would be read as commands.

/// Stands in for the real process: records the call, answers as told.
class _FakeRunner {
  final calls = <(String, List<String>)>[];
  int exitCode = 0;

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return ProcessResult(1, exitCode, '', '');
  }
}

void main() {
  late _FakeRunner runner;
  late LinuxUrlOpener opener;

  setUp(() {
    runner = _FakeRunner();
    opener = LinuxUrlOpener(runProcess: runner.call);
  });

  test('1: the URL goes to xdg-open as a single argument', () async {
    final opened = await opener.open(Uri.parse('https://example.com/a b&c'));

    expect(opened, isTrue);
    expect(runner.calls.single.$1, 'xdg-open');
    expect(runner.calls.single.$2, ['https://example.com/a%20b&c']);
  });

  test('2: a handler that refuses the URL reports failure', () async {
    runner.exitCode = 4;

    expect(await opener.open(Uri.parse('https://example.com')), isFalse);
  });

  test('2: no xdg-open on the box reports failure, it does not throw',
      () async {
    final missing = LinuxUrlOpener(
      runProcess: (_, _) =>
          Future.error(ProcessException('xdg-open', const [], 'No such file')),
    );

    expect(await missing.open(Uri.parse('https://example.com')), isFalse);
  });
}
