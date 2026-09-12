import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/profile/public_profile_page.dart';

/// The server refuses a private account's grid to anyone who is not an accepted
/// follower — `GET /v1/users/:username/posts` answers 403 even with no token.
/// These tests cover what the app does with that answer, because the previous
/// behaviour was to swallow it and draw "No posts yet", which reads as an empty
/// account rather than one the viewer is not allowed to see.

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _profileBody({
  required String username,
  bool isPrivate = false,
  bool followedByViewer = false,
}) =>
    {
      'profile': {
        'id': 'usr_$username',
        'username': username,
        'displayName': username.toUpperCase(),
        'bio': '',
        'followersCount': 3,
        'followingCount': 1,
        'postsCount': 7,
        'followedByViewer': followedByViewer,
        'followRequestPending': false,
        'isPrivate': isPrivate,
        'avatar': null,
      },
    };

/// A backend that serves [username]'s profile and refuses its posts.
///
/// [postsStatus] is what `GET /v1/users/:username/posts` answers: 403 for a
/// private account or a block, 503 for a server that is simply down.
http.Client _clientRefusingPosts({
  required String username,
  bool isPrivate = false,
  bool followedByViewer = false,
  int postsStatus = 403,
  String message = 'This account is private. Follow it to see its posts.',
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/v1/users/$username' && request.method == 'GET') {
      return _json(_profileBody(
        username: username,
        isPrivate: isPrivate,
        followedByViewer: followedByViewer,
      ));
    }
    if (path == '/v1/users/$username/posts' && request.method == 'GET') {
      return _json(
        {'message': message, 'statusCode': postsStatus},
        postsStatus,
      );
    }
    return _json({'message': 'Not found', 'statusCode': 404}, 404);
  });
}

Future<void> _pumpProfile(
  WidgetTester t, {
  required AccountAuthController auth,
  required String username,
}) async {
  // A phone-shaped surface: the default 800×600 test window is wider than it is
  // tall, and the profile header alone is taller than 600, which would leave the
  // grid area — the thing under test — unbuilt below the fold.
  t.view.physicalSize = const Size(400, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    home: UserProfilePage(controller: auth, username: username),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('loadUserPosts — a refusal is not an empty grid', () {
    test('another account\'s 403 reaches the caller', () async {
      final auth = AccountAuthController(
        client: _clientRefusingPosts(username: 'bob', isPrivate: true),
      );

      await expectLater(
        auth.loadUserPosts('bob'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('private'))),
      );
    });

    test('the handle is lower-cased before it is asked for', () async {
      var asked = '';
      final client = MockClient((request) async {
        asked = request.url.path;
        return _json({'message': 'Forbidden', 'statusCode': 403}, 403);
      });
      final auth = AccountAuthController(client: client);

      await expectLater(auth.loadUserPosts('BoB'), throwsA(isA<ApiException>()));
      expect(asked, '/v1/users/bob/posts');
    });

    test('the viewer\'s own grid still falls back to what this device composed',
        () async {
      // A signed-in session is needed for the "is this me?" comparison, so the
      // fake answers the register call and then refuses the grid.
      final client = MockClient((request) async {
        if (request.url.path == '/v1/users' && request.method == 'POST') {
          return _json({
            'id': 'usr_me',
            'token': 'real.access.token.usr_me',
            'refreshToken': 'real.refresh.token.usr_me',
            'isNewUser': true,
            'profile': {
              'id': 'usr_me',
              'email': 'me@example.com',
              'username': 'me',
              'displayName': 'Me',
              'bio': '',
              'avatar': null,
            },
          }, 201);
        }
        if (request.url.path == '/v1/users/me/posts') {
          return _json({'message': 'Server is down', 'statusCode': 503}, 503);
        }
        return _json({'message': 'Not found', 'statusCode': 404}, 404);
      });

      final auth = AccountAuthController(client: client);
      await auth.signUp(
        email: 'me@example.com',
        password: 'Password123!',
        username: 'me',
        displayName: 'Me',
      );

      // No throw, and no fabricated content either — only local posts, of which
      // there are none on a fresh install.
      await expectLater(auth.loadUserPosts('me'), completion(isEmpty));
    });
  });

  group('UserProfilePage — the grid says why it is empty', () {
    testWidgets('a private account gets a lock, not "No posts yet"',
        (t) async {
      final auth = AccountAuthController(
        client: _clientRefusingPosts(username: 'bob', isPrivate: true),
      );

      await _pumpProfile(t, auth: auth, username: 'bob');

      expect(find.text('This account is private'), findsOneWidget);
      expect(
        find.text('Follow @bob to see their photos and videos.'),
        findsOneWidget,
      );
      expect(find.text('No posts yet'), findsNothing);
      // Nothing to retry — the answer will not change until the follow does.
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
      // The header is still there, so the viewer can follow from here.
      expect(find.text('@bob'), findsOneWidget);
    });

    testWidgets('a block reads as unavailable rather than private',
        (t) async {
      final auth = AccountAuthController(
        client: _clientRefusingPosts(
          username: 'carol',
          // The server never tells the viewer they were blocked, so the profile
          // it returns looks ordinary and only the posts are refused.
          isPrivate: false,
          postsStatus: 403,
          message: 'This account is not available.',
        ),
      );

      await _pumpProfile(t, auth: auth, username: 'carol');

      expect(find.text('This account is not available'), findsOneWidget);
      expect(find.text('This account is private'), findsNothing);
      expect(find.text('No posts yet'), findsNothing);
    });

    testWidgets('a server that is down offers a retry', (t) async {
      final auth = AccountAuthController(
        client: _clientRefusingPosts(
          username: 'dave',
          postsStatus: 503,
          message: 'Posts are unavailable right now.',
        ),
      );

      await _pumpProfile(t, auth: auth, username: 'dave');

      expect(find.text('Posts could not be loaded'), findsOneWidget);
      expect(find.text('Posts are unavailable right now.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('an accepted follower sees the grid itself', (t) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/users/bob' && request.method == 'GET') {
          return _json(_profileBody(
            username: 'bob',
            isPrivate: true,
            followedByViewer: true,
          ));
        }
        if (path == '/v1/users/bob/posts' && request.method == 'GET') {
          return _json({'posts': <Map<String, dynamic>>[]});
        }
        return _json({'message': 'Not found', 'statusCode': 404}, 404);
      });

      await _pumpProfile(
          t, auth: AccountAuthController(client: client), username: 'bob');

      // An accepted follower of an account with nothing posted yet: the empty
      // state is the honest answer here, and no notice should appear.
      expect(find.text('No posts yet'), findsOneWidget);
      expect(find.text('This account is private'), findsNothing);
    });
  });
}
