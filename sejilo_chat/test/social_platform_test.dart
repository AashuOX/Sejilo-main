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

  final sampleImage = Uint8List.fromList(List.generate(100, (i) => i % 256));
  final sampleBase64 = base64Url.encode(sampleImage).replaceAll('=', '');

  group('Social Platform Controller Tests', () {
    test('createPost adds local post and dispatches POST /v1/posts', () async {
      bool posted = false;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/posts') {
          posted = true;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['caption'], equals('Testing social post'));
          return http.Response(jsonEncode({'id': 'post_123'}), 201, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.createPost(
        image: sampleImage,
        mimeType: 'image/jpeg',
        caption: 'Testing social post',
      );

      expect(auth.posts.length, equals(1));
      expect(auth.posts.first.caption, equals('Testing social post'));
      expect(posted, isTrue);
    });

    test('loadFeed parses paginated posts with liked and saved flags', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/feed') {
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 'post_999',
                  'userId': 'usr_alice',
                  'username': 'alice',
                  'displayName': 'Alice W',
                  'caption': 'Hello SejiloChat!',
                  'media': {'mimeType': 'image/jpeg', 'data': sampleBase64},
                  'createdAt': DateTime.now().toIso8601String(),
                  'likes': 5,
                  'comments': 2,
                  'liked': true,
                  'saved': true,
                }
              ],
              'nextCursor': '2026-08-19T10:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final page = await auth.loadFeed();
      expect(page.posts.length, equals(1));
      expect(page.posts.first.id, equals('post_999'));
      expect(page.posts.first.liked, isTrue);
      expect(page.posts.first.saved, isTrue);
      expect(page.nextCursor, equals('2026-08-19T10:00:00.000Z'));
    });

    test('like and save actions update state and send requests', () async {
      bool likedReq = false;
      bool savedReq = false;

      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/posts/post_1/likes') {
          likedReq = true;
          return http.Response(jsonEncode({'success': true}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.method == 'POST' && req.url.path == '/v1/posts/post_1/saves') {
          savedReq = true;
          return http.Response(jsonEncode({'success': true}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.setLike('post_1', true);
      await auth.setSave('post_1', true);

      expect(likedReq, isTrue);
      expect(savedReq, isTrue);
      expect(auth.savedPostIds.contains('post_1'), isTrue);
    });

    test('loadComments and addComment update comment list and counts', () async {
      bool commentPosted = false;

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/posts/post_1/comments') {
          return http.Response(
            jsonEncode({
              'comments': [
                {
                  'id': 'cmt_1',
                  'userId': 'usr_bob',
                  'username': 'bob',
                  'displayName': 'Bob M',
                  'text': 'Awesome photo!',
                  'createdAt': DateTime.now().toIso8601String(),
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/posts/post_1/comments') {
          commentPosted = true;
          return http.Response(
            jsonEncode({
              'comment': {
                'id': 'cmt_2',
                'userId': 'usr_me',
                'username': 'you',
                'displayName': 'You',
                'text': 'Thanks!',
                'createdAt': DateTime.now().toIso8601String(),
              }
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final initial = await auth.loadComments('post_1');
      expect(initial.length, equals(1));
      expect(initial.first.text, equals('Awesome photo!'));

      await auth.addComment('post_1', 'Thanks!');
      expect(commentPosted, isTrue);
    });

    test('searchUsers queries backend search endpoint and returns profiles', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/users/search') {
          expect(req.url.queryParameters['q'], equals('alice'));
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'id': 'usr_alice',
                  'username': 'alice',
                  'displayName': 'Alice Wonderland',
                  'bio': 'Exploring decentralized networks',
                  'followersCount': 12,
                  'followingCount': 8,
                  'followedByViewer': false,
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final results = await auth.searchUsers('alice');
      expect(results.length, equals(1));
      expect(results.first.username, equals('alice'));
      expect(results.first.followersCount, equals(12));
    });

    test('notifications load and mark read dispatches POST /v1/notifications/read', () async {
      bool markedRead = false;

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/notifications') {
          return http.Response(
            jsonEncode({
              'unreadCount': 1,
              'notifications': [
                {
                  'id': 'notif_1',
                  'type': 'like',
                  'postId': 'post_1',
                  'isRead': false,
                  'createdAt': DateTime.now().toIso8601String(),
                  'actor': {
                    'id': 'usr_bob',
                    'username': 'bob',
                    'displayName': 'Bob',
                    'bio': '',
                    'followersCount': 0,
                    'followingCount': 0,
                    'followedByViewer': false,
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/notifications/read') {
          markedRead = true;
          return http.Response(jsonEncode({'success': true}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final notifs = await auth.loadNotifications();
      expect(notifs.length, equals(1));
      expect(auth.unreadNotificationsCount, equals(1));

      await auth.markNotificationsRead();
      expect(auth.unreadNotificationsCount, equals(0));
      expect(markedRead, isTrue);
    });

    group('STEP 8 — Follow System', () {
      test('follow/unfollow updates local state and dispatches to backend', () async {
        String? followedUsername;
        String? unfollowedUsername;
        final client = MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'POST' && path == '/v1/users/bob/follow') {
            followedUsername = 'bob';
            return http.Response(
              jsonEncode({
                'profile': {
                  'id': 'usr-bob',
                  'username': 'bob',
                  'displayName': 'Bob',
                  'bio': '',
                  'followersCount': 1,
                  'followingCount': 0,
                  'followedByViewer': true,
                  'isFollowing': true,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'DELETE' && path == '/v1/users/bob/follow') {
            unfollowedUsername = 'bob';
            return http.Response(
              jsonEncode({
                // `id` included because the real DELETE .../follow answers with
                // the same full profile the POST does. The stub used to omit it
                // and the test only passed because setFollow swallowed the
                // resulting parse error.
                'profile': {
                  'id': 'usr-bob',
                  'username': 'bob',
                  'displayName': 'Bob',
                  'bio': '',
                  'followersCount': 0,
                  'followedByViewer': false,
                  'isFollowing': false,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' && path == '/v1/users/1/followers') {
            return http.Response(
              jsonEncode({
                'users': [
                  {'id': 'usr-me', 'username': 'me', 'displayName': 'Me', 'bio': ''}
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' && path == '/v1/users/1/following') {
            return http.Response(
              jsonEncode({
                'users': [
                  {'id': 'usr-bob', 'username': 'bob', 'displayName': 'Bob', 'bio': ''}
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final auth = AccountAuthController(client: client);
        final followed = await auth.setFollow('bob', true);
        expect(followed.followedByViewer, isTrue);
        expect(followedUsername, equals('bob'));

        final followers = await auth.loadFollowers('1');
        expect(followers.length, equals(1));

        final following = await auth.loadFollowing('1');
        expect(following.length, equals(1));
        expect(following.first.username, equals('bob'));

        final unfollowed = await auth.setFollow('bob', false);
        expect(unfollowed.followedByViewer, isFalse);
        expect(unfollowedUsername, equals('bob'));
      });
    });
  });
}
