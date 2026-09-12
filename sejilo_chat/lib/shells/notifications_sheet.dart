import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_state_views.dart';
import '../../design_system/sejilo_theme.dart';

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key, required this.auth});

  final AccountAuthController auth;

  static Future<void> show(BuildContext context, AccountAuthController auth) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationsSheet(auth: auth),
    );
  }

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  bool _isLoading = true;
  List<SocialNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final list = await widget.auth.loadNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
      await widget.auth.markNotificationsRead();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_notifications.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await widget.auth.markNotificationsRead();
                      setState(() {});
                    },
                    child: const Text('Mark all read', style: TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: SejiloLoadingView(message: 'Loading notifications…'))
                : _notifications.isEmpty
                    ? const SejiloEmptyView(
                        icon: Icons.notifications_none_rounded,
                        title: 'No notifications yet',
                        description: 'When people like, comment, or follow you, you\'ll see them here.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            final n = _notifications[index];
                            return _NotificationTile(notification: n);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final SocialNotification notification;

  @override
  Widget build(BuildContext context) {
    final actor = notification.actor;
    String actionText;
    IconData icon;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.like:
        actionText = 'liked your post.';
        icon = Icons.favorite_rounded;
        iconColor = SejiloColors.primary;
        break;
      case NotificationType.comment:
        actionText = 'commented on your post.';
        icon = Icons.chat_bubble_rounded;
        iconColor = SejiloColors.secondary;
        break;
      case NotificationType.follow:
        actionText = 'started following you.';
        icon = Icons.person_add_rounded;
        iconColor = SejiloColors.accent;
        break;
      case NotificationType.message:
        actionText = 'sent you a message.';
        icon = Icons.chat_outlined;
        iconColor = Colors.blue;
        break;
      case NotificationType.meshMessage:
        actionText = 'sent a mesh message.';
        icon = Icons.sensors_rounded;
        iconColor = SejiloColors.highlight;
        break;
    }

    final displayName = actor?.displayName ?? actor?.username ?? 'Someone';
    final username = actor?.username ?? 'someone';

    return ListTile(
      leading: Stack(
        children: [
          SejiloAvatar(
            name: displayName,
            imageBytes: actor?.avatarBytes,
            size: SejiloAvatarSize.md,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 12),
            ),
          ),
        ],
      ),
      title: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: ' $actionText'),
          ],
        ),
      ),
      subtitle: Text(
        _formatTimeAgo(notification.createdAt),
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      trailing: notification.postMediaBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                notification.postMediaBytes!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          : null,
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
