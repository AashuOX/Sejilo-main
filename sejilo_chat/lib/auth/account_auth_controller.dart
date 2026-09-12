import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';
import '../core/app_preferences.dart';
import '../core/image_utils.dart';

// ─────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────

class StoredUserAccount {
  const StoredUserAccount({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    required this.salt,
    this.bio = 'Hey there! I am using SejiloChat.',
    this.avatarMimeType,
    this.avatarBytes,
    this.birthDate,
    this.isPrivate = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String passwordHash;
  final String salt;
  final String bio;
  final String? avatarMimeType;
  final Uint8List? avatarBytes;
  final DateTime? birthDate;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  AccountProfile toProfile() => AccountProfile(
        id: id,
        email: email,
        username: username,
        displayName: displayName,
        bio: bio,
        avatarMimeType: avatarMimeType,
        avatarBytes: avatarBytes,
        birthDate: birthDate,
        isPrivate: isPrivate,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'displayName': displayName,
        'passwordHash': passwordHash,
        'salt': salt,
        'bio': bio,
        'avatarMimeType': avatarMimeType,
        'avatar': avatarBytes != null && avatarMimeType != null
            ? {
                'mimeType': avatarMimeType,
                'data': base64Url.encode(avatarBytes!).replaceAll('=', ''),
              }
            : null,
        if (birthDate != null) 'birthDate': birthDate!.toIso8601String(),
        'isPrivate': isPrivate,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StoredUserAccount.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    DateTime? birthDate;
    if (json['birthDate'] != null) {
      try {
        birthDate = DateTime.parse(json['birthDate'] as String);
      } catch (_) {}
    }
    return StoredUserAccount(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      passwordHash: json['passwordHash'] as String? ?? '',
      salt: json['salt'] as String? ?? '',
      bio: json['bio'] as String? ?? 'Hey there! I am using SejiloChat.',
      avatarMimeType:
          json['avatarMimeType'] as String? ?? avatar?['mimeType'] as String?,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      birthDate: birthDate,
      isPrivate: json['isPrivate'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  StoredUserAccount copyWith({
    String? username,
    String? displayName,
    String? bio,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    DateTime? birthDate,
    bool? isPrivate,
    bool clearAvatar = false,
  }) {
    return StoredUserAccount(
      id: id,
      email: email,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      passwordHash: passwordHash,
      salt: salt,
      bio: bio ?? this.bio,
      avatarBytes: clearAvatar ? null : (avatarBytes ?? this.avatarBytes),
      avatarMimeType: clearAvatar ? null : (avatarMimeType ?? this.avatarMimeType),
      birthDate: birthDate ?? this.birthDate,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarMimeType,
    this.avatarBytes,
    this.birthDate,
    this.isPrivate = false,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarMimeType;
  final Uint8List? avatarBytes;
  final DateTime? birthDate;

  /// Account privacy, as the server sees it.
  ///
  /// Enforced in the backend (follows, search, recommendations), so this is a
  /// mirror of server state rather than a client-side preference.
  final bool isPrivate;

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    DateTime? birthDate;
    if (json['birthDate'] != null) {
      try {
        birthDate = DateTime.parse(json['birthDate'] as String);
      } catch (_) {}
    }
    return AccountProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      bio: json['bio'] as String,
      avatarMimeType: avatar?['mimeType'] as String?,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      birthDate: birthDate,
      isPrivate: json['isPrivate'] as bool? ?? false,
    );
  }
}

class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.followedByViewer = false,
    this.followRequestPending = false,
    this.mutedByViewer = false,
    this.blockedByViewer = false,
    this.isPrivate = false,
    this.avatarMimeType,
    this.avatarBytes,
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final bool followedByViewer;
  final bool followRequestPending;

  /// From the viewer's own block row only. A muted account still reaches the
  /// viewer's inbox; a blocked one does not. The server never reports the
  /// reverse direction, so nobody can tell that *they* have been blocked.
  final bool mutedByViewer;
  final bool blockedByViewer;

  /// Whether this account has "Private account" turned on. The server refuses
  /// `GET /v1/users/:username/posts` with 403 for anyone who is not an accepted
  /// follower, so this is what lets the grid say why instead of asking and
  /// showing the error.
  final bool isPrivate;
  final String? avatarMimeType;
  final Uint8List? avatarBytes;

  /// Parses any of the account shapes the server returns.
  ///
  /// `displayName` and `bio` are read leniently because not every shape carries
  /// them: a notification's `actor` object has no `bio` at all, so the previous
  /// hard cast threw "type 'Null' is not a subtype of type 'String'" and took
  /// down the whole notification list. Only `id` and `username` stay strict —
  /// they drive navigation and further API calls, so a response without them is
  /// a broken contract rather than a sparse one.
  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return PublicProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      followersCount: json['followersCount'] as int? ?? 0,
      followingCount: json['followingCount'] as int? ?? 0,
      postsCount: json['postsCount'] as int? ?? 0,
      followedByViewer: json['followedByViewer'] as bool? ?? false,
      followRequestPending: json['followRequestPending'] as bool? ?? false,
      mutedByViewer: json['mutedByViewer'] as bool? ?? false,
      blockedByViewer: json['blockedByViewer'] as bool? ?? false,
      isPrivate: json['isPrivate'] as bool? ?? false,
      avatarMimeType: avatar?['mimeType'] as String?,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
    );
  }
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.caption,
    required this.media,
    required this.createdAt,
    required this.likes,
    required this.comments,
    required this.liked,
    this.saved = false,
    this.avatarBytes,
  });

  final String id, userId, username, displayName, caption;
  final Uint8List media;
  final DateTime createdAt;
  final int likes, comments;
  final bool liked;
  final bool saved;
  final Uint8List? avatarBytes;

