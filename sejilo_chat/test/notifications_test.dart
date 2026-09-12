import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('STEP 13 — Notifications', () {
    test('loadNotifications parses list; mark one read + mark all read', () async {
      bool singleRead = false;
      bool allRead = false;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path == '/v1/notifications') {
          return http.Response(
            jsonEncode({
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
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'PATCH' && path == '/v1/notifications/ntf_1') {
          singleRead = true;
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (req.method == 'POST' && path == '/v1/notifications/read') {
          allRead = true;
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final auth = AccountAuthController(client: client);
      final notifs = await auth.loadNotifications();
      expect(notifs.length, equals(1));
      expect(auth.unreadNotificationsCount, equals(2));

      await auth.markNotificationRead('ntf_1');
      expect(singleRead, isTrue);

      await auth.markNotificationsRead();
      expect(allRead, isTrue);
      expect(auth.unreadNotificationsCount, equals(0));
    });
  });
}
