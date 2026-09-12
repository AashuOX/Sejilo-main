import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/core/image_utils.dart';
import 'package:sejilo_chat/core/platform_capabilities.dart';
import 'package:sejilo_chat/messaging/messaging.dart';
import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock FlutterSecureStorage channel
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'write') {
      final key = call.arguments['key'] as String;
      final value = call.arguments['value'] as String?;
      if (value != null) {
        store[key] = value;
      }
      return null;
    } else if (call.method == 'read') {
      final key = call.arguments['key'] as String;
      return store[key];
    } else if (call.method == 'delete') {
      final key = call.arguments['key'] as String;
      store.remove(key);
      return null;
    } else if (call.method == 'deleteAll') {
      store.clear();
      return null;
    }
    return null;
  });

  group('PlatformCapabilities Tests', () {
    test('reports valid platform name', () {
      expect(PlatformCapabilities.platformName.isNotEmpty, isTrue);
    });
  });

  group('Online Messaging Controller Tests', () {
    test('initializes with zero unread when unauthenticated', () {
      final auth = AccountAuthController();
      final messaging = OnlineMessagingController(auth: auth);

      expect(messaging.conversations.isEmpty, isTrue);
      expect(messaging.totalUnreadCount, 0);

      messaging.dispose();
      auth.dispose();
    });

    test('online message model serializes and deserializes correctly', () {
      final now = DateTime.now();
      final msg = OnlineMessage(
        id: 'msg-123',
        conversationId: 'conv-test',
        senderId: 'user-1',
        senderUsername: 'alice',
        senderDisplayName: 'Alice W',
        text: 'Hello Sejilo!',
        createdAt: now,
        isMe: true,
        status: MessageDeliveryStatus.delivered,
      );

      expect(msg.id, 'msg-123');
      expect(msg.isMe, isTrue);
      expect(msg.text, 'Hello Sejilo!');
      expect(msg.status, MessageDeliveryStatus.delivered);

      final copy = msg.copyWith(text: 'Updated message');
      expect(copy.text, 'Updated message');
      expect(copy.id, 'msg-123');
    });

    test('online conversation model unread tracking works', () {
      final user = PublicProfile(
        id: 'user-2',
        username: 'bob',
        displayName: 'Bob M',
        bio: 'Tester',
        followersCount: 10,
        followingCount: 5,
        followedByViewer: false,
      );

      final conv = OnlineConversation(
        id: 'conv-bob',
        participant: user,
        unreadCount: 3,
        updatedAt: DateTime.now(),
      );

      expect(conv.unreadCount, 3);
      expect(conv.participant.username, 'bob');

      final updated = conv.copyWith(unreadCount: 0);
      expect(updated.unreadCount, 0);
    });

    test('message reactions and replies serialize properly', () {
      final msg = OnlineMessage(
        id: 'msg-456',
        conversationId: 'conv-test',
        senderId: 'user-1',
        senderUsername: 'alice',
        senderDisplayName: 'Alice W',
        text: 'What do you think?',
        replyToMessageId: 'msg-123',
        reactions: const [MessageReaction(userId: 'user-2', emoji: '🔥')],
        createdAt: DateTime.now(),
        isMe: true,
        status: MessageDeliveryStatus.read,
      );

      expect(msg.replyToMessageId, 'msg-123');
      expect(msg.reactions.length, 1);
      expect(msg.reactions.first.emoji, '🔥');
      expect(msg.status, MessageDeliveryStatus.read);
    });

    test('start conversation and send message updates local conversation state', () async {
      final auth = AccountAuthController(client: fakeSejiloBackend());
      final code = await auth.sendPhoneOtp('+15550001111');
      await auth.verifyPhoneOtp(
        phoneNumber: '+15550001111',
        otp: code,
        username: 'chatter',
        displayName: 'Chatter User',
      );

      final messaging = OnlineMessagingController(auth: auth);
      final partner = PublicProfile(
        id: 'user-partner',
        username: 'partner_user',
        displayName: 'Partner User',
      );

      final conv = await messaging.startConversationWith(partner);
      expect(conv.participant.username, 'partner_user');

      await messaging.sendMessage(
        conversationId: conv.id,
        text: 'Hello from real-time messaging!',
      );

      final msgs = messaging.getMessages(conv.id);
      expect(msgs.isNotEmpty, isTrue);
      expect(msgs.first.text, 'Hello from real-time messaging!');
      expect(msgs.first.isMe, isTrue);

      await messaging.addReaction(msgs.first.id, '❤️');
      final updatedMsgs = messaging.getMessages(conv.id);
      expect(updatedMsgs.first.reactions.any((r) => r.emoji == '❤️'), isTrue);

      await messaging.deleteMessage(conv.id, msgs.first.id);
      expect(messaging.getMessages(conv.id).isEmpty, isTrue);

      messaging.dispose();
      auth.dispose();
    });
  });

  group('Account Auth Controller Phone & Google Login Tests', () {
    test('sendPhoneOtp requests a server-issued 6-digit dev code', () async {
      final auth = AccountAuthController(client: fakeSejiloBackend());
      final code = await auth.sendPhoneOtp('+1 (555) 123-4567');

      expect(code.length, 6);
      expect(auth.pendingPhoneNumber, '+15551234567');
      auth.dispose();
    });

    test('verifyPhoneOtp successfully authenticates user and sets profile', () async {
      final auth = AccountAuthController(client: fakeSejiloBackend());
      final code = await auth.sendPhoneOtp('+15551234567');
      await auth.verifyPhoneOtp(
        phoneNumber: '+15551234567',
        otp: code,
        username: 'test_phone_user',
        displayName: 'Test Phone User',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile, isNotNull);
      expect(auth.profile!.username, 'test_phone_user');
      expect(auth.profile!.displayName, 'Test Phone User');
      expect(auth.token, startsWith('real.access.token.'));
      auth.dispose();
    });

    test('Database signup and login authenticates user', () async {
      final auth = AccountAuthController(client: fakeSejiloBackend());
      await auth.signUp(
        email: 'sarah.connor@gmail.com',
        username: 'sarah_c',
        displayName: 'Sarah Connor',
        password: 'Password123!',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile, isNotNull);
      expect(auth.profile!.email, 'sarah.connor@gmail.com');
      expect(auth.profile!.displayName, 'Sarah Connor');
      auth.dispose();
    });

    test('login with non-existent user is rejected', () async {
      final auth = AccountAuthController(client: fakeSejiloBackend());
      await expectLater(
        auth.login(email: 'nobody@gmail.com', password: 'Password123!'),
        throwsA(isA<Exception>()),
      );
      expect(auth.isAuthenticated, isFalse);
      auth.dispose();
    });
  });

  group('ImageUtils & Large Photo Handling Tests', () {
    test('undecodable bytes are handed back untouched instead of throwing',
        () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await ImageUtils.optimizeImage(garbage);
      expect(result.bytes.length, 5);
      // Nothing recognisable, so no image MIME type may be claimed for it.
      expect(result.mimeType, 'application/octet-stream');
    });

    test('a small in-bounds image keeps its bytes and its real MIME type',
        () async {
      final source = img.Image(width: 120, height: 90);
      img.fill(source, color: img.ColorRgb8(20, 120, 220));
      final png = Uint8List.fromList(img.encodePng(source));

      final result = await ImageUtils.optimizeImage(png);

      // Re-encoding this would only make it bigger, and would flatten an
      // animated GIF or WebP that arrived by the same path.
      expect(result.bytes, equals(png));
      expect(result.mimeType, 'image/png');
    });

    test('an out-of-bounds photo is downscaled and re-encoded as JPEG',
        () async {
      // 2400x1800 — a modest camera resolution, far past the 1080 feed limit.
      final source = img.Image(width: 2400, height: 1800);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }
      final png = Uint8List.fromList(img.encodePng(source));

      final result = await ImageUtils.optimizeImage(png);

      expect(result.mimeType, 'image/jpeg');
      expect(result.bytes.length,
          lessThanOrEqualTo(ImageUtils.maxTargetSizeBytes));

      final decoded = img.decodeImage(result.bytes)!;
      // Landscape, so the width is pinned and the height follows the ratio.
      expect(decoded.width, ImageUtils.maxPostDimension);
      expect(decoded.height, 810); // 1800 * (1080 / 2400)
    });

    test('a file over the byte ceiling is compressed down to fit', () async {
      // Pseudo-random pixels so PNG cannot compress them away — this is the
      // case the old PNG-only encoder made worse instead of better.
      final source = img.Image(width: 1000, height: 1000);
      var seed = 12345;
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          source.setPixelRgb(x, y, seed & 0xff, (seed >> 8) & 0xff, (seed >> 16) & 0xff);
        }
      }
      final png = Uint8List.fromList(img.encodePng(source));
      // Within the dimension limit, but well over the byte limit — the exact
      // shape that used to be waved through untouched and then rejected.
      expect(png.length, greaterThan(ImageUtils.maxTargetSizeBytes));

      final result = await ImageUtils.optimizeImage(png);

      expect(result.mimeType, 'image/jpeg');
      expect(result.bytes.length, lessThan(png.length));
      expect(result.bytes.length,
          lessThanOrEqualTo(ImageUtils.maxTargetSizeBytes));
    });

    test('avatars are held to the smaller avatar dimension', () async {
      final source = img.Image(width: 1600, height: 1600);
      img.fill(source, color: img.ColorRgb8(200, 40, 90));
      final png = Uint8List.fromList(img.encodePng(source));

      final result = await ImageUtils.optimizeImage(
        png,
        maxDimension: ImageUtils.maxAvatarDimension,
      );

      final decoded = img.decodeImage(result.bytes)!;
      expect(decoded.width, lessThanOrEqualTo(ImageUtils.maxAvatarDimension));
      expect(decoded.height, lessThanOrEqualTo(ImageUtils.maxAvatarDimension));
    });

    test('constants stay inside the API media ceiling', () {
      expect(ImageUtils.maxPostDimension, 1080);
      expect(ImageUtils.maxAvatarDimension, 512);
      expect(ImageUtils.maxTargetSizeBytes, 1500 * 1024);
      // base64url costs 4 bytes per 3, and the server caps the encoded string
      // at 3 MB (MAX_MEDIA_BASE64_LENGTH). Anything the optimiser emits has to
      // still fit after that inflation.
      expect((ImageUtils.maxTargetSizeBytes * 4 / 3).ceil(),
          lessThan(3 * 1024 * 1024));
    });
  });
}
