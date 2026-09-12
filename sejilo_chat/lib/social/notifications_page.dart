import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';

// ─────────────────────────────────────────────
// Notifications page — likes, comments, follows, messages
// ─────────────────────────────────────────────

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<SocialNotification>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.auth.isAuthenticated
        ? widget.auth.loadNotifications()
        : Future.value([]);
  }

  Future<void> _refresh() async {
    setState(_load);
  }

  Future<void> _markRead(SocialNotification notif) async {
    try {
      await widget.auth.markNotificationRead(notif.id);
      setState(_load);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_rounded, size: 52),
                SizedBox(height: 16),
                Text('Sign in to see notifications',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await widget.auth.markAllNotificationsRead();
                setState(_load);
              } catch (_) {}
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<SocialNotification>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final notifs = snap.data ?? [];
            if (notifs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 56),
                    SizedBox(height: 12),
                    Text('No notifications yet',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text('Likes, comments and follows will appear here.'),
                  ],
                ),
              );
            }
            return ListView.separated(
              itemCount: notifs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _NotifTile(
                notif: notifs[i],
                onRead: () => _markRead(notifs[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Notification tile
// ─────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.notif, required this.onRead});
  final SocialNotification notif;
  final VoidCallback onRead;

  IconData get _icon {
    return switch (notif.type) {
      NotificationType.like => Icons.favorite_rounded,
      NotificationType.comment => Icons.chat_bubble_rounded,
      NotificationType.follow => Icons.person_add_rounded,
      NotificationType.message => Icons.forum_rounded,
      NotificationType.meshMessage => Icons.bluetooth_rounded,
    };
  }

  Color _iconColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (notif.type) {
      NotificationType.like => const Color(0xFFE53935),
      NotificationType.comment => scheme.primary,
      NotificationType.follow => const Color(0xFF43A047),
      NotificationType.message => scheme.primary,
      NotificationType.meshMessage => const Color(0xFF0288D1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      tileColor: notif.read
          ? null
          : scheme.primary.withValues(alpha: .05),
      leading: CircleAvatar(
        backgroundColor: _iconColor(context).withValues(alpha: .15),
        child: Icon(_icon, color: _iconColor(context), size: 20),
      ),
      title: Text(
        notif.text ?? (notif.actor != null ? '${notif.actor!.username} interacted with you' : 'New notification'),
        style: TextStyle(
          fontWeight: notif.read ? FontWeight.normal : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        _timeAgo(notif.createdAt),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: notif.read
          ? null
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
      onTap: notif.read ? null : onRead,
    );
  }
}

// ─────────────────────────────────────────────
// Helper
// ─────────────────────────────────────────────

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
