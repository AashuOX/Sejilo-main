import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum NotificationLevel { all, important, none }

enum AutoDownloadPolicy { never, trustedPeers, everyone }

class AppPreferences extends ChangeNotifier {
  AppPreferences({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  ThemeMode _themeMode = ThemeMode.system;
  NotificationLevel _notificationLevel = NotificationLevel.all;
  AutoDownloadPolicy _autoDownloadPolicy = AutoDownloadPolicy.trustedPeers;
  bool _notificationPreviews = false;
  bool _notificationSound = true;
  bool _trustedOnly = false;
  bool _aiEnabled = false;
  bool _cloudAiEnabled = false;
  bool _aiSmartReplies = false;
  bool _aiTranslation = false;
  bool _aiSummaries = false;
  bool _aiTranscription = false;
  bool _aiSemanticSearch = false;
  bool _aiPriorityMessages = false;
  bool _aiScamDetection = false;
  bool _auroraEffects = true;
  bool _hideLikeCounts = false;
  bool _highQualityUploads = true;
  List<String> _hiddenWords = const [];

  ThemeMode get themeMode => _themeMode;
  NotificationLevel get notificationLevel => _notificationLevel;
  AutoDownloadPolicy get autoDownloadPolicy => _autoDownloadPolicy;
  bool get notificationPreviews => _notificationPreviews;
  bool get notificationSound => _notificationSound;
  bool get trustedOnly => _trustedOnly;
  bool get aiEnabled => _aiEnabled;
  bool get cloudAiEnabled => _cloudAiEnabled;
  bool get aiSmartReplies => _aiSmartReplies;
  bool get aiTranslation => _aiTranslation;
  bool get aiSummaries => _aiSummaries;
  bool get aiTranscription => _aiTranscription;
  bool get aiSemanticSearch => _aiSemanticSearch;
  bool get aiPriorityMessages => _aiPriorityMessages;
  bool get aiScamDetection => _aiScamDetection;
  bool get auroraEffects => _auroraEffects;

  /// Hides like and comment counts everywhere they are shown.
  ///
  /// A viewing preference for this device: the counts still exist server-side,
  /// they are simply not drawn.
  bool get hideLikeCounts => _hideLikeCounts;

  /// When false, photos are uploaded at a smaller longest edge to save data.
  bool get highQualityUploads => _highQualityUploads;

  /// Words that hide a comment from this device's view when it contains one.
  ///
  /// Client-side only: the API has no hidden-words field, so this filters what
  /// you see rather than what other people can post.
  List<String> get hiddenWords => List.unmodifiable(_hiddenWords);

  Future<void> load() async {
    try {
      final values = await Future.wait([
        _storage.read(key: 'settings.theme.v1'),
        _storage.read(key: 'settings.notifications.v1'),
        _storage.read(key: 'settings.auto_download.v1'),
        _storage.read(key: 'settings.notification_previews.v1'),
        _storage.read(key: 'settings.notification_sound.v1'),
        _storage.read(key: 'settings.trusted_only.v1'),
        _storage.read(key: 'settings.ai.enabled.v1'),
        _storage.read(key: 'settings.ai.cloud.v1'),
        _storage.read(key: 'settings.ai.smart_replies.v1'),
        _storage.read(key: 'settings.ai.translation.v1'),
        _storage.read(key: 'settings.ai.summaries.v1'),
        _storage.read(key: 'settings.ai.transcription.v1'),
        _storage.read(key: 'settings.ai.semantic_search.v1'),
        _storage.read(key: 'settings.ai.priority.v1'),
        _storage.read(key: 'settings.ai.scam.v1'),
        _storage.read(key: 'settings.aurora.v1'),
        _storage.read(key: 'settings.hide_like_counts.v1'),
        _storage.read(key: 'settings.high_quality_uploads.v1'),
        _storage.read(key: 'settings.hidden_words.v1'),
      ]);
      _themeMode = _enumValue(ThemeMode.values, values[0], ThemeMode.system);
      _notificationLevel = _enumValue(
        NotificationLevel.values,
        values[1],
        NotificationLevel.all,
      );
      _autoDownloadPolicy = _enumValue(
        AutoDownloadPolicy.values,
        values[2],
        AutoDownloadPolicy.trustedPeers,
      );
      _notificationPreviews = values[3] == 'true';
      _notificationSound = values[4] != 'false';
      _trustedOnly = values[5] == 'true';
      _aiEnabled = values[6] == 'true';
      _cloudAiEnabled = _aiEnabled && values[7] == 'true';
      _aiSmartReplies = values[8] == 'true';
      _aiTranslation = values[9] == 'true';
      _aiSummaries = values[10] == 'true';
      _aiTranscription = values[11] == 'true';
      _aiSemanticSearch = values[12] == 'true';
      _aiPriorityMessages = values[13] == 'true';
      _aiScamDetection = values[14] == 'true';
      _auroraEffects = values[15] != 'false';
      _hideLikeCounts = values[16] == 'true';
      _highQualityUploads = values[17] != 'false';
      _hiddenWords = _decodeWords(values[18]);
    } on Exception {
      // Defaults keep the app usable if platform secure storage is temporarily
      // unavailable. Sensitive identity/message storage still fails closed in
      // MeshClient and is surfaced to the user there.
    }
    notifyListeners();
  }

  T _enumValue<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((value) => value.name == name).firstOrNull ?? fallback;

  static List<String> _decodeWords(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((word) => word.trim().toLowerCase())
            .where((word) => word.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Corrupt entry — start from an empty list rather than failing to load
      // every other preference alongside it.
    }
    return const [];
  }

  Future<void> setHideLikeCounts(bool value) async {
    _hideLikeCounts = value;
    notifyListeners();
    await _storage.write(key: 'settings.hide_like_counts.v1', value: '$value');
  }

  Future<void> setHighQualityUploads(bool value) async {
    _highQualityUploads = value;
    notifyListeners();
    await _storage.write(
        key: 'settings.high_quality_uploads.v1', value: '$value');
  }

  /// Adds a word to the hidden-words list, ignoring duplicates and case.
  Future<void> addHiddenWord(String word) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty || _hiddenWords.contains(normalized)) return;
    _hiddenWords = [..._hiddenWords, normalized];
    notifyListeners();
    await _writeHiddenWords();
  }

