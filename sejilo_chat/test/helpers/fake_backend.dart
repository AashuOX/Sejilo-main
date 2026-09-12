import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fakeProfileJson({
  required String id,
  required String email,
  required String username,
  required String displayName,
  String bio = '',
}) =>
    {
      'id': id,
      'email': email,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'avatar': null,
    };

http.Response fakeJson(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// A fake HTTP transport that mimics the REAL Sejilo backend contract
/// (same paths, request bodies, response shapes). It never fabricates a
/// session on its own — the controller must store whatever the server says.
///
/// Routes handled: POST /v1/users, POST /v1/auth/password/login,
/// POST /v1/auth/google (requires idToken 'verified.google.id.token'),
/// POST /v1/auth/phone/otp-requests (returns devCode '123456'),
/// POST /v1/auth/phone/verify, DELETE /v1/auth/password/session,
/// DELETE /v1/me, PATCH /v1/me.
http.Client fakeSejiloBackend() {
  final users = <String, Map<String, dynamic>>{};

  return MockClient((request) async {
    final path = request.url.path;
    Map<String, dynamic>? body;
    if (request.body.isNotEmpty) {
      try {
        body = jsonDecode(request.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (path == '/v1/auth/phone/otp-requests' && request.method == 'POST') {
      return fakeJson({'devCode': '123456'});
    }

    if (path == '/v1/auth/phone/verify' && request.method == 'POST') {
      final email =
          '${(body!['username'] ?? 'phone_user')}@phone.sejilochat.net';
      final existing = users[email];
      if (existing != null) {
        return fakeJson({
          'id': existing['id'],
          'token': 'real.access.token.${existing['id']}',
          'refreshToken': 'real.refresh.token.${existing['id']}',
          'isNewUser': false,
          'profile': existing,
        });
      }
      final id = 'usr_${users.length + 1}';
      users[email] = fakeProfileJson(
        id: id,
        email: email,
        username: body['username'] as String? ?? 'phone_user',
        displayName: body['displayName'] as String? ?? 'Phone User',
      );
      return fakeJson({
        'id': id,
        'token': 'real.access.token.$id',
        'refreshToken': 'real.refresh.token.$id',
        'isNewUser': true,
        'profile': users[email],
      });
    }

    if (path == '/v1/users' && request.method == 'POST') {
      final email = (body!['email'] as String).toLowerCase();
      if (users.containsKey(email)) {
        return fakeJson({
          'message': 'Email or username is already in use.',
          'error': 'Conflict',
          'statusCode': 409,
        }, 409);
      }
      final id = 'usr_${users.length + 1}';
      users[email] = fakeProfileJson(
        id: id,
        email: email,
        username: body['username'] as String,
        displayName: body['displayName'] as String,
      );
      return fakeJson({
        'id': id,
        'token': 'real.access.token.$id',
        'refreshToken': 'real.refresh.token.$id',
        'isNewUser': true,
        'profile': users[email],
      }, 201);
    }

    if (path == '/v1/auth/password/login' && request.method == 'POST') {
      final email = (body!['email'] as String).toLowerCase();
      final user = users[email];
      if (user == null || body['password'] != 'Password123!') {
        return fakeJson({
          'message': 'Invalid email or password.',
          'error': 'Unauthorized',
          'statusCode': 401,
        }, 401);
      }
      return fakeJson({
        'id': user['id'],
        'token': 'real.access.token.${user['id']}',
        'refreshToken': 'real.refresh.token.${user['id']}',
        'isNewUser': false,
        'profile': user,
      });
    }

    if (path == '/v1/auth/google' && request.method == 'POST') {
      if (body == null || body['idToken'] != 'verified.google.id.token') {
        return fakeJson({
          'message':
              'Google token verification failed. Provide a valid idToken or accessToken.',
          'error': 'Unauthorized',
          'statusCode': 401,
        }, 401);
      }
      // The real server derives identity from the verified token and ignores
      // `email`/`googleId` in the body; the client only sends them when Google
      // reported them, so neither is guaranteed to be present.
      final email =
          (body['email'] as String? ?? 'google.user@example.com').toLowerCase();
      final existing = users[email];
      if (existing != null) {
        return fakeJson({
          'id': existing['id'],
          'token': 'real.access.token.${existing['id']}',
          'refreshToken': 'real.refresh.token.${existing['id']}',
          'isNewUser': false,
          'profile': existing,
        });
      }
      final id = 'usr_g_${users.length + 1}';
      users[email] = fakeProfileJson(
        id: id,
        email: email,
        username: email.split('@').first,
        displayName: body['displayName'] as String? ?? 'Google User',
      );
      return fakeJson({
        'id': id,
        'token': 'real.access.token.$id',
        'refreshToken': 'real.refresh.token.$id',
        'isNewUser': true,
        'profile': users[email],
      });
    }

    if (path == '/v1/auth/password/session' && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path == '/v1/me' && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path == '/v1/me' && request.method == 'PATCH') {
      final profile = users.values.first;
      profile['username'] = body!['username'] ?? profile['username'];
      profile['displayName'] = body['displayName'] ?? profile['displayName'];
      profile['bio'] = body['bio'] ?? profile['bio'];
      return fakeJson({'profile': profile});
    }

    if (path == '/v1/auth/password/reset-requests' && request.method == 'POST') {
      return fakeJson({'accepted': true});
    }

    if (path == '/v1/posts' && request.method == 'POST') {
      return fakeJson({
        'id': 'post-qa-001',
        'username': 'qa_tester',
        'displayName': 'QA Tester',
        'caption': body?['caption'] ?? 'QA Test Post',
        'createdAt': DateTime.now().toIso8601String(),
        'likes': 0,
        'comments': 0,
        'liked': false,
        'saved': false,
        'media': {'mimeType': 'image/jpeg', 'data': 'dGVzdA=='},
      }, 201);
    }

    if (path == '/v1/feed' && request.method == 'GET') {
      return fakeJson({
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
      });
    }

    if (path == '/v1/explore' && request.method == 'GET') {
      return fakeJson({
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
      });
    }

    if (RegExp(r'^/v1/users/[^/]+/posts$').hasMatch(path) &&
        request.method == 'GET') {
      return fakeJson({
        'posts': [
          {
            'id': 'post_user_1',
            'userId': 'usr-2',
            'username': 'followed_user',
            'displayName': 'Followed User',
            'caption': 'User profile post',
            'media': {'mimeType': 'image/jpeg', 'data': 'dGVzdA=='},
            'createdAt': DateTime.now().toIso8601String(),
            'likes': 2,
            'comments': 0,
            'liked': false,
            'saved': false,
          },
        ],
      });
    }

    // The viewer's bookmarks, as the real GET /v1/saved-posts answers them:
    // whole posts with `saved` already true, not a list of ids.
    if (path == '/v1/saved-posts' && request.method == 'GET') {
      return fakeJson({
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
      });
    }

    if (path.contains('/likes') || path.contains('/saves')) {
      return fakeJson({'success': true});
    }

    if (path == '/v1/notifications' && request.method == 'GET') {
      return fakeJson({
        'unreadCount': 2,
        'notifications': [
          {
            'id': 'ntf_1',
            'type': 'follow',
            'isRead': false,
            'createdAt': DateTime.now().toIso8601String(),
            'actor': {
              'id': 'usr-2',
              'username': 'bob',
              'displayName': 'Bob',
              'bio': '',
            },
          },
        ],
      });
    }

    if (path.contains('/v1/notifications/') && request.method == 'PATCH') {
      return fakeJson({'success': true});
    }

    if (path.contains('/v1/posts') && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path == '/v1/stories' && request.method == 'POST') {
      return fakeJson({
        'id': 'story-qa-001',
        'username': 'qa_tester',
        'displayName': 'QA Tester',
        'type': 'text',
        'textContent': body?['text'] ?? 'QA Live Story',
        'backgroundStyle': 'gradient_0',
        'createdAt': DateTime.now().toIso8601String(),
        'expiresAt':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'viewedByMe': false,
      }, 201);
    }

    // GET /v1/stories -> list of unexpired stories for self + following
    if (path == '/v1/stories' && request.method == 'GET') {
      return fakeJson({
        'stories': [
          {
            'id': 'story-qa-001',
            'userId': 'usr-2',
            'username': 'followed_user',
            'displayName': 'Followed User',
            'type': 'text',
            'textContent': 'A story from someone you follow',
            'backgroundStyle': 'gradient_0',
            'createdAt': DateTime.now().toIso8601String(),
            'expiresAt':
                DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
            'viewedByMe': false,
            'viewsCount': 3,
          },
        ],
      });
    }

    // POST /v1/stories/:id/views (mark viewed) and GET viewers
    final viewsMatch =
        RegExp(r'^/v1/stories/([^/]+)/views$').firstMatch(path);
    if (viewsMatch != null) {
      if (request.method == 'POST') {
        return http.Response('', 204);
      }
      if (request.method == 'GET') {
        return fakeJson({
          'viewers': [
            {
              'userId': 'usr-3',
              'username': 'viewer_user',
              'displayName': 'Viewer User',
              'viewedAt': DateTime.now().toIso8601String(),
            },
          ],
        });
      }
    }

    // DELETE /v1/stories/:id
    if (RegExp(r'^/v1/stories/[^/]+$').hasMatch(path) &&
        request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path.contains('/v1/chat/conversations/') && request.method == 'POST') {
      return fakeJson({
        'id': 'srv-msg-${DateTime.now().millisecondsSinceEpoch}',
        'conversationId': path.split('/').elementAt(4),
        'senderId': 'user-101',
        'senderUsername': 'qa_tester',
        'senderDisplayName': 'QA Tester',
        'text': body?['text'] ?? 'Test Message',
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
      }, 201);
    }

    if (path == '/v1/chat/messages' && request.method == 'POST') {
      return fakeJson({
        'message': {
          'id': 'srv-msg-${DateTime.now().millisecondsSinceEpoch}',
          'conversationId': 'conv-qa-direct',
          'senderId': 'user-101',
          'senderUsername': 'qa_tester',
          'senderDisplayName': 'QA Tester',
          'text': body?['text'] ?? 'Test Message',
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        },
      }, 201);
    }

    // ── Follow system ────────────────────────────
    // Note: the fake stores one authenticated session (the last registered user).
    // Follow endpoints use the stored profile's id as the follower for tests.
    final lastUser = users.values.isNotEmpty ? users.values.first : null;
    final followMatch = RegExp(r'^/v1/users/([^/]+)/follow$').firstMatch(path);
    if (followMatch != null && request.method == 'POST') {
      final targetName = followMatch.group(1)!;
      final target = users.values.firstWhere(
        (u) => u['username'] == targetName,
        orElse: () => <String, dynamic>{},
      );
      if (target.isEmpty) return fakeJson({'message': 'User not found'}, 404);
      if (lastUser != null && lastUser['id'] == target['id']) {
        return fakeJson({'message': 'Cannot follow yourself.'}, 400);
      }
      return fakeJson({
        'profile': {
          'id': target['id'],
          'username': target['username'],
          'displayName': target['displayName'],
          'bio': target['bio'] ?? '',
          'followersCount': 1,
          'followingCount': 0,
          'followedByViewer': true,
          'isFollowing': true,
        },
      });
    }
    if (followMatch != null && request.method == 'DELETE') {
      final target = users.values.firstWhere(
        (u) => u['username'] == followMatch.group(1)!,
        orElse: () => <String, dynamic>{},
      );
      if (target.isEmpty) return fakeJson({'message': 'User not found'}, 404);
      // Same full profile as the POST, and a 200 with a body — the server
      // answers DELETE .../follow the same way so the app can redraw the
      // button from the response.
      return fakeJson({
        'profile': {
          'id': target['id'],
          'username': target['username'],
          'displayName': target['displayName'],
          'bio': target['bio'] ?? '',
          'followersCount': 0,
          'followingCount': 0,
          'followedByViewer': false,
          'isFollowing': false,
        },
      });
    }

    final followersMatch =
        RegExp(r'^/v1/users/([^/]+)/followers$').firstMatch(path);
    if (followersMatch != null && request.method == 'GET') {
      final target = users.values.firstWhere(
        (u) =>
            u['id'] == followersMatch.group(1)! ||
            u['username'] == followersMatch.group(1)!,
        orElse: () => <String, dynamic>{},
      );
      if (target.isEmpty) return fakeJson({'followers': []});
      return fakeJson({
        'followers': [
          {'id': lastUser?['id'] ?? '', 'username': lastUser?['username'] ?? ''}
        ],
      });
    }

    final followingMatch =
        RegExp(r'^/v1/users/([^/]+)/following$').firstMatch(path);
    if (followingMatch != null && request.method == 'GET') {
      final followerId = followingMatch.group(1)!;
      if (lastUser != null &&
          (lastUser['id'] == followerId || lastUser['username'] == followerId)) {
        return fakeJson({
          'following': [
            {'id': 'user-2', 'username': 'followed_user'}
          ],
        });
      }
      return fakeJson({'following': []});
    }

    // ── Likes & comments ────────────────────────
    if (path.contains('/v1/posts/') && request.method == 'POST' && path.contains('/likes')) {
      return fakeJson({'success': true, 'liked': true});
    }
    if (path.contains('/v1/posts/') && request.method == 'DELETE' && path.contains('/likes')) {
      return fakeJson({'success': true, 'liked': false});
    }
    if (path.contains('/v1/posts/') && request.method == 'POST' && path.contains('/comments')) {
      return fakeJson({
        'id': 'comment-${DateTime.now().millisecondsSinceEpoch}',
        'text': body?['text'] ?? '',
        'username': lastUser?['username'] ?? 'tester',
      }, 201);
    }
    if (path.contains('/v1/posts/') && request.method == 'GET' && path.contains('/comments')) {
      return fakeJson({'comments': []});
    }
    if (path.contains('/v1/comments/') && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    return fakeJson({'message': 'Not found', 'statusCode': 404}, 404);
  });
}