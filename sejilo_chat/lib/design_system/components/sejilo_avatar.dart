import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../sejilo_theme.dart';

enum SejiloAvatarSize { xs, sm, md, lg, xl }

class SejiloAvatar extends StatelessWidget {
  const SejiloAvatar({
    super.key,
    this.imageBytes,
    Uint8List? bytes,
    this.imageUrl,
    String? label,
    this.name = '',
    this.size = SejiloAvatarSize.md,
    this.customSize,
    this.hasStoryRing = false,
    this.hasUnseenStory = true,
    this.isOnline = false,
    this.onTap,
  })  : _bytes = bytes ?? imageBytes;

  final Uint8List? imageBytes;
  final Uint8List? _bytes;
  final String? imageUrl;
  final String name;
  final SejiloAvatarSize size;
  final double? customSize;
  final bool hasStoryRing;
  final bool hasUnseenStory;
  final bool isOnline;
  final VoidCallback? onTap;

  double get _dimension {
    if (customSize != null) return customSize!;
    switch (size) {
      case SejiloAvatarSize.xs:
        return 28;
      case SejiloAvatarSize.sm:
        return 38;
      case SejiloAvatarSize.md:
        return 50;
      case SejiloAvatarSize.lg:
        return 72;
      case SejiloAvatarSize.xl:
        return 96;
    }
  }

  double get _fontSize {
    if (customSize != null) return customSize! * 0.4;
    switch (size) {
      case SejiloAvatarSize.xs:
        return 11;
      case SejiloAvatarSize.sm:
        return 14;
      case SejiloAvatarSize.md:
        return 18;
      case SejiloAvatarSize.lg:
        return 26;
      case SejiloAvatarSize.xl:
        return 34;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = _dimension;

    Widget avatarContent;
    if (_bytes != null && _bytes.isNotEmpty) {
      avatarContent = ClipOval(
        child: Image.memory(
          _bytes,
          width: dim,
          height: dim,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(isDark),
        ),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatarContent = ClipOval(
        child: Image.network(
          imageUrl!,
          width: dim,
          height: dim,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(isDark),
        ),
      );
    } else {
      avatarContent = _buildFallback(isDark);
    }

    Widget fullAvatar = avatarContent;

    if (hasStoryRing) {
      final ringPadding = dim > 60 ? 3.0 : 2.0;
      fullAvatar = Container(
        padding: EdgeInsets.all(ringPadding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: hasUnseenStory ? SejiloColors.sejiloGradient : null,
          color: hasUnseenStory ? null : (isDark ? SejiloColors.darkOutline : SejiloColors.lightOutline),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
          ),
          child: avatarContent,
        ),
      );
    }

    if (isOnline) {
      fullAvatar = Stack(
        clipBehavior: Clip.none,
        children: [
          fullAvatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dim * 0.28,
              height: dim * 0.28,
              decoration: BoxDecoration(
                color: SejiloColors.statusOnline,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? SejiloColors.darkBg : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: fullAvatar);
    }

    return fullAvatar;
  }

  Widget _buildFallback(bool isDark) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';
    final colors = Colors.primaries;
    final color = colors[name.hashCode.abs() % colors.length];

    return Container(
      width: _dimension,
      height: _dimension,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(isDark ? 80 : 40),
        border: Border.all(
          color: color.withAlpha(isDark ? 160 : 120),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
