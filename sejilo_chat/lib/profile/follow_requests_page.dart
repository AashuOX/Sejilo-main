// follow_requests_page.dart — accept or decline the people waiting to follow
// a private account.
//
// The backend has created FollowRequest rows since STEP 27 and the API to
// accept or reject them existed, but nothing in the app ever listed them: a
// private account could receive requests and never act on them. Both actions
// here hit the server and the row disappears only after it confirms.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/components/sejilo_state_views.dart';
import 'public_profile_page.dart';

class FollowRequestsPage extends StatefulWidget {
  const FollowRequestsPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<FollowRequestsPage> createState() => _FollowRequestsPageState();
}

class _FollowRequestsPageState extends State<FollowRequestsPage> {
  List<_FollowRequest> _requests = const [];
  bool _loading = true;
  String? _error;

  /// Requester ids with an accept/decline in flight, so a double tap cannot
  /// send the same decision twice.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.auth.getFollowRequests();
      final parsed = raw.map(_FollowRequest.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _requests = parsed;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Requests could not be loaded — the server could not be '
            'reached.';
        _loading = false;
      });
    }
  }

  Future<void> _decide(_FollowRequest request, bool accept) async {
    if (_busy.contains(request.requesterId)) return;
    setState(() => _busy.add(request.requesterId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (accept) {
        await widget.auth.acceptFollowRequest(request.requesterId);
      } else {
        await widget.auth.rejectFollowRequest(request.requesterId);
      }
      if (!mounted) return;
      setState(() {
        _requests = _requests
            .where((r) => r.requesterId != request.requesterId)
            .toList(growable: false);
        _busy.remove(request.requesterId);
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(accept
              ? '@${request.username} now follows you.'
              : 'Request from @${request.username} declined.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _busy.remove(request.requesterId));
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) setState(() => _busy.remove(request.requesterId));
      messenger.showSnackBar(const SnackBar(
        content: Text('Nothing changed — the server could not be reached.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Follow requests',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SejiloLoadingView(message: 'Loading requests…');
    }
    if (_error != null) {
      return SejiloErrorView(message: _error!, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return const SejiloEmptyView(
        icon: Icons.person_add_alt_outlined,
        title: 'No pending requests',
        description: 'When someone asks to follow your private account, they '
            'show up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final request = _requests[index];
          final busy = _busy.contains(request.requesterId);
          return ListTile(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PublicProfilePage(
                  username: request.username,
                  auth: widget.auth,
                ),
              ),
            ),
            leading: SejiloAvatar(
              imageBytes: request.avatarBytes,
              name: request.displayName.isEmpty
                  ? request.username
                  : request.displayName,
              size: SejiloAvatarSize.md,
            ),
            title: Text(
              request.displayName.isEmpty
                  ? '@${request.username}'
                  : request.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('@${request.username}'),
            trailing: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: () => _decide(request, true),
                        child: const Text('Confirm'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _decide(request, false),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _FollowRequest {
  const _FollowRequest({
    required this.requesterId,
    required this.username,
    required this.displayName,
    this.avatarBytes,
  });

  final String requesterId;
  final String username;
  final String displayName;
  final Uint8List? avatarBytes;

  factory _FollowRequest.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>?;
    final data = avatar?['data'] as String?;
    return _FollowRequest(
      requesterId: (json['requesterId'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      avatarBytes: data == null
          ? null
          : Uint8List.fromList(base64Url.decode(base64Url.normalize(data))),
    );
  }
}
