// The About screen's open-source list is hand-maintained. Nothing used to check
// it against the manifests, so a dependency could be added and shipped with no
// attribution at all. These tests read `pubspec.yaml` and `rust/Cargo.toml` at
// test time and fail if a direct dependency is missing from the screen, plus pin
// the entries whose licence is easy to get wrong.
//
// Assets (the Public Suffix List, the wordlists) are not derivable from a
// manifest, so those are a fixed expected set.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'test_helpers.dart';

/// Direct dependencies of the Flutter app. The SDK entries and our own Rust
/// crate are not third-party components, so they carry no attribution.
const _pubExclusions = {'flutter', 'flutter_localizations', 'rust_lib_gabbro'};

List<String> _pubDependencies() {
  final file = File('pubspec.yaml');
  expect(file.existsSync(), isTrue,
      reason: 'pubspec.yaml not found - tests must run from the repo root');
  final names = <String>[];
  var inDeps = false;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('dependencies:')) {
      inDeps = true;
      continue;
    }
    // Any other top-level key ends the block.
    if (inDeps && line.isNotEmpty && !line.startsWith(' ')) break;
    if (!inDeps) continue;
    final m = RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line);
    if (m != null && !_pubExclusions.contains(m.group(1))) {
      names.add(m.group(1)!);
    }
  }
  expect(names, isNotEmpty,
      reason: 'parsed no dependencies from pubspec.yaml - has it moved?');
  return names;
}

/// Direct dependencies of the Rust crate: `[dependencies]` plus every
/// `[target.'cfg(...)'.dependencies]`. Dev- and build-dependencies are not
/// shipped, so they are excluded.
List<String> _cargoDependencies() {
  final file = File('rust/Cargo.toml');
  expect(file.existsSync(), isTrue,
      reason: 'rust/Cargo.toml not found - tests must run from the repo root');
  final names = <String>{};
  var inDeps = false;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inDeps = line == '[dependencies]' ||
          RegExp(r'^\[target\..*\.dependencies\]$').hasMatch(line);
      continue;
    }
    if (!inDeps || line.isEmpty || line.startsWith('#')) continue;
    final m = RegExp(r'^([A-Za-z0-9_-]+)\s*=').firstMatch(line);
    if (m != null) names.add(m.group(1)!);
  }
  expect(names, isNotEmpty,
      reason: 'parsed no dependencies from rust/Cargo.toml - has it moved?');
  return names.toList();
}

/// Every string rendered on the screen.
List<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

/// True when [name] appears in [haystack] as a whole token, so `intl` does not
/// match inside `distinctly` but `serde` does match in `serde / serde_json`.
bool _namesComponent(List<String> haystack, String name) {
  final pattern = RegExp('(^|[^A-Za-z0-9_-])${RegExp.escape(name)}'
      r'($|[^A-Za-z0-9_-])');
  return haystack.any(pattern.hasMatch);
}

/// The licence shown beside [name], or null when [name] is not listed.
String? _licenceFor(WidgetTester tester, String name) {
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
    final title = tile.title;
    final subtitle = tile.subtitle;
    if (title is Text && title.data == name && subtitle is Text) {
      return subtitle.data;
    }
  }
  return null;
}

Future<List<String>> _pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(testApp(const AboutScreen()));
  await tester.pumpAndSettle();
  return _renderedText(tester);
}

void main() {
  testWidgets('About names every direct pub dependency', (tester) async {
    final rendered = await _pumpAbout(tester);
    for (final dep in _pubDependencies()) {
      expect(_namesComponent(rendered, dep), isTrue,
          reason: '$dep is a direct pubspec.yaml dependency but the About '
              'screen does not name it');
    }
  });

  testWidgets('About names every direct Rust dependency', (tester) async {
    final rendered = await _pumpAbout(tester);
    for (final dep in _cargoDependencies()) {
      expect(_namesComponent(rendered, dep), isTrue,
          reason: '$dep is a direct rust/Cargo.toml dependency but the About '
              'screen does not name it');
    }
  });

  testWidgets('About shows the dual licence for jni', (tester) async {
    await _pumpAbout(tester);
    // Crate metadata says MIT/Apache-2.0; the screen claimed MIT alone.
    expect(_licenceFor(tester, 'jni'), 'Apache-2.0 / MIT');
  });

  testWidgets('About credits the libfido2 crate and C library separately',
      (tester) async {
    await _pumpAbout(tester);
    // Both ship: the Rust binding (MIT) and Yubico's C library it links
    // against (BSD-2-Clause). One entry cannot carry both licences.
    expect(_licenceFor(tester, 'libfido2-sys'), 'MIT');
    expect(_licenceFor(tester, 'libfido2 (Yubico)'), 'BSD-2-Clause');
  });

  testWidgets('About credits the Public Suffix List', (tester) async {
    final rendered = await _pumpAbout(tester);
    // Ships inside every APK as an Android asset (autofill eTLD+1 matching).
    expect(_namesComponent(rendered, 'Public Suffix List'), isTrue);
    expect(_licenceFor(tester, 'Public Suffix List'), 'MPL-2.0');
  });

  testWidgets('About credits the Slovak and Greek wordlist sources',
      (tester) async {
    final rendered = await _pumpAbout(tester);
    expect(_namesComponent(rendered, 'diceware_slovak'), isTrue);
    expect(_namesComponent(rendered, 'greek-dictionary'), isTrue);
  });
}
