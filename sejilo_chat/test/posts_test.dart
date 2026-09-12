import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('STEP 10-12 — Posts / Likes / Comments', () {
    test('loadFeed and loadExplore parse posts with liked/saved flags', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/feed') {
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 'post_feed_1',
                  'userId': 'usr-2',
                  'username': 'followed_user',
                  'displayName': 'Followed User',
                  'caption': 'From the feed',
                  'media': {'mimeType': 'image/jpeg', 'data': 'dGVzdA=='},
                  'createdAt': DateTime.now().toIso8601String(),
                  'likes': 4,
                  'comments': 1,
                  'liked': false,
                  'saved': false,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'GET' && req.url.path == '/v1/explore') {
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 'post_explore_1',
                  'userId': 'usr-9',
                  'username': 'explorer',
                  'displayName': 'Explorer',
                  'caption': 'Explore grid',
                  'media': {'mimeType': 'image/jpeg', 'data': 'dGVzdA=='},
                  'createdAt': DateTime.now().toIso8601String(),
                  'likes': 10,
                  'comments': 2,
                  'liked': false,
                  'saved': false,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final feed = await auth.loadFeed();
      expect(feed.posts.length, equals(1));
      expect(feed.posts.first.caption, equals('From the feed'));

      final explore = await auth.discoverPosts();
      expect(explore.length, equals(1));
      expect(explore.first.likes, equals(10));
    });

    test('setLike / setSave toggle local state and dispatch to backend', () async {
      bool likePosted = false;
      bool likeDeleted = false;
      bool savePosted = false;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'POST' && path == '/v1/posts/post_1/likes') {
          likePosted = true;
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (req.method == 'DELETE' && path == '/v1/posts/post_1/likes') {
          likeDeleted = true;
          return http.Response('', 204);
        }
        if (req.method == 'POST' && path == '/v1/posts/post_1/saves') {
          savePosted = true;
          return http.Response(jsonEncode({'success': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.setLike('post_1', true);
      expect(likePosted, isTrue);

      await auth.setLike('post_1', false);
      expect(likeDeleted, isTrue);

      await auth.setSave('post_1', true);
      expect(savePosted, isTrue);
      expect(auth.savedPostIds.contains('post_1'), isTrue);
    });

    test('a save the server rejects is rolled back, not left looking saved',
        () async {
      // The bookmark endpoint answers 404 — the post is gone. Before the client
      // was taught to care, this response was swallowed and the icon stayed
      // filled with nothing behind it.
      final client = MockClient((req) async => http.Response(
            jsonEncode({'message': 'Post not found.'}),
            404,
            headers: {'content-type': 'application/json'},
          ));

      final auth = AccountAuthController(client: client);
      await expectLater(
        auth.setSave('post_gone', true),
        throwsA(isA<ApiException>()),
      );
      expect(auth.savedPostIds.contains('post_gone'), isFalse);
      expect(auth.error, equals('Post not found.'));
    });

    test('a failed unsave puts the bookmark back', () async {
      var allowSave = true;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/posts/post_1/saves') {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (req.method == 'DELETE' && allowSave) {
          // Server unreachable rather than refusing: the bookmark is still
          // there, so the client must not pretend it removed it.
          return http.Response('Service Unavailable', 503);
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.setSave('post_1', true);
      expect(auth.savedPostIds.contains('post_1'), isTrue);

      await expectLater(
        auth.setSave('post_1', false),
        throwsA(isA<ApiException>()),
      );
      expect(auth.savedPostIds.contains('post_1'), isTrue);
    });

    test('a like the server rejects leaves the count where it was', () async {
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/posts') {
          return http.Response(
            jsonEncode({
              'id': 'post_local_1',
              'createdAt': DateTime.now().toIso8601String(),
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/likes')) {
          return http.Response(
            jsonEncode({'message': 'Post not found.'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.createPost(
        image: Uint8List.fromList(List.generate(120, (i) => (i * 5) % 256)),
        mimeType: 'image/jpeg',
        caption: 'Local post',
      );
      final before = auth.posts.first;
      expect(before.liked, isFalse);

      await expectLater(
        auth.setLike(before.id, true),
        throwsA(isA<ApiException>()),
      );
      final after = auth.posts.firstWhere((p) => p.id == before.id);
      expect(after.liked, isFalse);
      expect(after.likes, equals(before.likes));
    });

    test('loadSavedPosts reads the server list and reports its failures',
        () async {
      var fail = false;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/saved-posts') {
          if (fail) return http.Response('Bad Gateway', 502);
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 'post_saved_1',
                  'userId': 'usr-9',
                  'username': 'explorer',
                  'displayName': 'Explorer',
                  'caption': 'Bookmarked earlier',
                  'media': {'mimeType': 'image/jpeg', 'data': 'dGVzdA=='},
                  'createdAt': DateTime.now().toIso8601String(),
                  'likes': 3,
                  'comments': 1,
                  'liked': false,
                  'saved': true,
                },
              ],
              'nextCursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final saved = await auth.loadSavedPosts();
      expect(saved.length, equals(1));
      expect(saved.first.id, equals('post_saved_1'));
      expect(saved.first.saved, isTrue);

      // A failure has to reach the caller: the Saved tab shows an error and a
      // retry rather than an empty grid that looks like "no bookmarks".
      fail = true;
      await expectLater(auth.loadSavedPosts(), throwsA(isA<ApiException>()));
    });

    test('deletePost dispatches DELETE /v1/posts/:id', () async {
      bool deleted = false;
      final client = MockClient((req) async {
        if (req.method == 'DELETE' &&
            req.url.path == '/v1/posts/post_del_1') {
          deleted = true;
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });
      final auth = AccountAuthController(client: client);
      await auth.deletePost('post_del_1');
      expect(deleted, isTrue);
    });
  });

  group('Feed paging and in-app sharing', () {
    SocialPost samplePost() => SocialPost(
          id: 'post_share_1',
          userId: 'usr-7',
          username: 'photographer',
          displayName: 'Photographer',
          caption: 'Sunrise',
          media: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x01, 0x02]),
          createdAt: DateTime.now(),
          likes: 3,
          comments: 0,
          liked: false,
        );

    test('loadExplore forwards the cursor and returns the next one', () async {
      String? seenCursor;
      var calls = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/explore') {
          calls++;
          seenCursor = req.url.queryParameters['cursor'];
          return http.Response(
            jsonEncode({
              'posts': const <Map<String, dynamic>>[],
              'nextCursor': '2026-08-29T10:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final first = await auth.loadExplore();
      expect(seenCursor, isNull);
      expect(first.nextCursor, equals('2026-08-29T10:00:00.000Z'));

      await auth.loadExplore(cursor: first.nextCursor);
      expect(calls, equals(2));
      expect(seenCursor, equals('2026-08-29T10:00:00.000Z'));
    });

    test('sharePostWithUser opens one direct thread and attaches the picture',
        () async {
      var conversationsOpened = 0;
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/chat/conversations') {
          conversationsOpened++;
          expect(
            jsonDecode(req.body) as Map<String, dynamic>,
            equals({'kind': 'direct', 'recipientUserId': 'usr-42'}),
          );
          return http.Response(
            jsonEncode({'id': 'conv_9', 'isExisting': true}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' &&
            req.url.path == '/v1/chat/conversations/conv_9/messages') {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'id': 'msg_1'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final conversationId = await auth.sharePostWithUser(
        recipientUserId: 'usr-42',
        post: samplePost(),
        note: 'look at this',
      );

      expect(conversationId, equals('conv_9'));
      expect(conversationsOpened, equals(1));
      expect(sent!['text'], contains('look at this'));
      expect(sent!['text'], contains('@photographer'));
      expect(sent!['text'], contains('Sunrise'));
      // The post's own bytes travel with the message; nothing points at a link
      // this build could not open.
      final media = sent!['media'] as Map<String, dynamic>;
      expect(media['mimeType'], equals('image/jpeg'));
      expect(
        base64Url.decode(base64Url.normalize(media['data'] as String)),
        equals([0xFF, 0xD8, 0xFF, 0x01, 0x02]),
      );
    });

    test('a refused recipient surfaces the server\'s own message', () async {
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/chat/conversations') {
          return http.Response(
            jsonEncode({'message': 'This account is not available.'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await expectLater(
        auth.sharePostWithUser(
          recipientUserId: 'usr-blocked',
          post: samplePost(),
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          equals('This account is not available.'),
        )),
      );
    });
  });
}
