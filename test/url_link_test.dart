import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/widgets/url_link.dart';

import 'test_helpers.dart';

// Net for the url_launcher replacement: pins what a link tap actually does —
// the URL the user was shown is the URL handed to the browser, and a launch
// that fails says so instead of appearing to work.

/// Records what it was asked to open, and answers as the test dictates.
class _RecordingOpener {
  final opened = <Uri>[];
  bool result = true;

  Future<bool> call(Uri uri) async {
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
    openUrl = opener.call;
  });

  tearDown(resetUrlOpener);

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

    expect(find.textContaining('https://example.com'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
