import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/linux_url_opener.dart';
import 'package:gabbro/widgets/url_link.dart';

import 'test_helpers.dart';

// Net for the url_launcher replacement: pins what a link tap actually does —
// the URL the user was shown is the URL handed to the browser, and a launch
// that fails says so instead of appearing to work.

/// Records what it was asked to open, and answers as the test dictates.
class _RecordingOpener extends LinuxUrlOpener {
  _RecordingOpener() : super(runProcess: _never);

  static Future<ProcessResult> _never(String _, List<String> _) async =>
      ProcessResult(0, 0, '', '');

  final opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

Widget _host(String url) => testApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showUrlDialog(context, title: 'Source', url: url),
            child: const Text('open dialog'),
          ),
        ),
      ),
    );

Future<void> _tapOpenInBrowser(WidgetTester tester) async {
  await tester.tap(find.text('open dialog'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open in browser'));
  await tester.pumpAndSettle();
}

void main() {
  late _RecordingOpener opener;

  setUp(() {
    opener = _RecordingOpener();
    GabbroUrlOpener.isLinux = () => true;
    GabbroUrlOpener.linuxOpener = opener;
  });

  tearDown(GabbroUrlOpener.reset);

  testWidgets('N1: Open in browser hands over the URL that was shown',
      (tester) async {
    await tester.pumpWidget(_host('https://example.com/docs'));

    await _tapOpenInBrowser(tester);

    expect(opener.opened.single, Uri.parse('https://example.com/docs'));
  });

  testWidgets('N1: the dialog closes once the browser has been asked',
      (tester) async {
    await tester.pumpWidget(_host('https://example.com'));

    await _tapOpenInBrowser(tester);

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('N1: Close launches nothing', (tester) async {
    await tester.pumpWidget(_host('https://example.com'));

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(opener.opened, isEmpty);
  });

  testWidgets('N2: a launch that fails tells the user', (tester) async {
    opener.result = false;
    await tester.pumpWidget(_host('https://example.com'));

    await _tapOpenInBrowser(tester);

    expect(find.text('Could not open https://example.com'), findsOneWidget);
  });

  // 7c: a refusal is a rule, not a fault. "Could not open" would send the user
  // hunting for a broken browser.
  testWidgets('7c: a link that is not a web page says exactly that',
      (tester) async {
    await tester.pumpWidget(_host('ssh://example.com'));

    await _tapOpenInBrowser(tester);

    expect(find.text('Only web links can be opened'), findsOneWidget);
    expect(find.textContaining('Could not open'), findsNothing);
    expect(opener.opened, isEmpty);
  });

  // 7d: on Linux a screen reader never reads a SnackBar, so the message is
  // announced too — otherwise a blind user gets silence either way.
  testWidgets('7d: the message is announced, not only shown', (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final data = message as Map<dynamic, dynamic>;
        if (data['type'] == 'announce') {
          announcements.add(data['data']['message'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));

    await tester.pumpWidget(_host('ssh://example.com'));
    await _tapOpenInBrowser(tester);

    expect(announcements, contains('Only web links can be opened'));
  });
}
