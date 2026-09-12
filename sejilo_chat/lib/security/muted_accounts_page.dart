// muted_accounts_page.dart — the accounts whose notifications are silenced.
//
// A mute is a `Block` row with `isMuted: true` on the server: the person can
// still see you and message you, their alerts just stay quiet. Unmuting is the
// only action here — muting itself happens from the person's profile.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/components/sejilo_state_views.dart';
import '../settings/settings_section.dart';

class MutedAccountsPage extends StatefulWidget {
  const MutedAccountsPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<MutedAccountsPage> createState() => _MutedAccountsPageState();
}

class _MutedAccountsPageState extends State<MutedAccountsPage> {
  List<MutedUser>? _muted;
  String? _error;
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.auth.loadMutedUsers();
      if (!mounted) return;
      setState(() => _muted = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    }
  }

  Future<void> _unmute(MutedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending.add(user.id));
    try {
      await widget.auth.setMuted(user.username, false);
      if (!mounted) return;
      setState(() {
        _muted = [
          for (final entry in _muted ?? const <MutedUser>[])
            if (entry.id != user.id) entry,
        ];
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Notifications from @${user.username} are on again')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Muted accounts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return SejiloErrorView(
        title: 'Muted accounts unavailable',
        message: _error!,
        onRetry: _load,
      );
    }
    final muted = _muted;
    if (muted == null) {
      return const SejiloLoadingView(message: 'Loading muted accounts…');
    }
    if (muted.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: const SejiloEmptyView(
              icon: Icons.notifications_off_outlined,
              title: 'Nobody is muted',
              description:
                  'Mute someone from their profile to stop their notifications '
                  'without blocking them. They are never told.',
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: muted.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final user = muted[index];
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
            '@${user.username} · muted ${settingsRelativeDate(user.mutedAt)}',
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: () => _unmute(user),
                  child: const Text('Unmute'),
                ),
        );
      },
    );
  }
}
