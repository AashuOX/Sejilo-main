import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('STEP 9 — Stories', () {
    test('create text story dispatches POST /v1/stories and stores locally', () async {
      bool posted = false;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/stories') {
          posted = true;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['type'], equals('text'));
          expect(body['textContent'], equals('Hello story'));
          return http.Response(
            jsonEncode({
              'id': 'story-qa-009',
              'username': 'qa_tester',
              'displayName': 'QA Tester',
              'type': 'text',
              'textContent': 'Hello story',
              'backgroundStyle': 'gradient_0',
              'createdAt': DateTime.now().toIso8601String(),
              'expiresAt':
                  DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
              'viewedByMe': false,
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.createTextStory(
        text: 'Hello story',
        backgroundStyle: 'gradient_0',
      );

      expect(posted, isTrue);
      // Local story is stored; loadStories falls back to local when GET 404s.
      final local = await auth.loadStories();
      expect(local.length, equals(1));
      expect(local.first.textContent, equals('Hello story'));
    });

    test('loadStories parses remote stories; markStoryViewed + loadStoryViewers + deleteStory', () async {
      String? viewPosted;
      String? deletedId;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path == '/v1/stories' && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'stories': [
                {
                  'id': 'story-remote-1',
                  'userId': 'usr-2',
                  'username': 'followed_user',
                  'displayName': 'Followed User',
                  'type': 'text',
                  'textContent': 'A story',
                  'backgroundStyle': 'gradient_0',
                  'createdAt': DateTime.now().toIso8601String(),
                  'expiresAt': DateTime.now()
                      .add(const Duration(hours: 24))
                      .toIso8601String(),
                  'viewedByMe': false,
                  'viewsCount': 2,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && path == '/v1/stories/story-remote-1/views') {
          viewPosted = path;
          return http.Response('', 204);
        }
        if (req.method == 'GET' && path == '/v1/stories/story-remote-1/views') {
          return http.Response(
            jsonEncode({
              'viewers': [
                {
                  'userId': 'usr-3',
                  'username': 'viewer_user',
                  'displayName': 'Viewer User',
                  'viewedAt': DateTime.now().toIso8601String(),
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'DELETE' && path == '/v1/stories/story-remote-1') {
          deletedId = 'story-remote-1';
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final stories = await auth.loadStories();
      expect(stories.length, equals(1));
      expect(stories.first.username, equals('followed_user'));

      await auth.markStoryViewed('story-remote-1');
      expect(viewPosted, equals('/v1/stories/story-remote-1/views'));

      final viewers = await auth.loadStoryViewers('story-remote-1');
      expect(viewers.length, equals(1));
      expect(viewers.first.username, equals('viewer_user'));

      await auth.deleteStory('story-remote-1');
      expect(deletedId, equals('story-remote-1'));
    });
  });
}