  factory SocialPost.fromJson(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>;
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return SocialPost(
      id: json['id'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      caption: json['caption'] as String,
      media: Uint8List.fromList(
          base64Url.decode(base64Url.normalize(media['data'] as String))),
      createdAt: DateTime.parse(json['createdAt'] as String),
      likes: json['likes'] as int? ?? 0,
      comments: json['comments'] as int? ?? 0,
      liked: json['liked'] as bool? ?? false,
      saved: json['saved'] as bool? ?? false,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'caption': caption,
        'media': {
          'mimeType': 'image/jpeg',
          'data': base64Url.encode(media).replaceAll('=', ''),
        },
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'comments': comments,
        'liked': liked,
        'saved': saved,
        if (avatarBytes != null)
          'avatar': {
            'mimeType': 'image/png',
            'data': base64Url.encode(avatarBytes!).replaceAll('=', ''),
          },
      };
}

class PostComment {
  const PostComment({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.text,
    required this.createdAt,
    this.avatarBytes,
  });

  final String id, userId, username, displayName, text;
  final DateTime createdAt;
  final Uint8List? avatarBytes;

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return PostComment(
      id: json['id'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Paginated feed result.
class FeedPage {
  const FeedPage({required this.posts, this.nextCursor});
  final List<SocialPost> posts;
  final String? nextCursor;
}

enum StoryType { image, text }

class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarBytes,
    required this.type,
    this.mediaBytes,
    this.textContent,
    this.backgroundStyle,
    required this.createdAt,
    required this.expiresAt,
    this.viewedByMe = false,
    this.viewsCount = 0,
  });

  final String id;
  final String userId;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;
  final StoryType type;
  final Uint8List? mediaBytes;
  final String? textContent;
  final String? backgroundStyle;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewedByMe;
  final int viewsCount;

  Uint8List? get thumbnailBytes => mediaBytes;
  Uint8List get media => mediaBytes ?? Uint8List(0);

  factory Story.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    final media = (json['media'] ?? json['thumbnail']) as Map<String, dynamic>?;
    final typeStr = json['type'] as String? ?? 'image';
    return Story(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      type: typeStr == 'text' ? StoryType.text : StoryType.image,
      mediaBytes: media == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(media['data'] as String))),
      textContent: json['textContent'] as String?,
      backgroundStyle: json['backgroundStyle'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      viewedByMe: json['viewedByMe'] as bool? ?? false,
      viewsCount: json['viewsCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'type': type == StoryType.text ? 'text' : 'image',
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'viewedByMe': viewedByMe,
        'viewsCount': viewsCount,
        if (textContent != null) 'textContent': textContent,
        if (backgroundStyle != null) 'backgroundStyle': backgroundStyle,
        if (mediaBytes != null)
          'media': {
            'mimeType': 'image/jpeg',
            'data': base64Url.encode(mediaBytes!).replaceAll('=', ''),
          },
      };
}

class UserStoryGroup {
  const UserStoryGroup({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarBytes,
    required this.stories,
  });

  final String userId;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;
  final List<Story> stories;

  bool get hasUnseenStory => stories.any((s) => !s.viewedByMe);
}

class StoryViewerInfo {
  const StoryViewerInfo({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarBytes,
    required this.viewedAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;
  final DateTime viewedAt;

  factory StoryViewerInfo.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return StoryViewerInfo(
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      viewedAt: DateTime.parse(json['viewedAt'] as String),
    );
  }
}

/// A person this account has muted.
///
/// Muting is stored server-side as a `Block` row carrying an `isMuted` flag, so
/// the list comes back from `/v1/users/muted` rather than being kept on device.
class MutedUser {
  const MutedUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarBytes,
    required this.mutedAt,
  });

  final String id;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;
  final DateTime mutedAt;

  factory MutedUser.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return MutedUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['username'] as String? ?? '',
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      mutedAt: DateTime.tryParse(json['mutedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// A person this account has fully blocked.
///
/// Same `Block` table as [MutedUser], but with `isMuted: false`; the server
/// keeps the two lists apart, so a blocked person never shows up as muted.
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarBytes,
    required this.blockedAt,
  });

  final String id;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    return BlockedUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['username'] as String? ?? '',
      avatarBytes: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      blockedAt: DateTime.tryParse(json['blockedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// One report this account has filed, as the server recorded it.
///
/// The server never returns anyone else's reports, so this is a personal
/// history: what you flagged, and whether a moderator has closed it yet.
class FiledReport {
  const FiledReport({
    required this.id,
    required this.targetType,
    required this.reason,
    this.details,
    required this.status,
    required this.createdAt,
    this.targetLabel,
    this.targetName,
    this.targetDeleted = false,
  });

  final String id;

  /// `user` or `post` — the server's own vocabulary for what was reported.
  final String targetType;
  final String reason;
  final String? details;

  /// `pending`, `resolved` or `dismissed`.
  final String status;
  final DateTime createdAt;

  /// `@username` for an account, or the caption for a post. Null when the
  /// target has been deleted since.
  final String? targetLabel;
  final String? targetName;
  final bool targetDeleted;

  bool get isOpen => status == 'pending';

  factory FiledReport.fromJson(Map<String, dynamic> json) => FiledReport(
        id: json['id'] as String? ?? '',
        targetType: json['targetType'] as String? ?? 'user',
        reason: json['reason'] as String? ?? 'Reported',
        details: json['details'] as String?,
        status: json['status'] as String? ?? 'pending',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        targetLabel: json['targetLabel'] as String?,
        targetName: json['targetName'] as String?,
        targetDeleted: json['targetDeleted'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────
// Notification model
// ─────────────────────────────────────────────

enum NotificationType { like, comment, follow, message, meshMessage }

class SocialNotification {
  const SocialNotification({
    required this.id,
    required this.type,
    this.text,
    this.read = false,
    this.isRead = false,
    required this.createdAt,
    this.referenceId,
    this.postId,
    this.actor,
    this.postMediaBytes,
  });

  final String id;
  final NotificationType type;
  final String? text;
  final bool read;
  final bool isRead;
  final DateTime createdAt;
  final String? referenceId;
  final String? postId;
  final PublicProfile? actor;
  final Uint8List? postMediaBytes;

  factory SocialNotification.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'message';
    final type = switch (typeStr) {
      'like' => NotificationType.like,
      'comment' => NotificationType.comment,
      'follow' => NotificationType.follow,
      'message' => NotificationType.message,
      'mesh_message' => NotificationType.meshMessage,
      _ => NotificationType.message,
    };
    final isReadVal = (json['isRead'] ?? json['read']) as bool? ?? false;
    final actorJson = json['actor'] as Map<String, dynamic>?;
    final postMedia = json['postMedia'] as Map<String, dynamic>?;

    return SocialNotification(
      id: json['id'] as String,
      type: type,
      text: json['text'] as String?,
      read: isReadVal,
      isRead: isReadVal,
      createdAt: DateTime.parse(json['createdAt'] as String),
      referenceId: json['referenceId'] as String?,
      postId: json['postId'] as String?,
      actor: actorJson != null ? PublicProfile.fromJson(actorJson) : null,
      postMediaBytes: postMedia == null
          ? null
          : Uint8List.fromList(base64Url
              .decode(base64Url.normalize(postMedia['data'] as String))),
    );
  }
}

// ─────────────────────────────────────────────
// AccountAuthController
// ─────────────────────────────────────────────

/// Persistent account session for profile/social features. This deliberately
/// does not replace the existing local Ed25519 device identity used by BLE.
class AccountAuthController extends ChangeNotifier {
  AccountAuthController({
    FlutterSecureStorage? storage,
    http.Client? client,
    AppPreferences? preferences,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client(),
        _preferences = preferences;

  static const _serverUrlKey = 'account.server.base_url.v1';
  static const _tokenKey = 'account.session.token.v1';
  static const _profileKey = 'account.session.profile.v1';
  static const _usersDatabaseKey = 'account.database.users.v1';
  static const _postsKey = 'account.posts.local.v1';
  static const _storiesKey = 'account.stories.local.v1';
  static const _commentsKey = 'account.comments.local.v1';
  static const _followingKey = 'account.following.local.v1';
  static const _likesKey = 'account.likes.local.v1';
  static const _savedPostsKey = 'account.saved_posts.local.v1';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  /// Device settings, when the app supplied them.
  ///
  /// Optional so tests can build the controller bare; the only thing it changes
  /// is the size media is uploaded at.
  final AppPreferences? _preferences;
  String? _customBaseUrl;
  String? _token;
  AccountProfile? _profile;
  bool _ready = false;
  bool _busy = false;
  String? _error;
  String? _pendingPhoneNumber;

  final List<SocialPost> _localPosts = [];
  final List<Story> _localStories = [];
  final Map<String, List<PostComment>> _localComments = {};
  final Set<String> _followingUsernames = {};
  final Set<String> _likedPostIds = {};
  final Set<String> _savedPostIds = {};
  final List<SocialNotification> _notifications = [];
  int _unreadNotificationsCount = 0;

  bool get isReady => _ready;
  bool get isBusy => _busy;
  bool get isAuthenticated => _profile != null && _token != null;
  String? get token => _token;
  AccountProfile? get profile => _profile;
  String? get currentUserId => _profile?.id;
  String? get currentUsername => _profile?.username;
  List<SocialPost> get posts => List.unmodifiable(_localPosts);
  List<SocialNotification> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotificationsCount => _unreadNotificationsCount;
  Set<String> get savedPostIds => Set.unmodifiable(_savedPostIds);
  String? get error => _error;
  /// The backend this install talks to: the address saved in Settings → Server
  /// if there is one, otherwise whatever [ApiConfig] resolves to.
  String get baseUrl => _customBaseUrl != null && _customBaseUrl!.isNotEmpty
      ? _customBaseUrl!
      : ApiConfig.baseUrl;
  bool get isConfigured => true;
  String? get pendingPhoneNumber => _pendingPhoneNumber;

  /// Longest edge photos are uploaded at.
  ///
  /// Follows the device's "highest quality uploads" setting; with it off, posts
  /// and stories are sent at a smaller size to save mobile data.
  int get _uploadDimension => (_preferences?.highQualityUploads ?? true)
      ? ImageUtils.maxPostDimension
      : ImageUtils.dataSaverPostDimension;

  Future<void> updateBaseUrl(String url) async {
    _customBaseUrl = url.trim();
    await _storage.write(key: _serverUrlKey, value: _customBaseUrl);
    notifyListeners();
  }

  Future<int?> testServerConnection([String? testUrl]) async =>
      (await probeServer(testUrl)).latencyMs;

  /// Asks the API base URL what it really is.
  ///
  /// Only a 2xx from `/health` counts as a SejiloChat server. The old version
  /// accepted any status below 500 and, failing that, any status below 500 from
  /// `/` — so a hostname with nothing deployed reported "Server OK", because
  /// Render's edge answers 404 (`x-render-routing: no-server`) for a service
  /// that does not exist.
  Future<ServerProbe> probeServer([String? testUrl]) async {
    final target = (testUrl ?? baseUrl).trim();
    final start = DateTime.now();
    http.Response health;
    try {
      health = await _client
          .get(Uri.parse(target).resolve('/health'))
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      // Six seconds is right for a host that is simply wrong — DNS fails or the
      // connection is refused long before that. It is not enough for a free-tier
      // host that has been idle: the container is stopped and takes about a
      // minute to come back, and calling that "unreachable" is the same lie the
      // old any-status-under-500 check told, in the other direction.
      try {
        health = await _client
            .get(Uri.parse(target).resolve('/health'))
            .timeout(const Duration(seconds: 65));
      } on Object {
        return const ServerProbe(
          reachable: false,
          databaseReady: false,
          detail: 'Server unreachable',
        );
      }
    } on Object {
      // Bad URL, DNS failure, refused connection or timeout — all the same to
      // the person reading the chip.
      return const ServerProbe(
        reachable: false,
        databaseReady: false,
        detail: 'Server unreachable',
      );
    }
    final ms = DateTime.now().difference(start).inMilliseconds;
    if (health.statusCode < 200 || health.statusCode >= 300) {
      return ServerProbe(
        reachable: false,
        databaseReady: false,
        detail: 'No SejiloChat server here (HTTP ${health.statusCode})',
      );
    }

    // `/health` answers from the process alone; `/health/ready` is the one that
    // runs SELECT 1. Without a database nothing can sign in, so a server that
    // is up but not ready has to read differently from one that works.
    try {
      final ready = await _client
          .get(Uri.parse(target).resolve('/health/ready'))
          .timeout(const Duration(seconds: 6));
      final ok = ready.statusCode >= 200 && ready.statusCode < 300;
      return ServerProbe(
        reachable: true,
        databaseReady: ok,
        latencyMs: ms,
        detail: ok
            ? 'Server ready (${ms}ms)'
            : 'Server up, database unavailable',
      );
    } on Object {
      return ServerProbe(
        reachable: true,
        databaseReady: false,
        latencyMs: ms,
        detail: 'Server up, readiness unknown',
      );
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      try {
        await _storage.delete(key: key);
        await _storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  Future<void> initialize() async {
    _token = await _safeRead(_tokenKey);
    final savedProfileJson = await _safeRead(_profileKey);
    if (savedProfileJson != null) {
      try {
        _profile = AccountProfile.fromJson(
            jsonDecode(savedProfileJson) as Map<String, dynamic>);
      } catch (_) {}
    }

    // Load local posts
    final savedPostsJson = await _safeRead(_postsKey);
    if (savedPostsJson != null) {
      try {
        final list = jsonDecode(savedPostsJson) as List<dynamic>;
        _localPosts.clear();
        _localPosts.addAll(
            list.map((e) => SocialPost.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }

    // Load local stories
    final savedStoriesJson = await _safeRead(_storiesKey);
    if (savedStoriesJson != null) {
      try {
        final list = jsonDecode(savedStoriesJson) as List<dynamic>;
        _localStories.clear();
        final now = DateTime.now();
        _localStories.addAll(
          list
              .map((e) => Story.fromJson(e as Map<String, dynamic>))
              .where((s) => s.expiresAt.isAfter(now)),
        );
      } catch (_) {}
    }

    // Load following
    final savedFollowing = await _safeRead(_followingKey);
    if (savedFollowing != null) {
      try {
        final list = jsonDecode(savedFollowing) as List<dynamic>;
        _followingUsernames.clear();
        _followingUsernames.addAll(list.cast<String>());
      } catch (_) {}
    }

    // Load likes
    final savedLikes = await _safeRead(_likesKey);
    if (savedLikes != null) {
      try {
        final list = jsonDecode(savedLikes) as List<dynamic>;
        _likedPostIds.clear();
        _likedPostIds.addAll(list.cast<String>());
      } catch (_) {}
    }

    // Load saved posts
    final savedPosts = await _safeRead(_savedPostsKey);
    if (savedPosts != null) {
      try {
        final list = jsonDecode(savedPosts) as List<dynamic>;
        _savedPostIds.clear();
        _savedPostIds.addAll(list.cast<String>());
      } catch (_) {}
    }

    // Load comments
    final savedComments = await _safeRead(_commentsKey);
    if (savedComments != null) {
      try {
        final map = jsonDecode(savedComments) as Map<String, dynamic>;
        _localComments.clear();
        map.forEach((k, v) {
          if (v is List<dynamic>) {
            _localComments[k] = v
                .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
                .toList(growable: true);
          }
        });
      } catch (_) {}
    }

    if (_token != null && isConfigured) {
      try {
        final res = await _request('GET', '/v1/me');
        if (res['profile'] is Map<String, dynamic>) {
          _profile =
              AccountProfile.fromJson(res['profile'] as Map<String, dynamic>);
          await _saveProfileToStorage(_profile!);
          }
        } on Object {
          // Profile refresh is best-effort; ignore failures and continue.
        }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _saveProfileToStorage(AccountProfile p) async {
    final map = {
      'id': p.id,
      'email': p.email,
      'username': p.username,
      'displayName': p.displayName,
      'bio': p.bio,
      'isPrivate': p.isPrivate,
      if (p.birthDate != null) 'birthDate': p.birthDate!.toIso8601String().split('T').first,
      if (p.avatarBytes != null && p.avatarMimeType != null)
        'avatar': {
          'mimeType': p.avatarMimeType,
          'data': base64Url.encode(p.avatarBytes!).replaceAll('=', ''),
        },
    };
    await _safeWrite(_profileKey, jsonEncode(map));
  }

  Future<void> _savePostsToStorage() async {
    try {
      final list = _localPosts.map((p) => p.toJson()).toList();
      await _safeWrite(_postsKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _saveCommentsToStorage() async {
    try {
      final map = _localComments
          .map((k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()));
      await _safeWrite(_commentsKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _saveStoriesToStorage() async {
    try {
      final list = _localStories.map((s) => s.toJson()).toList();
      await _safeWrite(_storiesKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _saveFollowingToStorage() async {
    try {
      final list = _followingUsernames.toList();
      await _safeWrite(_followingKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _saveLikesToStorage() async {
    try {
      final list = _likedPostIds.toList();
      await _safeWrite(_likesKey, jsonEncode(list));
    } catch (_) {}
  }

  // ── Database Storage Helpers ───────────────

  Future<Map<String, StoredUserAccount>> _getUsersDatabase() async {
    try {
      final raw = await _safeRead(_usersDatabaseKey);
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, StoredUserAccount.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsersDatabase(Map<String, StoredUserAccount> users) async {
    final map = users.map((k, v) => MapEntry(k, v.toJson()));
    await _safeWrite(_usersDatabaseKey, jsonEncode(map));
  }

  static Future<String> _hashPassword(String password, String salt) async {
    final algorithm = Sha256();
    final hash = await algorithm.hash(utf8.encode('$salt:$password'));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'slt_${now}_${(now * 31 % 1000000)}';
  }

  /// Registers a real new account into our user database.
  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final cleanEmail = email.trim().toLowerCase();
      final cleanUsername = username.trim().toLowerCase();
      final cleanDisplayName = displayName.trim().isNotEmpty
          ? displayName.trim()
          : cleanUsername;

      if (cleanUsername.length < 3) {
        throw Exception('Username must be at least 3 characters.');
      }
      if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(cleanUsername)) {
        throw Exception(
            'Username can only contain letters, numbers, dots and underscores.');
      }
      if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
        throw Exception('Please enter a valid email address.');
      }
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters long.');
      }

      final db = await _getUsersDatabase();
      for (final user in db.values) {
        if (user.email == cleanEmail) {
          throw Exception('An account with this email already exists.');
        }
        if (user.username == cleanUsername) {
          throw Exception(
              'This username is already taken. Please choose another.');
        }
      }

      String? serverToken;
      AccountProfile? serverProfile;

      // Try registering on backend server if online/configured
      if (isConfigured) {
        try {
          final res = await _request('POST', '/v1/users', {
            'email': cleanEmail,
            'password': password,
            'username': cleanUsername,
            'displayName': cleanDisplayName,
          }, false);
          serverToken = res['token'] as String?;
          if (res['profile'] is Map<String, dynamic>) {
            serverProfile = AccountProfile.fromJson(
                res['profile'] as Map<String, dynamic>);
          }
        } on ApiException catch (e) {
          if (e.statusCode == 409) {
            throw Exception('Email or username is already in use.');
          }
        } catch (_) {
          // If server is currently offline or unreachable, local database registration proceeds seamlessly
        }
      }

      final salt = _generateSalt();
      final passwordHash = await _hashPassword(password, salt);
      final userId = serverProfile?.id ??
          'usr_${DateTime.now().millisecondsSinceEpoch}';

      final newAccount = StoredUserAccount(
        id: userId,
        email: cleanEmail,
        username: cleanUsername,
        displayName: cleanDisplayName,
        passwordHash: passwordHash,
        salt: salt,
        bio: 'Hey there! I am using SejiloChat.',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      db[newAccount.id] = newAccount;
      await _saveUsersDatabase(db);

      _profile = serverProfile ?? newAccount.toProfile();
      _token = serverToken ??
          'token_${newAccount.id}_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: _tokenKey, value: _token);
      await _saveProfileToStorage(_profile!);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Authenticates using either email OR username against our database.
  Future<void> login({required String email, required String password}) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final identifier = email.trim().toLowerCase();
      if (identifier.isEmpty) {
        throw Exception('Email or username is required.');
      }
      if (password.isEmpty) {
        throw Exception('Password is required.');
      }

      String? serverToken;
      AccountProfile? serverProfile;

      // 1. Try remote server authentication first if available
      if (isConfigured) {
        try {
          final res = await _request('POST', '/v1/auth/password/login', {
            'email': identifier,
            'password': password,
          }, false);
          serverToken = res['token'] as String?;
          if (res['profile'] is Map<String, dynamic>) {
            serverProfile = AccountProfile.fromJson(
                res['profile'] as Map<String, dynamic>);
          }
        } on ApiException catch (e) {
          if (e.statusCode == 401) {
            throw Exception('Invalid email, username or password.');
          }
        } catch (_) {
          // Network failure or offline: fallback to local database
        }
      }

      final db = await _getUsersDatabase();
      StoredUserAccount? matchedUser;
      for (final user in db.values) {
        if (user.email == identifier || user.username == identifier) {
          matchedUser = user;
          break;
        }
      }

      if (serverToken != null && serverProfile != null) {
        // Authenticated with server: update or insert into database
        if (matchedUser != null) {
          db[matchedUser.id] = matchedUser.copyWith(
            displayName: serverProfile.displayName,
            bio: serverProfile.bio,
            avatarBytes: serverProfile.avatarBytes,
            avatarMimeType: serverProfile.avatarMimeType,
            birthDate: serverProfile.birthDate,
            isPrivate: serverProfile.isPrivate,
          );
        } else {
          final salt = _generateSalt();
          final passwordHash = await _hashPassword(password, salt);
          db[serverProfile.id] = StoredUserAccount(
            id: serverProfile.id,
            email: serverProfile.email,
            username: serverProfile.username,
            displayName: serverProfile.displayName,
            passwordHash: passwordHash,
            salt: salt,
            bio: serverProfile.bio,
            avatarBytes: serverProfile.avatarBytes,
            avatarMimeType: serverProfile.avatarMimeType,
            birthDate: serverProfile.birthDate,
            isPrivate: serverProfile.isPrivate,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
        await _saveUsersDatabase(db);
        _profile = serverProfile;
        _token = serverToken;
        await _storage.write(key: _tokenKey, value: _token);
        await _saveProfileToStorage(_profile!);
        return;
      }

      // 2. Validate against local database
      if (matchedUser == null) {
        throw Exception('No account found with this email or username.');
      }

      final hash = await _hashPassword(password, matchedUser.salt);
      if (hash != matchedUser.passwordHash) {
        throw Exception('Incorrect password. Please try again.');
      }

      _profile = matchedUser.toProfile();
      _token =
          'token_${matchedUser.id}_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: _tokenKey, value: _token);
      await _saveProfileToStorage(_profile!);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
    String? fallbackUsername,
    String? fallbackDisplayName,
  }) =>
      login(email: email, password: password);

  // ── Phone OTP Authentication ───────────────

  /// Step 1: Send OTP to Phone Number
  Future<String> sendPhoneOtp(String phoneNumber) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      _pendingPhoneNumber = cleanPhone;

      if (!isConfigured) {
        throw Exception(
            'Phone OTP requires a configured server. Use Continue without '
            'account for offline mesh-only mode.');
      }

      final res = await _request('POST', '/v1/auth/phone/otp-requests',
          {'phoneNumber': cleanPhone}, false);
      final devCode = res['devCode'] as String?;
      if (devCode != null && devCode.isNotEmpty) {
        return devCode;
      }
      return 'sent via SMS';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Step 2: Verify Phone OTP and Sign In / Register
  Future<void> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
    String? username,
    String? displayName,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      if (otp.trim().isEmpty || otp.trim().length < 4) {
        throw Exception('Please enter a valid 6-digit confirmation code.');
      }

      if (!isConfigured) {
        throw Exception(
            'Phone OTP requires a configured server. Use Continue without '
            'account for offline mesh-only mode.');
      }

      final res = await _request(
          'POST',
          '/v1/auth/phone/verify',
          {
            'phoneNumber': cleanPhone,
            'code': otp.trim(),
            if (username != null) 'username': username.trim(),
            if (displayName != null) 'displayName': displayName.trim(),
          },
          false);
      if (res['token'] is String && res['profile'] is Map<String, dynamic>) {
        _token = res['token'] as String;
        _profile = AccountProfile.fromJson(
            res['profile'] as Map<String, dynamic>);
        await _storage.write(key: _tokenKey, value: _token);
        await _saveProfileToStorage(_profile!);
        return;
      }
      throw Exception('Verification failed. Check the code and try again.');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      if (_token != null && isConfigured) {
        await _request('DELETE', '/v1/auth/password/session');
      }
    } on Object {
      // Session deletion on the server is best-effort; clear local state anyway.
    }
    _token = null;
    _profile = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _profileKey);
    notifyListeners();
  }

  Future<void> signOut() => logout();

  /// Deletes the account on the server, then wipes every local trace of it from database and storage.
  Future<void> deleteAccount() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (_token != null && isConfigured) {
        await _request('DELETE', '/v1/me');
      }
      final currentId = _profile?.id;
      if (currentId != null) {
        final db = await _getUsersDatabase();
        if (db.containsKey(currentId)) {
          db.remove(currentId);
          await _saveUsersDatabase(db);
        }
      }
      _token = null;
      _profile = null;
      _localPosts.clear();
      _localStories.clear();
      _localComments.clear();
      _likedPostIds.clear();
      _followingUsernames.clear();
      await _storage.deleteAll();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> requestPasswordReset(String email) => _run(() async {
        if (isConfigured) {
          await _request('POST', '/v1/auth/password/reset-requests',
              {'email': email.trim()});
        }
      });

  Future<void> resetPassword(
          {required String token, required String password}) =>
      _run(() async {
        if (isConfigured) {
          await _request('POST', '/v1/auth/password/resets',
              {'token': token.trim(), 'password': password});
        }
      });

  // ── Profile ─────────────────────────────────

  Future<void> updateProfile({
    required String username,
    required String displayName,
    required String bio,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    DateTime? birthDate,
    bool removeAvatar = false,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final cur = _profile;
      final newUsername = username.trim().isNotEmpty
          ? username.trim()
          : (cur?.username ?? 'user');
      final newDisplayName = displayName.trim().isNotEmpty
          ? displayName.trim()
          : (cur?.displayName ?? 'User');
      final newBio = bio.trim();
      final newAvatarBytes =
          removeAvatar ? null : (avatarBytes ?? cur?.avatarBytes);
      final newAvatarMime =
          removeAvatar ? null : (avatarMimeType ?? cur?.avatarMimeType);
      final newBirthDate = birthDate ?? cur?.birthDate;

      final updated = AccountProfile(
        id: cur?.id ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
        email: cur?.email ?? '$newUsername@sejilochat.net',
        username: newUsername,
        displayName: newDisplayName,
        bio: newBio,
        avatarBytes: newAvatarBytes,
        avatarMimeType: newAvatarMime,
        birthDate: newBirthDate,
        isPrivate: cur?.isPrivate ?? false,
      );

      _profile = updated;
      await _saveProfileToStorage(updated);

      final db = await _getUsersDatabase();
      if (cur != null && db.containsKey(cur.id)) {
        db[cur.id] = db[cur.id]!.copyWith(
          username: newUsername,
          displayName: newDisplayName,
          bio: newBio,
          avatarBytes: newAvatarBytes,
          avatarMimeType: newAvatarMime,
          birthDate: newBirthDate,
        );
        await _saveUsersDatabase(db);
      }

      if (isConfigured && _token != null && !_token!.startsWith('local_')) {
        try {
          final body = <String, Object?>{
            'username': newUsername,
            'displayName': newDisplayName,
            'bio': newBio,
          };
          if (removeAvatar) body['avatar'] = null;
          if (newAvatarBytes != null && newAvatarMime != null) {
            body['avatar'] = {
              'mimeType': newAvatarMime,
              'data': base64Url.encode(newAvatarBytes).replaceAll('=', ''),
            };
          }
          if (birthDate != null) {
            body['birthDate'] =
                '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';
          }
          final res = await _request('PATCH', '/v1/me', body);
          if (res['profile'] is Map<String, dynamic>) {
            _profile =
                AccountProfile.fromJson(res['profile'] as Map<String, dynamic>);
            await _saveProfileToStorage(_profile!);
            if (db.containsKey(_profile!.id)) {
              db[_profile!.id] = db[_profile!.id]!.copyWith(
                username: _profile!.username,
                displayName: _profile!.displayName,
                bio: _profile!.bio,
                avatarBytes: _profile!.avatarBytes,
                avatarMimeType: _profile!.avatarMimeType,
                birthDate: _profile!.birthDate,
              );
              await _saveUsersDatabase(db);
            }
          }
        } on Object catch (e) {
          // If the cloud server is offline, sleeping, or returning 404, the local profile
          // is already saved and persists in our database.
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Flips account privacy on the server.
  ///
  /// The effect is enforced backend-side — a follow of a private account
  /// becomes a follow *request*, and the account drops out of search and
  /// recommendations — so nothing here is a local-only flag. The local copy is
  /// only updated once the server has accepted the change.
  Future<void> setAccountPrivate(bool value) async {
    final cur = _profile;
    if (cur == null) {
      throw const ApiException(401, 'Sign in to change your account privacy.');
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _request('PATCH', '/v1/me', {'isPrivate': value});
      _profile = res['profile'] is Map<String, dynamic>
          ? AccountProfile.fromJson(res['profile'] as Map<String, dynamic>)
          : AccountProfile(
              id: cur.id,
              email: cur.email,
              username: cur.username,
              displayName: cur.displayName,
              bio: cur.bio,
              avatarBytes: cur.avatarBytes,
              avatarMimeType: cur.avatarMimeType,
              birthDate: cur.birthDate,
              isPrivate: value,
            );
      await _saveProfileToStorage(_profile!);
    } on ApiException catch (e) {
      _error = e.message;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// The profile as the server reports it.
  ///
  /// A failure is surfaced rather than replaced with an invented profile. The
  /// old fallback returned a made-up id and the bio "SejiloChat Explorer", so a
  /// network error looked like a real but empty account — and every
  /// viewer-scoped flag (follow state, mute, block) silently read false.
  Future<PublicProfile> loadPublicProfile(String username) async {
    final handle = username.trim().toLowerCase();
    if (isConfigured) {
      final response =
          await _request('GET', '/v1/users/${Uri.encodeComponent(handle)}');
      return PublicProfile.fromJson(
          response['profile'] as Map<String, dynamic>);
    }

    // With no server configured the only profile this device genuinely knows
    // is the signed-in one, which is held in local storage.
    final me = _profile;
    if (me != null && handle == me.username.trim().toLowerCase()) {
      return PublicProfile(
        id: me.id,
        username: me.username,
        displayName: me.displayName,
        bio: me.bio,
        avatarBytes: me.avatarBytes,
        avatarMimeType: me.avatarMimeType,
      );
    }
    throw ApiException(
      0,
      'No server is configured, so @$handle cannot be loaded. '
      'Set the address under Settings › Server.',
    );
  }
  /// Follows or unfollows, then returns the profile the server reports.
  ///
  /// The local mirror is updated first so the button reacts at once, and rolled
  /// back if the request fails. The old version swallowed the error, so the app
  /// showed "Following" for a follow the server had rejected.
  Future<PublicProfile> setFollow(String username, bool follow) async {
    final handle = username.trim().toLowerCase();
    if (follow) {
      _followingUsernames.add(handle);
    } else {
      _followingUsernames.remove(handle);
    }
    await _saveFollowingToStorage();
    notifyListeners();

    if (!isConfigured) return loadPublicProfile(handle);

    try {
      final response = await _request(
        follow ? 'POST' : 'DELETE',
        '/v1/users/${Uri.encodeComponent(handle)}/follow',
      );
      return PublicProfile.fromJson(
          response['profile'] as Map<String, dynamic>);
    } catch (_) {
      if (follow) {
        _followingUsernames.remove(handle);
      } else {
        _followingUsernames.add(handle);
      }
      await _saveFollowingToStorage();
      notifyListeners();
      rethrow;
    }
  }

  /// Asks to follow a private account. The server answers with the profile,
  /// where `followRequestPending` is true until the owner accepts.
  Future<PublicProfile> requestFollow(String username) async {
    final response = await _request(
      'POST',
      '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/follow',
    );
    return PublicProfile.fromJson(response['profile'] as Map<String, dynamic>);
  }

  /// Follow requests waiting on this account.
  ///
  /// The path carries the extra `/pending` segment because
  /// `/v1/users/follow-requests` is shadowed by the profile-by-username route
  /// on the server.
  Future<List<Map<String, dynamic>>> getFollowRequests() async {
    if (!isConfigured) return const [];
    final response =
        await _request('GET', '/v1/users/follow-requests/pending');
    final list = response['requests'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  Future<PublicProfile> acceptFollowRequest(String requesterId) async {
    final response = await _request(
      'POST',
      '/v1/users/follow-requests/${Uri.encodeComponent(requesterId)}/accept',
    );
    return PublicProfile.fromJson(response['profile'] as Map<String, dynamic>);
  }

  Future<void> rejectFollowRequest(String requesterId) async {
    await _request(
      'POST',
      '/v1/users/follow-requests/${Uri.encodeComponent(requesterId)}/reject',
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getMessageRequests() async {
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/message-requests');
        final list = response['requests'] as List<dynamic>;
        return list
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  Future<Map<String, String>> sendMessageRequest(String recipientId, String text) async {
    if (isConfigured) {
      try {
        final response = await _request('POST', '/v1/message-requests/send', {
          'recipientId': recipientId,
          'text': text,
        });
        return Map<String, String>.from(response);
      } catch (_) {}
    }
    notifyListeners();
    return <String, String>{};
  }

  Future<Map<String, String>> acceptMessageRequest(String requestId) async {
    if (isConfigured) {
      try {
        final response = await _request(
          'POST',
          '/v1/message-requests/$requestId/accept',
        );
        return Map<String, String>.from(response);
      } catch (_) {}
    }
    notifyListeners();
    return <String, String>{};
  }

  Future<void> rejectMessageRequest(String requestId) async {
    if (isConfigured) {
      try {
        await _request(
          'POST',
          '/v1/message-requests/$requestId/reject',
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<List<SocialPost>> loadUserPosts(String username) async {
    final isMe = _profile != null &&
        username.toLowerCase() == _profile!.username.toLowerCase();
    if (isConfigured) {
      try {
        final response = await _request('GET',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/posts');
        final remote = (response['posts'] as List<dynamic>)
            .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
            .toList(growable: true);
        if (isMe) {
          final ids = remote.map((p) => p.id).toSet();
          final localToAdd = _localPosts.where((p) => !ids.contains(p.id));
          remote.insertAll(0, localToAdd);
        }
        return remote;
      } catch (e) {
        // Someone else's grid must not fall back to an empty list. The server
        // answers 403 for a private account and for a block, and that used to
        // be swallowed here and drawn as "No posts yet" — which read as an
        // account with nothing on it rather than one the viewer cannot see.
        if (!isMe) rethrow;
        // The viewer's own grid keeps a fallback, but only to the posts this
        // device composed; the page shows the error alongside it.
        return List.unmodifiable(_localPosts);
      }
    }
    return isMe ? List.unmodifiable(_localPosts) : const [];
  }

  Future<List<PublicProfile>> loadFollowers(String username) async {
    if (isConfigured) {
      try {
        final response = await _request('GET',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/followers');
        return (response['users'] as List<dynamic>)
            .map((e) => PublicProfile.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  Future<List<PublicProfile>> loadFollowing(String username) async {
    if (isConfigured) {
      try {
        final response = await _request('GET',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/following');
        return (response['users'] as List<dynamic>)
            .map((e) => PublicProfile.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return _followingUsernames
        .map((u) => PublicProfile(
              id: 'usr_$u',
              username: u,
              displayName: u,
              bio: '',
              followersCount: 0,
              followingCount: 0,
              followedByViewer: true,
            ))
        .toList();
  }

  // ── Feed ─────────────────────────────────────

  Future<FeedPage> loadFeed({String? cursor}) async {
    if (isConfigured) {
      try {
        final path = cursor == null
            ? '/v1/feed?limit=20'
            : '/v1/feed?limit=20&cursor=${Uri.encodeQueryComponent(cursor)}';
        final response = await _request('GET', path);
        final remote = (response['posts'] as List<dynamic>)
            .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
            .toList(growable: true);
        final ids = remote.map((p) => p.id).toSet();
        final localToAdd = _localPosts.where((p) => !ids.contains(p.id));
        remote.insertAll(0, localToAdd);
        return FeedPage(
          posts: remote,
          nextCursor: response['nextCursor'] as String?,
        );
      } catch (_) {}
    }
    return FeedPage(posts: List.unmodifiable(_localPosts));
  }

  Future<List<SocialPost>> discoverPosts() async {
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/explore?limit=30');
        return (response['posts'] as List<dynamic>)
            .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return List.unmodifiable(_localPosts);
  }

  /// The Explore grid as a page, so a caller can keep scrolling past the first
  /// batch. `/v1/explore` is the global timeline; `/v1/feed` is the same shape
  /// but scoped to the accounts you follow, which is what makes the home
  /// screen's For You / Following switch two calls rather than two endpoints.
  ///
  /// [discoverPosts] is left alone — the explore grid, the hashtag page and the
  /// old feed screen all call it and none of them paginate.
  Future<FeedPage> loadExplore({String? cursor, int limit = 24}) async {
    if (isConfigured) {
      try {
        final path = cursor == null
            ? '/v1/explore?limit=$limit'
            : '/v1/explore?limit=$limit&cursor=${Uri.encodeQueryComponent(cursor)}';
        final response = await _request('GET', path);
        return FeedPage(
          posts: (response['posts'] as List<dynamic>)
              .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
              .toList(growable: true),
          nextCursor: response['nextCursor'] as String?,
        );
      } catch (_) {}
    }
    return FeedPage(posts: List.unmodifiable(_localPosts));
  }

  Future<List<PublicProfile>> searchUsers(String query) async {
    if (isConfigured) {
      try {
        final path =
            '/v1/users/search?q=${Uri.encodeQueryComponent(query.trim())}&limit=20';
        final response = await _request('GET', path);
        return (response['users'] as List<dynamic>)
            .map((e) => PublicProfile.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  // ── Posts ─────────────────────────────────────

  Future<void> createPost({
    required Uint8List image,
    // Only a hint, kept for call-site readability. The label that goes to the
    // server always comes from the optimiser below, which is the only thing
    // that knows what format the bytes ended up in.
    String? mimeType,
    required String caption,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final optimized = await ImageUtils.optimizeImage(
        image,
        maxDimension: _uploadDimension,
      );
      final optimizedBytes = optimized.bytes;
      final p = _profile;
      final newPost = SocialPost(
        id: 'post_${DateTime.now().millisecondsSinceEpoch}',
        userId: p?.id ?? 'usr_me',
        username: p?.username ?? 'you',
        displayName: p?.displayName ?? 'You',
        caption: caption.trim(),
        media: optimizedBytes,
        createdAt: DateTime.now(),
        likes: 0,
        comments: 0,
        liked: false,
        avatarBytes: p?.avatarBytes,
      );

      _localPosts.insert(0, newPost);
      await _savePostsToStorage();

      if (isConfigured) {
        try {
          await _request('POST', '/v1/posts', {
            'media': {
              'mimeType': optimized.mimeType,
              'data': base64Url.encode(optimizedBytes).replaceAll('=', ''),
            },
            'caption': caption.trim(),
          });
        } on ApiException catch (e) {
          // This used to be `catch (_) {}`: a post the server rejected still
          // showed up in the local feed and the compose screen still reported
          // success. A 4xx will never succeed on retry, so take the local copy
          // back out; anything else (timeout, 5xx) keeps it so the user's work
          // is not thrown away.
          if (e.isClientError) {
            _localPosts.removeWhere((post) => post.id == newPost.id);
            await _savePostsToStorage();
          }
          _error = e.message;
          rethrow;
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Bookmarks a post, or takes the bookmark off.
  ///
  /// The device copy moves first so the icon answers the tap immediately, then
  /// the server is told. If the server refuses — or cannot be reached — the
  /// local change is put back and the error is rethrown. It used to be wrapped
  /// in `catch (_) {}`, which was harmless only while `POST /v1/posts/:id/saves`
  /// did not exist: a bookmark looked saved, lived on that one device, and
  /// quietly vanished the next time the Saved tab was loaded from the server.
  Future<void> setSave(String postId, bool saved) async {
    final wasSaved = _savedPostIds.contains(postId);
    await _applySavedState(postId, saved);

    if (isConfigured) {
      try {
        await _request(saved ? 'POST' : 'DELETE', '/v1/posts/$postId/saves');
      } catch (e) {
        await _applySavedState(postId, wasSaved);
        _error = e is ApiException
            ? e.message
            : 'Your bookmark could not be saved — the server could not be '
                'reached.';
        notifyListeners();
        rethrow;
      }
    }
    notifyListeners();
  }

  /// Writes the saved flag for [postId] to storage and to any cached copy of the
  /// post. Split out so [setSave] can use the same code to apply a change and to
  /// roll it back.
  Future<void> _applySavedState(String postId, bool saved) async {
    if (saved) {
      _savedPostIds.add(postId);
    } else {
      _savedPostIds.remove(postId);
    }
    await _safeWrite(_savedPostsKey, jsonEncode(_savedPostIds.toList()));

    final index = _localPosts.indexWhere((p) => p.id == postId);
    if (index >= 0) {
      final p = _localPosts[index];
      _localPosts[index] = SocialPost(
        id: p.id,
        userId: p.userId,
        username: p.username,
        displayName: p.displayName,
        caption: p.caption,
        media: p.media,
        createdAt: p.createdAt,
        likes: p.likes,
        comments: p.comments,
        liked: p.liked,
        saved: saved,
        avatarBytes: p.avatarBytes,
      );
      await _savePostsToStorage();
    }
  }

  Future<void> savePost(String postId) => setSave(postId, true);
  Future<void> unsavePost(String postId) => setSave(postId, false);

  /// The account's bookmarks.
  ///
  /// Once a backend is configured this is the server's list and nothing else:
  /// the failure is left for the caller to show, because falling back to the
  /// device's own subset used to present a stale — often empty — Saved tab as
  /// though it were complete.
  Future<List<SocialPost>> loadSavedPosts() async {
    if (isConfigured) {
      final response = await _request('GET', '/v1/saved-posts?limit=30');
      return (response['posts'] as List<dynamic>)
          .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    }
    return _localPosts.where((p) => _savedPostIds.contains(p.id)).toList();
  }

  Future<List<SocialNotification>> loadNotifications() async {
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/notifications');
        _unreadNotificationsCount = response['unreadCount'] as int? ?? 0;
        final list = (response['notifications'] as List<dynamic>)
            .map((e) => SocialNotification.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
        _notifications.clear();
        _notifications.addAll(list);
        notifyListeners();
        return _notifications;
      } catch (_) {}
    }
    return _notifications;
  }

  Future<void> markNotificationsRead() async {
    _unreadNotificationsCount = 0;
    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      if (!n.isRead) {
        _notifications[i] = SocialNotification(
          id: n.id,
          type: n.type,
          postId: n.postId,
          isRead: true,
          createdAt: n.createdAt,
          actor: n.actor,
          postMediaBytes: n.postMediaBytes,
        );
      }
    }
    notifyListeners();

    if (isConfigured) {
      try {
        await _request('POST', '/v1/notifications/read');
      } catch (_) {}
    }
  }

  Future<void> deletePost(String postId) async {
    _localPosts.removeWhere((p) => p.id == postId);
    await _savePostsToStorage();
    if (isConfigured) {
      try {
        await _request('DELETE', '/v1/posts/$postId');
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Likes a post, or removes the like.
  ///
  /// Optimistic in the same way as [setSave], and rolled back the same way: the
  /// server call used to be swallowed, so a like the server rejected still drew
  /// a filled heart and a count that no other device would ever agree with.
  Future<void> setLike(String postId, bool liked) async {
    final wasLiked = _likedPostIds.contains(postId);
    await _applyLikedState(postId, liked);

    if (isConfigured) {
      try {
        await _request(liked ? 'POST' : 'DELETE', '/v1/posts/$postId/likes');
      } catch (e) {
        await _applyLikedState(postId, wasLiked);
        _error = e is ApiException
            ? e.message
            : 'Your like could not be sent — the server could not be reached.';
        notifyListeners();
        rethrow;
      }
    }
    notifyListeners();
  }

  /// Writes the liked flag and the count for [postId] to storage and to any
  /// cached copy of the post. The count moves only when the flag actually
  /// changes, so applying the same value twice cannot drift it.
  Future<void> _applyLikedState(String postId, bool liked) async {
    if (liked) {
      _likedPostIds.add(postId);
    } else {
      _likedPostIds.remove(postId);
    }
    final index = _localPosts.indexWhere((p) => p.id == postId);
    if (index >= 0) {
      final p = _localPosts[index];
      final newLikes = liked
          ? (p.liked ? p.likes : p.likes + 1)
          : (p.liked ? p.likes - 1 : p.likes);
      _localPosts[index] = SocialPost(
        id: p.id,
        userId: p.userId,
        username: p.username,
        displayName: p.displayName,
        caption: p.caption,
        media: p.media,
        createdAt: p.createdAt,
        likes: newLikes < 0 ? 0 : newLikes,
        comments: p.comments,
        liked: liked,
        saved: p.saved,
        avatarBytes: p.avatarBytes,
      );
      await _savePostsToStorage();
    }
    await _saveLikesToStorage();
  }

  Future<void> likePost(String postId) => setLike(postId, true);
  Future<void> unlikePost(String postId) => setLike(postId, false);

  Future<List<PostComment>> loadComments(String postId) async {
    final local = _localComments[postId] ?? [];
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/posts/$postId/comments');
        final remote = (response['comments'] as List<dynamic>)
            .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
            .toList(growable: true);
        final ids = remote.map((c) => c.id).toSet();
        remote.addAll(local.where((c) => !ids.contains(c.id)));
        return remote;
      } catch (_) {}
    }
    return List.unmodifiable(local);
  }

  Future<void> addComment(String postId, String text) async {
    final p = _profile;
    final comment = PostComment(
      id: 'cmt_${DateTime.now().millisecondsSinceEpoch}',
      userId: p?.id ?? 'usr_me',
      username: p?.username ?? 'you',
      displayName: p?.displayName ?? 'You',
      text: text.trim(),
      createdAt: DateTime.now(),
    );

    _localComments.putIfAbsent(postId, () => []).add(comment);

    final pIndex = _localPosts.indexWhere((post) => post.id == postId);
    if (pIndex >= 0) {
      final cur = _localPosts[pIndex];
      _localPosts[pIndex] = SocialPost(
        id: cur.id,
        userId: cur.userId,
        username: cur.username,
        displayName: cur.displayName,
        caption: cur.caption,
        media: cur.media,
        createdAt: cur.createdAt,
        likes: cur.likes,
        comments: cur.comments + 1,
        liked: cur.liked,
        avatarBytes: cur.avatarBytes,
      );
      await _savePostsToStorage();
    }
    await _saveCommentsToStorage();

    if (isConfigured) {
      try {
        final response = await _request(
            'POST', '/v1/posts/$postId/comments', {'text': text.trim()});
        // Adopt the id the server assigned. loadComments returns the remote
        // list and then appends local comments whose id it did not already
        // see, so an optimistic entry that kept its fabricated `cmt_…` id
        // would reappear beside the server's copy of the same comment.
        await _adoptServerCommentId(postId, comment.id, response['id']);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Rewrites a just-posted comment's local id to the one the server chose,
  /// keeping the entry so it stays on screen if the next fetch fails.
  Future<void> _adoptServerCommentId(
    String postId,
    String localId,
    Object? serverId,
  ) async {
    if (serverId is! String || serverId.isEmpty || serverId == localId) return;
    final list = _localComments[postId];
    if (list == null) return;
    final index = list.indexWhere((c) => c.id == localId);
    if (index < 0) return;
    final old = list[index];
    list[index] = PostComment(
      id: serverId,
      userId: old.userId,
      username: old.username,
      displayName: old.displayName,
      text: old.text,
      createdAt: old.createdAt,
      avatarBytes: old.avatarBytes,
    );
    await _saveCommentsToStorage();
  }

  /// Removes one of your own comments. The backend rejects deleting anyone
  /// else's (`DELETE /v1/comments/:id` checks ownership), so callers should
  /// only offer this on comments whose `userId` is the signed-in user.
  Future<void> deleteComment(String postId, String commentId) async {
    final list = _localComments[postId];
    final removed = list?.where((c) => c.id == commentId).isNotEmpty ?? false;
    list?.removeWhere((c) => c.id == commentId);
    if (list != null && list.isEmpty) _localComments.remove(postId);

    final pIndex = _localPosts.indexWhere((post) => post.id == postId);
    if (pIndex >= 0 && removed) {
      final cur = _localPosts[pIndex];
      _localPosts[pIndex] = SocialPost(
        id: cur.id,
        userId: cur.userId,
        username: cur.username,
        displayName: cur.displayName,
        caption: cur.caption,
        media: cur.media,
        createdAt: cur.createdAt,
        likes: cur.likes,
        comments: cur.comments > 0 ? cur.comments - 1 : 0,
        liked: cur.liked,
        avatarBytes: cur.avatarBytes,
      );
      await _savePostsToStorage();
    }
    await _saveCommentsToStorage();

    if (isConfigured) {
      try {
        await _request('DELETE', '/v1/comments/$commentId');
      } catch (_) {}
    }
    notifyListeners();
  }

  // ── Stories ───────────────────────────────────

  Future<List<Story>> loadStories() async {
    final now = DateTime.now();
    final validLocal =
        _localStories.where((s) => s.expiresAt.isAfter(now)).toList();
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/stories');
        final List<Story> remote = (response['stories'] as List<dynamic>)
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .where((s) => s.expiresAt.isAfter(now))
            .toList(growable: true);
        final ids = remote.map((s) => s.id).toSet();
        remote.addAll(validLocal.where((s) => !ids.contains(s.id)));
        return remote;
      } catch (_) {}
    }
    return List.unmodifiable(validLocal);
  }

  Future<List<UserStoryGroup>> loadGroupedStories() async {
    final allStories = await loadStories();
    final Map<String, List<Story>> byUser = {};
    for (final s in allStories) {
      byUser.putIfAbsent(s.username, () => []).add(s);
    }

    final groups = <UserStoryGroup>[];
    byUser.forEach((username, userStories) {
      if (userStories.isNotEmpty) {
        final first = userStories.first;
        groups.add(UserStoryGroup(
          userId: first.userId,
          username: first.username,
          displayName: first.displayName,
          avatarBytes: first.avatarBytes,
          stories: userStories,
        ));
      }
    });

    final myUsername = _profile?.username.toLowerCase();
    groups.sort((a, b) {
      if (a.username.toLowerCase() == myUsername) return -1;
      if (b.username.toLowerCase() == myUsername) return 1;
      if (a.hasUnseenStory && !b.hasUnseenStory) return -1;
      if (!a.hasUnseenStory && b.hasUnseenStory) return 1;
      return 0;
    });

    return groups;
  }

  Future<void> createImageStory({
    required Uint8List imageBytes,
    // Hint only — see createPost. The optimiser decides the real format.
    String? mimeType,
    String? caption,
  }) async {
    _busy = true;
    notifyListeners();

    try {
      final optimized = await ImageUtils.optimizeImage(
        imageBytes,
        maxDimension: _uploadDimension,
      );
      final optimizedBytes = optimized.bytes;
      final p = _profile;
      final now = DateTime.now();
      final newStory = Story(
        id: 'story_${now.millisecondsSinceEpoch}',
        userId: p?.id ?? 'usr_me',
        username: p?.username ?? 'you',
        displayName: p?.displayName ?? 'You',
        avatarBytes: p?.avatarBytes,
        type: StoryType.image,
        mediaBytes: optimizedBytes,
        textContent: caption,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        viewedByMe: true,
      );

      _localStories.insert(0, newStory);
      await _saveStoriesToStorage();

      if (isConfigured) {
        try {
          await _request('POST', '/v1/stories', {
            'type': 'image',
            'media': {
              'mimeType': optimized.mimeType,
              'data': base64Url.encode(optimizedBytes).replaceAll('=', ''),
            },
            if (caption != null && caption.isNotEmpty) 'textContent': caption,
          });
        } on ApiException catch (e) {
          // Same reasoning as createPost: a rejected story must not be reported
          // as published.
          if (e.isClientError) {
            _localStories.removeWhere((story) => story.id == newStory.id);
            await _saveStoriesToStorage();
          }
          _error = e.message;
          rethrow;
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> createTextStory({
    required String text,
    required String backgroundStyle,
  }) async {
    _busy = true;
    notifyListeners();

    try {
      final p = _profile;
      final now = DateTime.now();
      final newStory = Story(
        id: 'story_${now.millisecondsSinceEpoch}',
        userId: p?.id ?? 'usr_me',
        username: p?.username ?? 'you',
        displayName: p?.displayName ?? 'You',
        avatarBytes: p?.avatarBytes,
        type: StoryType.text,
        textContent: text.trim(),
        backgroundStyle: backgroundStyle,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        viewedByMe: true,
      );

      _localStories.insert(0, newStory);
      await _saveStoriesToStorage();

      if (isConfigured) {
        try {
          await _request('POST', '/v1/stories', {
            'type': 'text',
            'textContent': text.trim(),
            'backgroundStyle': backgroundStyle,
          });
        } on ApiException catch (e) {
          if (e.isClientError) {
            _localStories.removeWhere((story) => story.id == newStory.id);
            await _saveStoriesToStorage();
          }
          _error = e.message;
          rethrow;
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> createStory({
    required Uint8List imageBytes,
    String? mimeType,
  }) =>
      createImageStory(imageBytes: imageBytes, mimeType: mimeType);

  Future<void> markStoryViewed(String storyId) async {
    final index = _localStories.indexWhere((s) => s.id == storyId);
    if (index >= 0) {
      final s = _localStories[index];
      _localStories[index] = Story(
        id: s.id,
        userId: s.userId,
        username: s.username,
        displayName: s.displayName,
        avatarBytes: s.avatarBytes,
        type: s.type,
        mediaBytes: s.mediaBytes,
        textContent: s.textContent,
        backgroundStyle: s.backgroundStyle,
        createdAt: s.createdAt,
        expiresAt: s.expiresAt,
        viewedByMe: true,
        viewsCount: s.viewsCount,
      );
      await _saveStoriesToStorage();
    }
    notifyListeners();

    if (isConfigured) {
      try {
        await _request('POST', '/v1/stories/$storyId/views');
      } on Object {
        // Marking a story viewed is best-effort; ignore network failures.
      }
    }
  }

  Future<void> deleteStory(String storyId) async {
    _localStories.removeWhere((s) => s.id == storyId);
    await _saveStoriesToStorage();
    notifyListeners();

    if (isConfigured) {
      try {
        await _request('DELETE', '/v1/stories/$storyId');
      } catch (_) {}
    }
  }

  Future<List<StoryViewerInfo>> loadStoryViewers(String storyId) async {
    if (isConfigured) {
      try {
        final response = await _request('GET', '/v1/stories/$storyId/views');
        return (response['viewers'] as List<dynamic>)
            .map((e) => StoryViewerInfo.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  // ── Notifications helpers ─────────────────────

  Future<void> markNotificationRead(String id) => _run(() async {
        await _request('PATCH', '/v1/notifications/$id', {'read': true});
      });

  Future<void> markAllNotificationsRead() => markNotificationsRead();

  // ── Moderation ────────────────────────────────

  Future<void> blockUser(String username) => _run(() async {
        await _request('POST',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/block');
      });

  Future<void> unblockUser(String username) => _run(() async {
        await _request('DELETE',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/block');
      });

  Future<void> reportUser(String username, String reason, {String? details}) =>
      _run(() async {
        await _request(
            'POST',
            '/v1/users/${Uri.encodeComponent(username.trim().toLowerCase())}/reports',
            {
              'reason': reason,
              if (details != null && details.trim().isNotEmpty)
                'details': details.trim(),
            });
      });

  Future<void> reportPost(String postId, String reason, {String? details}) =>
      _run(() async {
        await _request('POST', '/v1/posts/$postId/reports', {
          'reason': reason,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
        });
      });

  /// Every report this account has filed, newest first.
  ///
  /// There is no moderator view in this deployment — the server only ever
  /// returns your own rows, since a report names its author and showing it to
  /// anyone else would out the reporter.
  Future<List<FiledReport>> loadMyReports() async {
    final response = await _request('GET', '/v1/me/reports?limit=50');
    final list = response['reports'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(FiledReport.fromJson)
        .toList(growable: false);
  }

  /// Mutes or unmutes an account.
  ///
  /// Server-side this is a `Block` row with `isMuted: true`, which suppresses
  /// that person's notifications without hiding you from them — so unlike a
  /// block it is reversible with no other visible effect.
  Future<void> setMuted(String identifier, bool muted) => _run(() async {
        await _request(
          'POST',
          '/v1/users/${Uri.encodeComponent(identifier.trim().toLowerCase())}/mute',
          {'isMuted': muted},
        );
      });

  /// The accounts this user has muted, straight from the server.
  Future<List<MutedUser>> loadMutedUsers() async {
    final response = await _request('GET', '/v1/users/muted');
    final list = response['mutedUsers'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MutedUser.fromJson)
        .toList(growable: false);
  }

  /// The accounts this user has blocked, straight from the server.
  ///
  /// `/v1/users/blocked` excludes muted rows, so this is the list the block
  /// screen should show — muting is managed on its own screen.
  Future<List<BlockedUser>> loadBlockedUsers() async {
    final response = await _request('GET', '/v1/users/blocked');
    final list = response['blockedUsers'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BlockedUser.fromJson)
        .toList(growable: false);
  }

  /// Device settings this controller was built with, for screens that only have
  /// a handle on the controller.
  ///
  /// Null in tests that construct the controller bare.
  AppPreferences? get preferences => _preferences;

  // ── Sharing ───────────────────────────────────

  /// Opens the direct conversation with [recipientUserId], creating it only if
  /// there is not one already, and returns its id.
  ///
  /// The server does the deduplication (`kind: 'direct'` with both members), so
  /// calling this twice does not leave two threads behind.
  Future<String> openDirectConversation(String recipientUserId) async {
    final response = await _request('POST', '/v1/chat/conversations', {
      'kind': 'direct',
      'recipientUserId': recipientUserId,
    });
    final id = response['id'];
    if (id is! String || id.isEmpty) {
      throw const ApiException(
          502, 'The server did not return a conversation to send into.');
    }
    return id;
  }

  /// Sends [post] to somebody as a direct message.
  ///
  /// The picture itself is attached rather than a link: this build registers no
  /// deep link and there is no web front end, so a `https://…/p/<id>` URL would
  /// open nothing for the person receiving it. The attachment is the post's own
  /// already-compressed bytes, so nothing is re-encoded here.
  Future<String> sharePostWithUser({
    required String recipientUserId,
    required SocialPost post,
    String? note,
  }) async {
    final conversationId = await openDirectConversation(recipientUserId);
    final caption = post.caption.trim();
    final lines = <String>[
      if (note != null && note.trim().isNotEmpty) note.trim(),
      '@${post.username}’s post${caption.isEmpty ? '' : ': $caption'}',
    ];
    await _request(
      'POST',
      '/v1/chat/conversations/${Uri.encodeComponent(conversationId)}/messages',
      {
        'text': lines.join('\n'),
        if (post.media.isNotEmpty)
          'media': {
            'mimeType': ImageUtils.sniffMimeType(post.media) ?? 'image/jpeg',
            'data': base64Url.encode(post.media).replaceAll('=', ''),
          },
      },
    );
    return conversationId;
  }

  // ── Internal helpers ──────────────────────────


  Future<void> _run(Future<void> Function() op) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await op();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Requests worth a second attempt when the first one runs out of time.
  ///
  /// A free-tier host stops the container after a stretch of no traffic and
  /// takes about a minute to start it again — longer than any 15-second
  /// deadline. The first request after an idle period is almost always a
  /// sign-in, so the app reported the server as unreachable at precisely the
  /// moment it was coming up. These are the calls that can safely be repeated
  /// when no response arrived: at worst a second attempt leaves behind an extra
  /// unused session. Sign-up, OTP requests, OTP verification and anything that
  /// writes content are deliberately excluded — repeating those duplicates an
  /// account, sends a second SMS, or spends a code that was already consumed.
  @visibleForTesting
  static bool isColdStartRetryable(String method, String path) =>
      method == 'GET' ||
      path == '/v1/auth/password/login';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, Object?>? body,
    bool authenticated = true,
  ]) async {
    if (!isConfigured) {
      throw Exception('Online accounts are not configured in this build.');
    }
    // Rebuilt per attempt: an http.Request is finalized when it is sent and
    // cannot be handed to the client twice.
    Future<http.Response> send(Duration limit) async {
      final request = http.Request(method, Uri.parse(baseUrl).resolve(path));
      request.headers['content-type'] = 'application/json';
      request.headers['accept'] = 'application/json';
      if (authenticated && _token != null) {
        request.headers['authorization'] = 'Bearer $_token';
      }
      if (body != null) request.body = jsonEncode(body);
      return http.Response.fromStream(
          await _client.send(request).timeout(limit));
    }

    http.Response response;
    try {
      response = await send(const Duration(seconds: 15));
    } on TimeoutException {
      if (!isColdStartRetryable(method, path)) rethrow;
      response = await send(const Duration(seconds: 70));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        _messageFromErrorBody(response.body, response.statusCode),
      );
    }
    return response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Extracts something worth showing the user out of an error body.
  ///
  /// Nest's ValidationPipe answers with `{"message": ["…", "…"]}` — a list —
  /// so testing only for a String meant every validation failure surfaced as
  /// "Request failed (400)." and the actual reason ("data is too large — the
  /// limit is about 2 MB per image or video.") was dropped on the floor.
  static String _messageFromErrorBody(String body, int statusCode) {
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final message = decoded['message'];
          if (message is String && message.isNotEmpty) return message;
          if (message is List) {
            final lines = message.whereType<String>().toList(growable: false);
            if (lines.isNotEmpty) return lines.join('\n');
          }
        }
      } catch (_) {
        // Not JSON (an HTML error page from a proxy, say) — fall through.
      }
    }
    return 'Request failed ($statusCode).';
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// A non-2xx answer from the SejiloChat API.
///
/// Carries the status code so callers can tell "this will never work" (4xx —
/// the payload was rejected) from "this might work later" (timeout, 5xx), which
/// is the difference between discarding an optimistic local write and keeping
/// it. `toString()` is the server's own message so existing `'$e'` snackbars
/// show the real reason rather than "Exception: …".
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// True when the session is gone and the user has to sign in again.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// What a probe of an API base URL actually found.
///
/// [reachable] means a SejiloChat server answered `/health`. [databaseReady]
/// means `/health/ready` also reported the database attached — the thing every
/// sign-in needs, and the state that is missing on a fresh deploy whose
/// `DATABASE_URL` has not been set yet.
class ServerProbe {
  const ServerProbe({
    required this.reachable,
    required this.databaseReady,
    this.latencyMs,
    required this.detail,
  });

  final bool reachable;
  final bool databaseReady;
  final int? latencyMs;

  /// One short line to show the user, always populated.
  final String detail;

  /// Everything needed for an online account to work.
  bool get isReady => reachable && databaseReady;
}
