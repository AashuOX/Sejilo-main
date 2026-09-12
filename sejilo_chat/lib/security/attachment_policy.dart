import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class AttachmentPolicy {
  const AttachmentPolicy._();

  static const maximumBytes = 96 * 1024;
  static const allowedTypes = {'photo', 'voice', 'file'};

  static bool accepts(String type, List<int> bytes) {
    if (!allowedTypes.contains(type) ||
        bytes.isEmpty ||
        bytes.length > maximumBytes) {
      return false;
    }
    return switch (type) {
      'photo' => _startsWith(
          bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      'voice' => bytes.length >= 12 &&
          ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp',
      'file' => true,
      _ => false,
    };
  }

  static Future<String> safeStorageName(String messageId, String type) async {
    if (!allowedTypes.contains(type) ||
        messageId.isEmpty ||
        messageId.length > 128) {
      throw ArgumentError('Invalid attachment identity.');
    }
    final digest =
        await Sha256().hash(utf8.encode('sejilo-attachment-v1|$messageId'));
    final encoded = base64Url.encode(digest.bytes).replaceAll('=', '');
    final extension = switch (type) {
      'photo' => 'png',
      'voice' => 'm4a',
      _ => 'bin',
    };
    return '$encoded.$extension';
  }

  static bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (value[index] != prefix[index]) return false;
    }
    return true;
  }
}
