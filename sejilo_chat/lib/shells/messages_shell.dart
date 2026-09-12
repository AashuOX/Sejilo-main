import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../../core/responsive.dart';
import '../../design_system/components/hybrid_status_badge.dart';
import '../../messaging/online_chat_page.dart';
import '../../messaging/online_messaging_controller.dart';
import '../../profile/public_profile_page.dart';

class MessagesShell extends StatefulWidget {
  const MessagesShell({super.key, required this.auth});

  final AccountAuthController auth;

  @override
  State<MessagesShell> createState() => _MessagesShellState();
}

class _MessagesShellState extends State<MessagesShell> {
  late OnlineMessagingController _messagingController;

  @override
  void initState() {
    super.initState();
    _messagingController = OnlineMessagingController(auth: widget.auth);
  }

  @override
  void dispose() {
    _messagingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              widget.auth.profile?.username ?? 'Messages',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _messagingController.hybridManager,
              builder: (context, _) => HybridStatusBadge(
                networkState: _messagingController.hybridManager.networkState,
                activityState: _messagingController.hybridManager.activityState,
                peerCount: _messagingController.hybridManager.activeMeshPeerCount,
                compact: true,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square, size: 22),
            onPressed: () => _startNewChat(context),
          ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 680,
          child: OnlineConversationsView(
            messagingController: _messagingController,
            authController: widget.auth,
          ),
        ),
      ),
    );
  }

  void _startNewChat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => _NewChatDialog(
        messagingController: _messagingController,
        authController: widget.auth,
      ),
    );
  }
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog({
    required this.messagingController,
    required this.authController,
  });

  final OnlineMessagingController messagingController;
  final AccountAuthController authController;

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _searchController = TextEditingController();
  List<PublicProfile> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await widget.authController.searchUsers(q);
      if (mounted) setState(() => _searchResults = results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'New Message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: _performSearch,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search people by username or name…',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Type a username to start chatting'
                              : 'No users found matching "${_searchController.text}"',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, idx) {
                          final user = _searchResults[idx];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U'),
                            ),
                            title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('@${user.username}'),
                            onTap: () async {
                              Navigator.pop(context);
                              final conv = await widget.messagingController.startConversationWith(user);
                              if (context.mounted) {
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
                            },
                            onLongPress: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PublicProfilePage(username: user.username, auth: widget.authController),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
