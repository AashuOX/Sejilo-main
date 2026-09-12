import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/settings/settings_page.dart';

void main() {
  test('the version shown in Settings is the version that was built', () {
    // kSejiloVersion is written by hand and displayed on the Settings screen,
    // while the number that actually ships in the APK comes from pubspec.yaml.
    // Nothing tied the two together, so the screen could report a build the
    // binary was not.
    final pubspec = File('pubspec.yaml');
    if (!pubspec.existsSync()) {
      markTestSkipped('pubspec.yaml not reachable from the package root.');
      return;
    }
    final match = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
            multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    expect(match, isNotNull,
        reason: 'pubspec.yaml must carry a `version: x.y.z+build` line — '
            'flutter reads versionName and versionCode from it.');

    expect(
      kSejiloVersion,
      equals('${match!.group(1)} (${match.group(2)})'),
      reason: 'Settings would show "$kSejiloVersion" for a build that reports '
          '${match.group(1)} (${match.group(2)}) to Android. Update both, or '
          'the screen misidentifies which APK is on the phone.',
    );
  });
}
