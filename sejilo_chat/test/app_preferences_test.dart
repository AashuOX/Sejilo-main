// Covers the two content preferences that now change what the app draws:
// "Hide like and comment counts" and the hidden-words list. Both used to be
// stored and never read, so nothing here had anything to protect.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AppPreferences — hide like and comment counts', () {
    test('defaults to showing counts', () async {
      final prefs = AppPreferences();
      await prefs.load();
      expect(prefs.hideLikeCounts, isFalse);
    });

    test('notifies listeners and survives a reload', () async {
      final prefs = AppPreferences();
      await prefs.load();

      var notified = 0;
      prefs.addListener(() => notified++);
      await prefs.setHideLikeCounts(true);

      expect(prefs.hideLikeCounts, isTrue);
      // The feed cards rebuild off this notification; without it the switch
      // would only take effect on the next cold start.
      expect(notified, equals(1));

      final reloaded = AppPreferences();
      await reloaded.load();
      expect(reloaded.hideLikeCounts, isTrue);
    });
  });

  group('AppPreferences — hidden words', () {
    test('matches whole words only', () async {
      final prefs = AppPreferences();
      await prefs.load();
      await prefs.addHiddenWord('ace');

      expect(prefs.isHidden('ace of spades'), isTrue);
      expect(prefs.isHidden('ACE'), isTrue, reason: 'case-insensitive');
      expect(prefs.isHidden('what a space'), isFalse);
      expect(prefs.isHidden('faceless'), isFalse);
      expect(prefs.isHidden(''), isFalse);
    });

    test('a multi-word entry matches as a phrase', () async {
      final prefs = AppPreferences();
      await prefs.load();
      await prefs.addHiddenWord('Buy Now');

      expect(prefs.isHidden('please buy now, cheap'), isTrue);
      expect(prefs.isHidden('buy it now'), isFalse);
    });

    test('entries are normalised, deduplicated and removable', () async {
      final prefs = AppPreferences();
      await prefs.load();
      await prefs.addHiddenWord('  Spoiler  ');
      await prefs.addHiddenWord('spoiler');
      await prefs.addHiddenWord('');

      expect(prefs.hiddenWords, equals(['spoiler']));
      expect(prefs.isHidden('big SPOILER ahead'), isTrue);

      await prefs.removeHiddenWord('SPOILER');
      expect(prefs.hiddenWords, isEmpty);
      expect(prefs.isHidden('big spoiler ahead'), isFalse);
    });

    test('the list survives a reload', () async {
      final prefs = AppPreferences();
      await prefs.load();
      await prefs.addHiddenWord('spoiler');

      final reloaded = AppPreferences();
      await reloaded.load();
      expect(reloaded.hiddenWords, equals(['spoiler']));
      expect(reloaded.isHidden('a spoiler'), isTrue);
    });

    test('an empty list hides nothing', () async {
      final prefs = AppPreferences();
      await prefs.load();
      expect(prefs.isHidden('anything at all'), isFalse);
    });
  });
}
