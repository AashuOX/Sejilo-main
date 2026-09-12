// online_chat_page.dart — 100% Instagram Direct Messaging
// Features: Instagram Direct Header, "Notes" bubble row, Gradient chat bubbles,
// Double-tap heart reaction on messages, Media attachments, and Read receipts.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../core/image_utils.dart';
import '../design_system/components/hybrid_status_badge.dart';
import '../design_system/components/sejilo_state_views.dart';
import '../design_system/sejilo_theme.dart';
import 'group/create_group_page.dart';
import 'online_messaging_controller.dart';

class OnlineConversationsPage extends StatelessWidget {
  const OnlineConversationsPage({required this.controller, super.key});
  final OnlineMessagingController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              controller.auth.profile?.username ?? 'Direct',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_rounded, size: 22),
            tooltip: 'New group',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CreateGroupPage(
                  onCreate: (name) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Group "$name" created')),
                    );
                  },
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_square, size: 22),
            onPressed: () => _startNewChat(context),
          ),
        ],
      ),
      body: OnlineConversationsView(
        messagingController: controller,
        authController: controller.auth,
      ),
    );
  }

  void _startNewChat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NewChatSheet(
        messagingController: controller,
        authController: controller.auth,
        onUserSelected: (user) async {
          Navigator.pop(context);
          final conv = await controller.startConversationWith(user);
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OnlineChatRoomPage(
                  conversationId: conv.id,
                  messagingController: controller,
                  authController: controller.auth,
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Online Conversations View
// ─────────────────────────────────────────────

class OnlineConversationsView extends StatefulWidget {
  const OnlineConversationsView({
    required this.messagingController,
    required this.authController,
    super.key,
  });

  final OnlineMessagingController messagingController;
  final AccountAuthController authController;

  @override
  State<OnlineConversationsView> createState() => _OnlineConversationsViewState();
}

class _OnlineConversationsViewState extends State<OnlineConversationsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(OnlineConversation conv) {
    widget.messagingController.markAsRead(conv.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineChatRoomPage(
          conversationId: conv.id,
          messagingController: widget.messagingController,
          authController: widget.authController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.messagingController,
      builder: (context, _) {
        final allConvs = widget.messagingController.conversations;
        final filteredConvs = _searchQuery.isEmpty
            ? allConvs
            : allConvs.where((c) {
                final u = c.participant.username.toLowerCase();
                final d = c.participant.displayName.toLowerCase();
                final q = _searchQuery.toLowerCase();
                return u.contains(q) || d.contains(q);
              }).toList();

        return Column(
          children: [
            // Search Box
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search, size: 20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                    filled: false,
                  ),
                ),
              ),
            ),

            // ── Instagram "Notes" Row ─────────────────
            _DirectNotesRow(auth: widget.authController),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Direct & Mesh Chats', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),

            // ── Conversations List ───────────────────
            Expanded(
              child: filteredConvs.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: SejiloEmptyView(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'No conversations yet',
                          description: 'Connect and chat in real-time with online friends or offline mesh peers.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: filteredConvs.length,
                      itemBuilder: (context, index) {
                        final conv = filteredConvs[index];
                        final unread = conv.unreadCount > 0;

                        return ListTile(
                          onTap: () => _openChat(conv),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: conv.participant.avatarBytes != null
                                    ? MemoryImage(conv.participant.avatarBytes!)
                                    : null,
                                child: conv.participant.avatarBytes == null
                                    ? Text(
                                        conv.participant.displayName.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10D876),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            conv.participant.displayName,
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            conv.lastMessage?.text ?? 'Active now',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.w700 : FontWeight.normal,
                              color: unread ? theme.colorScheme.onSurface : Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (unread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: SejiloColors.instaBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(Icons.camera_alt_outlined, size: 22, color: Colors.grey),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Instagram "Notes" Row
// ─────────────────────────────────────────────

class _DirectNotesRow extends StatelessWidget {
  const _DirectNotesRow({required this.auth});
  final AccountAuthController auth;

  @override
  Widget build(BuildContext context) {
    final profile = auth.profile;
    final displayName = profile?.displayName ?? 'You';
    final avatarBytes = profile?.avatarBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Your note prompt
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('💡 Notes feature is linked to your profile bio & stories'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                      child: avatarBytes == null
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                            )
                          : null,
                    ),
                    Positioned(
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withValues(alpha: .2)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Text(
                          'Share a note...',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your note',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Instagram Direct Chat Room
// ─────────────────────────────────────────────

class OnlineChatRoomPage extends StatefulWidget {
  const OnlineChatRoomPage({
    required this.conversationId,
    required this.messagingController,
    required this.authController,
    super.key,
  });

  final String conversationId;
  final OnlineMessagingController messagingController;
  final AccountAuthController authController;

  @override
  State<OnlineChatRoomPage> createState() => _OnlineChatRoomPageState();
}

class _OnlineChatRoomPageState extends State<OnlineChatRoomPage> {
  final _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  OnlineMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    widget.messagingController.loadMessages(widget.conversationId);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.messagingController.sendTyping(
      widget.conversationId,
      _textController.text.trim().isNotEmpty,
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    final replyId = _replyingTo?.id;
    setState(() => _replyingTo = null);

    widget.messagingController.sendMessage(
      conversationId: widget.conversationId,
      text: text,
      replyToMessageId: replyId,
    );
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes != null) {
      final optimized = await ImageUtils.optimizeImage(file!.bytes!);
      widget.messagingController.sendMessage(
        conversationId: widget.conversationId,
        text: '📷 Photo attachment',
        mediaBytes: optimized.bytes,
        mediaMimeType: optimized.mimeType,
      );
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageOptions(OnlineMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick emoji reaction bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['❤️', '😂', '🔥', '😮', '😢', '👍'].map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.messagingController.addReaction(msg.id, emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyingTo = msg);
                  },
                ),
                if (msg.isMe)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Unsend message', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.messagingController.deleteMessage(widget.conversationId, msg.id);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return const Icon(Icons.access_time_rounded, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.read:
        return const Icon(Icons.done_all, size: 12, color: SejiloColors.accent);
      case MessageDeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.messagingController,
      builder: (context, _) {
        final conv = widget.messagingController.getConversation(widget.conversationId);
        final messages = widget.messagingController.getMessages(widget.conversationId);

        if (conv == null) {
          return const Scaffold(body: Center(child: Text('Chat not found.')));
        }

        final isTyping = conv.typingUsers.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: conv.participant.avatarBytes != null ? MemoryImage(conv.participant.avatarBytes!) : null,
                  child: conv.participant.avatarBytes == null
                      ? Text(conv.participant.displayName.isNotEmpty ? conv.participant.displayName[0] : 'U')
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      isTyping
                          ? 'typing…'
                          : (conv.isOnline ? 'Active now' : 'Offline'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isTyping
                            ? SejiloColors.primary
                            : (conv.isOnline ? const Color(0xFF10D876) : Colors.grey),
                        fontWeight: isTyping ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: AnimatedBuilder(
                    animation: widget.messagingController.hybridManager,
                    builder: (context, _) => HybridStatusBadge(
                      networkState: widget.messagingController.hybridManager.networkState,
                      activityState: widget.messagingController.hybridManager.activityState,
                      peerCount: widget.messagingController.hybridManager.activeMeshPeerCount,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Messages list
                Expanded(
                  child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i];

                    return GestureDetector(
                      onDoubleTap: () => widget.messagingController.addReaction(msg.id, '❤️'),
                      onLongPress: () => _showMessageOptions(msg),
                      child: Align(
                        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Column(
                            crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: msg.isMe ? SejiloColors.dmGradient : null,
                                  color: msg.isMe ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (msg.replyToMessageId != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        margin: const EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.reply, size: 12, color: Colors.white70),
                                            SizedBox(width: 4),
                                            Text(
                                              'Replying to message',
                                              style: TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (msg.mediaBytes != null) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(msg.mediaBytes!),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Text(
                                      msg.text,
                                      style: TextStyle(
                                        color: msg.isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (msg.isMe) ...[
                                      const SizedBox(height: 2),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: _buildStatusIcon(msg.status),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (msg.reactions.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 4,
                                  children: msg.reactions.map((r) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                                      ),
                                      child: Text(r.emoji, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Replying preview banner
              if (_replyingTo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to: ${_replyingTo!.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _replyingTo = null),
                      ),
                    ],
                  ),
                ),

              // Bottom Input Bar
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      // Camera / Photo picker
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: SejiloColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          onPressed: _sendPhoto,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Text Field
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: TextField(
                            controller: _textController,
                            decoration: const InputDecoration(
                              hintText: 'Message...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                              filled: false,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      IconButton(
                        icon: const Icon(Icons.image_outlined, size: 24),
                        onPressed: _sendPhoto,
                      ),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: SejiloColors.primary, size: 24),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }
}

// ─────────────────────────────────────────────
// New Chat Search Bottom Sheet
// ─────────────────────────────────────────────

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({
    required this.messagingController,
    required this.authController,
    required this.onUserSelected,
  });

  final OnlineMessagingController messagingController;
  final AccountAuthController authController;
  final ValueChanged<PublicProfile> onUserSelected;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _searchController = TextEditingController();
  List<PublicProfile> _users = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await widget.authController.searchUsers(query.trim());
      setState(() => _users = results);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                const Expanded(
                  child: Text('New message', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_rounded, color: SejiloColors.primary),
            title: const Text('Create group', style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CreateGroupPage(
                  onCreate: (name) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Group "$name" created')),
                    );
                  },
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'To: Search...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, i) {
                      final u = _users[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(u.displayName.substring(0, 1)),
                        ),
                        title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('@${u.username}'),
                        onTap: () => widget.onUserSelected(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Delivery State Icon
// ─────────────────────────────────────────────

/// Compact delivery status indicator:
/// pending ◷, sent ✓, relaying ◷ (amber pulse), delivered ✓✓, read ✓✓ (primary), failed ✗, expired ⊘
class DeliveryStateIcon extends StatefulWidget {
  const DeliveryStateIcon({required this.status, super.key});
  final MessageDeliveryStatus status;

  @override
  State<DeliveryStateIcon> createState() => _DeliveryStateIconState();
}

class _DeliveryStateIconState extends State<DeliveryStateIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(DeliveryStateIcon old) {
    super.didUpdateWidget(old);
    _updateAnimation();
  }

  void _updateAnimation() {
    final animating = widget.status == MessageDeliveryStatus.relaying ||
        widget.status == MessageDeliveryStatus.sending;
    if (animating && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!animating && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.status) {
      MessageDeliveryStatus.sending => AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Icon(
            Icons.access_time_rounded,
            size: 13,
            color: Colors.white.withAlpha((120 + _ctrl.value * 100).toInt()),
          ),
        ),
      MessageDeliveryStatus.sent => const Icon(
          Icons.check_rounded,
          size: 13,
          color: Colors.white70,
        ),
      MessageDeliveryStatus.relaying => AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Icon(
            Icons.sync_rounded,
            size: 13,
            color: SejiloColors.statusOffline.withAlpha(
              (140 + _ctrl.value * 100).toInt(),
            ),
          ),
        ),
      MessageDeliveryStatus.delivered => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: Colors.white70),
            Icon(Icons.check_rounded, size: 12, color: Colors.white70),
          ],
        ),
      MessageDeliveryStatus.read => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: SejiloColors.primary),
            Icon(Icons.check_rounded, size: 12, color: SejiloColors.primary),
          ],
        ),
      MessageDeliveryStatus.failed => const Icon(
          Icons.close_rounded,
          size: 13,
          color: SejiloColors.danger,
        ),
      MessageDeliveryStatus.expired => const Icon(
          Icons.block_rounded,
          size: 13,
          color: Colors.white38,
        ),
    };
  }
}

// ─────────────────────────────────────────────
// Mesh Status Banner
// ─────────────────────────────────────────────

/// Shown above the input bar when the device is offline but has mesh peers
/// nearby. Informs the user that messages will relay via BLE mesh.
class MeshStatusBanner extends StatelessWidget {
  const MeshStatusBanner({required this.peerCount, super.key});
  final int peerCount;

  @override
  Widget build(BuildContext context) {
    if (peerCount == 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: SejiloColors.statusMesh.withAlpha(28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth, size: 14, color: SejiloColors.statusMesh),
          const SizedBox(width: 6),
          Text(
            'Mesh: $peerCount peer${peerCount != 1 ? "s" : ""} nearby · Messages will relay',
            style: const TextStyle(
              fontSize: 12,
              color: SejiloColors.statusMesh,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
