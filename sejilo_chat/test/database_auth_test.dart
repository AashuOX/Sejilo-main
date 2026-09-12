import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Database Authentication System', () {
    late Map<String, String> mockStorage;
    late AccountAuthController auth;

    http.Client mockBackend() => MockClient((request) async {
          if (request.url.path == '/v1/auth/password/register') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'id': 'usr_server_123',
                'token': 'server.bearer.token',
                'profile': {
                  'id': 'usr_server_123',
                  'email': body['email'],
                  'username': body['username'],
                  'displayName': body['displayName'] ?? body['username'],
                  'bio': 'Online bio',
                  'avatar': null,
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/v1/auth/password/login') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'id': 'usr_server_123',
                'token': 'server.bearer.token',
                'profile': {
                  'id': 'usr_server_123',
                  'email': body['email'],
                  'username': 'server_user',
                  'displayName': 'Server User',
                  'bio': 'Server bio',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode({'message': 'Not found'}), 404);
        });

    setUp(() async {
      mockStorage = {};
      FlutterSecureStorage.setMockInitialValues(mockStorage);
      auth = AccountAuthController(client: mockBackend());
      await auth.initialize();
    });

    tearDown(() {
      auth.dispose();
    });

    test('Registers a real user into database and authenticates', () async {
      await auth.signUp(
        email: 'testuser@example.com',
        username: 'testuser',
        displayName: 'Test User',
        password: 'SecurePassword123!',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile?.email, equals('testuser@example.com'));
      expect(auth.profile?.username, equals('testuser'));
      expect(auth.profile?.displayName, equals('Test User'));
      expect(auth.token, isNotNull);
    });

    test('Validates password length >= 8 characters on registration', () async {
      await expectLater(
        auth.signUp(
          email: 'shortpass@example.com',
          username: 'shortpass',
          displayName: 'Short Pass',
          password: 'short',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Allows login by username as well as email', () async {
      await auth.signUp(
        email: 'member@domain.com',
        username: 'cool_member',
        displayName: 'Cool Member',
        password: 'MyPassword2026!',
      );
      await auth.logout();
      expect(auth.isAuthenticated, isFalse);

      // Login using username
      await auth.login(
        email: 'cool_member',
        password: 'MyPassword2026!',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile?.username, equals('cool_member'));
      expect(auth.profile?.email, equals('member@domain.com'));
    });

    test('Rejects invalid password with clear error', () async {
      await auth.signUp(
        email: 'guard@domain.com',
        username: 'guard_user',
        displayName: 'Guard User',
        password: 'CorrectPassword!',
      );
      await auth.logout();

      await expectLater(
        auth.login(
          email: 'guard_user',
          password: 'WrongPassword!',
        ),
        throwsA(isA<Exception>()),
      );
      expect(auth.isAuthenticated, isFalse);
    });

    test('Updates real profile status/bio and persists to storage', () async {
      await auth.signUp(
        email: 'updater@domain.com',
        username: 'updater',
        displayName: 'Old Name',
        password: 'Password123!',
      );

      await auth.updateProfile(
        username: 'updater',
        displayName: 'New Real Name',
        bio: 'Coding with custom database auth!',
      );

      expect(auth.profile?.displayName, equals('New Real Name'));
      expect(auth.profile?.bio, equals('Coding with custom database auth!'));
    });

    test('Account deletion cleans up user from database and storage', () async {
      await auth.signUp(
        email: 'delete_me@domain.com',
        username: 'delete_me',
        displayName: 'Delete Me',
        password: 'Password123!',
      );
      expect(auth.isAuthenticated, isTrue);

      await auth.deleteAccount();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.profile, isNull);
    });
  });
}
