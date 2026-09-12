// blocked_users_page.dart — the real block list, served by the API.
//
// The previous version of this screen kept two invented usernames in a local
// list and answered "Unblocked @x" with a SnackBar while the server was never
// told anything. Everything here goes through `/v1/users/...`.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/components/sejilo_state_views.dart';
import '../settings/settings_section.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<BlockedUser>? _blocked;
  String? _error;

  /// Ids with a request in flight, so a row can show a spinner and refuse a
  /// second tap without freezing the whole list.
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.auth.loadBlockedUsers();
      if (!mounted) return;
      setState(() => _blocked = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unblock @${user.username}?'),
        content: const Text(
          'They will be able to find your profile, follow you and message you '
          'again. They are not told that you blocked them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _pending.add(user.id));
    try {
      await widget.auth.unblockUser(user.username);
      if (!mounted) return;
      setState(() {
        _blocked = [
          for (final entry in _blocked ?? const <BlockedUser>[])
            if (entry.id != user.id) entry,
        ];
      });
      messenger.showSnackBar(
        SnackBar(content: Text('@${user.username} is no longer blocked')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the server.')),
      );
    } finally {
      if (mounted) setState(() => _pending.remove(user.id));
    }
  }

  Future<void> _blockByUsername() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block an account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            prefixText: '@',
            labelText: 'Username',
            helperText: 'They will not be able to find or message you.',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = (username ?? '').trim().replaceFirst('@', '');
    if (trimmed.isEmpty || !mounted) return;

    try {
      await widget.auth.blockUser(trimmed);
      await _load();
      messenger.showSnackBar(SnackBar(content: Text('Blocked @$trimmed')));
    } on ApiException catch (e) {
      // A 404 here is the normal "no such username" case, so it reads as advice
      // rather than a failure.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.statusCode == 404 ? 'No account called @$trimmed.' : e.message,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the server.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blocked accounts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Block an account',
            onPressed: _blockByUsername,
            icon: const Icon(Icons.person_add_disabled_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return SejiloErrorView(
        title: 'Blocked accounts unavailable',
        message: _error!,
        onRetry: _load,
      );
    }
    final blocked = _blocked;
    if (blocked == null) {
      return const SejiloLoadingView(message: 'Loading blocked accounts…');
    }
    if (blocked.isEmpty) {
      // ListView keeps pull-to-refresh working on an empty list.
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: SejiloEmptyView(
              icon: Icons.block_outlined,
              title: 'No blocked accounts',
              description:
                  'When you block someone they cannot find your profile, '
                  'follow you or message you. Anyone you block shows up here.',
              actionLabel: 'Block an account',
              onAction: _blockByUsername,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: blocked.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final user = blocked[index];
        final busy = _pending.contains(user.id);
        return ListTile(
          leading: SejiloAvatar(
            bytes: user.avatarBytes,
            name: user.displayName.isEmpty ? user.username : user.displayName,
            size: SejiloAvatarSize.sm,
          ),
          title: Text(
            user.displayName.isEmpty ? '@${user.username}' : user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '@${user.username} · blocked ${settingsRelativeDate(user.blockedAt)}',
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: () => _unblock(user),
                  child: const Text('Unblock'),
                ),
        );
      },
    );
  }
}