  Future<void> removeHiddenWord(String word) async {
    final normalized = word.trim().toLowerCase();
    if (!_hiddenWords.contains(normalized)) return;
    _hiddenWords =
        _hiddenWords.where((entry) => entry != normalized).toList(growable: false);
    notifyListeners();
    await _writeHiddenWords();
  }

  /// True when [text] contains one of the hidden words.
  ///
  /// Matched on word boundaries so "ass" does not hide "class"; a multi-word
  /// entry is matched as a plain substring.
  bool isHidden(String text) {
    if (_hiddenWords.isEmpty || text.isEmpty) return false;
    final haystack = text.toLowerCase();
    for (final word in _hiddenWords) {
      if (word.contains(' ')) {
        if (haystack.contains(word)) return true;
        continue;
      }
      final pattern = RegExp(
        '(?<![a-z0-9])${RegExp.escape(word)}(?![a-z0-9])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(haystack)) return true;
    }
    return false;
  }

  Future<void> _writeHiddenWords() => _storage.write(
        key: 'settings.hidden_words.v1',
        value: jsonEncode(_hiddenWords),
      );

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    notifyListeners();
    await _storage.write(key: 'settings.theme.v1', value: value.name);
  }

  Future<void> setNotificationLevel(NotificationLevel value) async {
    _notificationLevel = value;
    notifyListeners();
    await _storage.write(key: 'settings.notifications.v1', value: value.name);
  }

  Future<void> setAutoDownloadPolicy(AutoDownloadPolicy value) async {
    _autoDownloadPolicy = value;
    notifyListeners();
    await _storage.write(key: 'settings.auto_download.v1', value: value.name);
  }

  Future<void> setNotificationPreviews(bool value) async {
    _notificationPreviews = value;
    notifyListeners();
    await _storage.write(
        key: 'settings.notification_previews.v1', value: '$value');
  }

  Future<void> setNotificationSound(bool value) async {
    _notificationSound = value;
    notifyListeners();
    await _storage.write(
        key: 'settings.notification_sound.v1', value: '$value');
  }

  Future<void> setTrustedOnly(bool value) async {
    _trustedOnly = value;
    notifyListeners();
    await _storage.write(key: 'settings.trusted_only.v1', value: '$value');
  }

  Future<void> setAiEnabled(bool value) async {
    _aiEnabled = value;
    if (!value) _cloudAiEnabled = false;
    notifyListeners();
    await _storage.write(key: 'settings.ai.enabled.v1', value: '$value');
    if (!value) {
      await _storage.write(key: 'settings.ai.cloud.v1', value: 'false');
    }
  }

  Future<void> setCloudAiEnabled(bool value) async {
    _cloudAiEnabled = _aiEnabled && value;
    notifyListeners();
    await _storage.write(
      key: 'settings.ai.cloud.v1',
      value: '$_cloudAiEnabled',
    );
  }

  Future<void> setAiSmartReplies(bool value) =>
      _setAiOption('smart_replies', value, (next) => _aiSmartReplies = next);
  Future<void> setAiTranslation(bool value) =>
      _setAiOption('translation', value, (next) => _aiTranslation = next);
  Future<void> setAiSummaries(bool value) =>
      _setAiOption('summaries', value, (next) => _aiSummaries = next);
  Future<void> setAiTranscription(bool value) =>
      _setAiOption('transcription', value, (next) => _aiTranscription = next);
  Future<void> setAiSemanticSearch(bool value) => _setAiOption(
      'semantic_search', value, (next) => _aiSemanticSearch = next);
  Future<void> setAiPriorityMessages(bool value) =>
      _setAiOption('priority', value, (next) => _aiPriorityMessages = next);
  Future<void> setAiScamDetection(bool value) =>
      _setAiOption('scam', value, (next) => _aiScamDetection = next);

  Future<void> setAuroraEffects(bool value) async {
    _auroraEffects = value;
    notifyListeners();
    await _storage.write(key: 'settings.aurora.v1', value: '$value');
  }

  Future<void> _setAiOption(
    String key,
    bool value,
    void Function(bool) update,
  ) async {
    update(value);
    notifyListeners();
    await _storage.write(key: 'settings.ai.$key.v1', value: '$value');
  }

  Future<void> clearAiData() async {
    await _storage.delete(key: 'ai.private.records.v1');
  }
}
