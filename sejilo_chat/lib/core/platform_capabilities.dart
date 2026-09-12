import 'dart:io';
import 'package:flutter/foundation.dart';

/// Central platform capability registry.
/// Query this instead of sprinkling `Platform.isAndroid` / `kIsWeb` everywhere.
abstract final class PlatformCapabilities {
  /// True on Android and iOS — the only platforms that have Bluetooth/mesh.
  static bool get meshSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True on web, Windows, macOS, Linux.
  static bool get isDesktopOrWeb =>
      kIsWeb ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  /// Human-readable label for the current platform.
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
