import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nets for the Gradle 9 bump (Java-25 JBR unblock). The real net for build
/// scripts is the gate's Android build leg; these fail fast and name the
/// reason if the working configuration is reverted or clobbered.

/// `[major, minor, patch]` of a dotted version, missing parts as 0.
List<int> _parseVersion(String v) {
  final parts = v.split('.').map(int.parse).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

bool _versionAtLeast(String version, String floor) {
  final a = _parseVersion(version);
  final b = _parseVersion(floor);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}

void main() {
  test('gradle wrapper is at least 9.1.0, the floor for running on Java 25', () {
    final props = File(
      'android/gradle/wrapper/gradle-wrapper.properties',
    ).readAsStringSync();
    final match = RegExp(
      r'distributionUrl=.*gradle-(\d+(?:\.\d+)+)-',
    ).firstMatch(props);
    expect(match, isNotNull, reason: 'distributionUrl not found or unparsable');
    final version = match!.group(1)!;
    expect(
      _versionAtLeast(version, '9.1.0'),
      isTrue,
      reason:
          'Gradle $version cannot run on the Java 25 build JDK '
          '(org.gradle.java.home); 9.1.0 is the documented floor',
    );
  });

  test('cargokit plugin does not call Project.exec, removed in Gradle 9', () {
    // The file is vendored; a flutter_rust_bridge template refresh could
    // silently restore the upstream copy and re-break every Android build.
    final plugin = File(
      'rust_builder/cargokit/gradle/plugin.gradle',
    ).readAsStringSync();
    expect(
      plugin,
      isNot(contains('project.exec')),
      reason: 'use the injected ExecOperations service instead',
    );
    expect(
      plugin,
      isNot(contains('project.javaexec')),
      reason: 'use the injected ExecOperations service instead',
    );
    expect(
      plugin,
      contains('ExecOperations'),
      reason: 'the exec calls must go through the injected service',
    );
  });

  test('app module pins Java and Kotlin to the same JVM target', () {
    // Unpinned, Kotlin follows the running JDK and Gradle 9 hard-errors on
    // the Java/Kotlin mismatch, failing every Android build.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final source = RegExp(
      r'sourceCompatibility = JavaVersion\.VERSION_(\d+)',
    ).firstMatch(gradle);
    final target = RegExp(
      r'targetCompatibility = JavaVersion\.VERSION_(\d+)',
    ).firstMatch(gradle);
    final kotlin = RegExp(r'JvmTarget\.JVM_(\d+)').firstMatch(gradle);
    expect(source, isNotNull, reason: 'Java sourceCompatibility pin missing');
    expect(target, isNotNull, reason: 'Java targetCompatibility pin missing');
    expect(kotlin, isNotNull, reason: 'Kotlin jvmTarget pin missing');
    expect(target!.group(1), source!.group(1));
    expect(
      kotlin!.group(1),
      source.group(1),
      reason: 'Kotlin and Java JVM targets must match',
    );
  });
}
