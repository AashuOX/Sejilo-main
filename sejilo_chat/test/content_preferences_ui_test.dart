// Proves the content preferences reach the widgets that draw the numbers and
// the comments. Both switches wrote a value nothing read until now, so these
// tests are what stop "Hide like and comment counts" and the hidden-words list
// from silently going back to being decorative.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/core/app_preferences.dart';
import 'package:sejilo_chat/shells/comments_sheet.dart';
import 'package:sejilo_chat/social/post_detail_page.dart';

/// Two comments, one of which mentions a word the test hides.
http.Client _commentsClient() => MockClient((req) async {
      if (req.method == 'GET' &&
          req.url.path == '/v1/posts/post_1/comments') {
        return http.Response(
          jsonEncode({
            'comments': [
              {
                'id': 'cmt_1',
                'userId': 'usr-2',
                'username': 'bob',
                'displayName': 'Bob',
                'text': 'Nice shot',
                'createdAt': DateTime.now().toIso8601String(),
              },
              {
                'id': 'cmt_2',
                'userId': 'usr-3',
                'username': 'carol',
                'displayName': 'Carol',
                'text': 'Massive spoiler in here',
                'createdAt': DateTime.now().toIso8601String(),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 404);
    });

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A real 2×2 PNG, so the post page has something a codec will accept rather
/// than bytes that would fail to decode inside the test.
final Uint8List _png =
    Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

SocialPost _post({int likes = 4, int comments = 2}) => SocialPost(
      id: 'post_1',
      userId: 'usr-2',
      username: 'bob',
      displayName: 'Bob',
      caption: 'A photo',
      media: _png,
      createdAt: DateTime.now(),
      likes: likes,
      comments: comments,
      liked: false,
    );

/// The sheet draws each comment as one `RichText` of "username text", so the
/// body has to be matched inside the spans rather than as a whole `Text`.
Finder _comment(String body) =>
    find.textContaining(body, findRichText: true);

/// Mounts the post page on a phone-shaped surface. The default 800×600 test
/// window is wider than it is tall, which makes the square photo taller than
/// the viewport and leaves the action row — the thing under test — unbuilt
/// below the fold.
Future<void> _pumpPostPage(
  WidgetTester t, {
  required SocialPost post,
  required AccountAuthController auth,
}) async {
  t.view.physicalSize = const Size(400, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  await t.pumpWidget(MaterialApp(home: PostDetailPage(post: post, auth: auth)));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a hidden word drops the comment and says how many', (t) async {
    final prefs = AppPreferences();
    await prefs.load();
    await prefs.addHiddenWord('spoiler');

    final auth =
        AccountAuthController(client: _commentsClient(), preferences: prefs);

    await t.pumpWidget(
      _host(CommentsSheet(auth: auth, postId: 'post_1')),
    );
    await t.pumpAndSettle();

    expect(_comment('Nice shot'), findsOneWidget);
    expect(_comment('Massive spoiler in here'), findsNothing);
    expect(find.text('1 comment hidden by your hidden words.'), findsOneWidget);
  });

  testWidgets('with no hidden words every comment is drawn', (t) async {
    final prefs = AppPreferences();
    await prefs.load();

    final auth =
        AccountAuthController(client: _commentsClient(), preferences: prefs);

    await t.pumpWidget(
      _host(CommentsSheet(auth: auth, postId: 'post_1')),
    );
    await t.pumpAndSettle();

    expect(_comment('Nice shot'), findsOneWidget);
    expect(_comment('Massive spoiler in here'), findsOneWidget);
    expect(
      find.textContaining('hidden by your hidden words'),
      findsNothing,
    );
  });

  testWidgets('hiding every comment explains itself instead of looking empty',
      (t) async {
    final prefs = AppPreferences();
    await prefs.load();
    await prefs.addHiddenWord('spoiler');
    await prefs.addHiddenWord('shot');

    final auth =
        AccountAuthController(client: _commentsClient(), preferences: prefs);

    await t.pumpWidget(
      _host(CommentsSheet(auth: auth, postId: 'post_1')),
    );
    await t.pumpAndSettle();

    expect(find.text('Comments hidden'), findsOneWidget);
    // Not the "no comments yet" state: there are comments, they are filtered.
    expect(find.text('No comments yet'), findsNothing);
  });

  testWidgets('toggling a word while the sheet is open redraws it', (t) async {
    final prefs = AppPreferences();
    await prefs.load();

    final auth =
        AccountAuthController(client: _commentsClient(), preferences: prefs);

    await t.pumpWidget(
      _host(CommentsSheet(auth: auth, postId: 'post_1')),
    );
    await t.pumpAndSettle();
    expect(_comment('Massive spoiler in here'), findsOneWidget);

    await prefs.addHiddenWord('spoiler');
    await t.pumpAndSettle();

    expect(_comment('Massive spoiler in here'), findsNothing);
  });

  group('hide like and comment counts', () {
    testWidgets('the count is drawn while the setting is off', (t) async {
      final prefs = AppPreferences();
      await prefs.load();

      final auth =
          AccountAuthController(client: _commentsClient(), preferences: prefs);

      await _pumpPostPage(t, post: _post(likes: 4), auth: auth);

      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('with the setting on the number is gone but the heart is not',
        (t) async {
      final prefs = AppPreferences();
      await prefs.load();
      await prefs.setHideLikeCounts(true);

      final auth =
          AccountAuthController(client: _commentsClient(), preferences: prefs);

      await _pumpPostPage(t, post: _post(likes: 4), auth: auth);

      expect(find.text('4'), findsNothing);
      // Hiding the count must not take the way to like the post with it.
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
    });

    testWidgets('flipping the setting redraws a page already open', (t) async {
      final prefs = AppPreferences();
      await prefs.load();

      final auth =
          AccountAuthController(client: _commentsClient(), preferences: prefs);

      await _pumpPostPage(t, post: _post(likes: 4), auth: auth);
      expect(find.text('4'), findsOneWidget);

      // Without the listener the switch would only take effect on the next
      // cold start, which is how it used to behave.
      await prefs.setHideLikeCounts(true);
      await t.pumpAndSettle();

      expect(find.text('4'), findsNothing);
    });
  });
}
