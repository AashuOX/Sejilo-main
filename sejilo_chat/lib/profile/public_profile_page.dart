import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../security/report_sheet.dart';
import '../social/post_detail_page.dart';
import 'profile_page.dart' show TabBarDelegate, EditProfileSheet;

// ─────────────────────────────────────────────
// Public/other user profile page
// ─────────────────────────────────────────────

class PublicProfilePage extends StatelessWidget {
  const PublicProfilePage({
    required this.username,
    required this.auth,
    super.key,
  });

  final String username;
  final AccountAuthController auth;

  @override
  Widget build(BuildContext context) {
    return UserProfilePage(controller: auth, username: username);
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    required this.controller,
    required this.username,
    super.key,
  });

  final AccountAuthController controller;
  final String username;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late Future<PublicProfile> _profileFuture;
  late Future<List<SocialPost>> _postsFuture;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 1, vsync: this);
    _reload();
  }

  void _reload() {
    _profileFuture =
        widget.controller.loadPublicProfile(widget.username);
    _postsFuture = _startPostsRequest();
  }

  /// Starts the grid request.
  ///
  /// `ignore()` does not swallow the failure — the `FutureBuilder` still
  /// receives it and draws the notice. What it stops is Dart reporting the
  /// rejection as an *unhandled* error during the window before that builder
  /// subscribes: the grid is fetched alongside the profile, but the grid's
  /// builder is only created once the profile has arrived, so a 403 that comes
  /// back first would otherwise be logged as uncaught.
  Future<List<SocialPost>> _startPostsRequest() =>
      widget.controller.loadUserPosts(widget.username)..ignore();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow(PublicProfile profile) async {
    try {
      late final PublicProfile updated;
      if (profile.followedByViewer) {
        updated = await widget.controller.setFollow(profile.username, false);
      } else if (profile.followRequestPending) {
        updated = await widget.controller.setFollow(profile.username, false);
      } else {
        updated = await widget.controller.requestFollow(profile.username);
      }
      if (!mounted) return;
      setState(() {
        _profileFuture = Future.value(updated);
        // On a private account the grid is gated by the follow edge, so the
        // lock notice has to appear — or clear — along with the button rather
        // than only on the next visit to the page.
        if (profile.isPrivate) {
          _postsFuture = _startPostsRequest();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Widget _buildFollowButton(PublicProfile profile) {
    final isFollowing = profile.followedByViewer;
    final isPending = profile.followRequestPending;

    if (isFollowing) {
      return FilledButton(
        onPressed: widget.controller.isBusy ? null : () => _toggleFollow(profile),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: const Text('Following'),
      );
    }

    if (isPending) {
      return FilledButton(
        onPressed: widget.controller.isBusy ? null : () => _toggleFollow(profile),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: const Text('Requested'),
      );
    }

    return FilledButton(
      onPressed: widget.controller.isBusy ? null : () => _toggleFollow(profile),
      child: const Text('Follow'),
    );
  }

  Future<void> _sendMessageRequest(PublicProfile profile) async {
    try {
      final textController = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Message @${profile.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write a message request...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  Navigator.pop(context, textController.text.trim());
                }
              },
              child: const Text('Send'),
            ),
          ],
        ),
      );

      if (result != null && result.isNotEmpty) {
        await widget.controller.sendMessageRequest(profile.username, result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message request sent.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _openMessageRequest(PublicProfile profile) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('@${profile.username}'),
        content: const Text('Message request pending or already connected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Report / mute / block, with the state the server reports for this viewer
  /// so a muted account offers "Unmute" instead of muting a second time.
  void _showMenu(PublicProfile profile) {
    final blocked = profile.blockedByViewer;
    final muted = profile.mutedByViewer;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!blocked)
              ListTile(
                leading: Icon(muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined),
                title: Text(muted ? 'Unmute' : 'Mute'),
                subtitle: Text(muted
                    ? 'Their posts and alerts come back.'
                    : 'Stops their alerts. They are not told, and you stay '
                        'able to message each other.'),
                onTap: () {
                  Navigator.pop(context);
                  _setMuted(profile, !muted);
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report user'),
              onTap: () {
                Navigator.pop(context);
                _showReport(profile);
              },
            ),
            if (blocked)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('Unblock user'),
                onTap: () {
                  Navigator.pop(context);
                  _unblock(profile);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Block user'),
                subtitle: const Text(
                    'Removes any follow between you and stops messages.'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () {
                  Navigator.pop(context);
                  _block(profile);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMuted(PublicProfile profile, bool mute) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.setMuted(profile.username, mute);
      if (!mounted) return;
      setState(_reload);
      messenger.showSnackBar(SnackBar(
        content: Text(mute
            ? '@${profile.username} muted. Manage this under Settings › '
                'Privacy and security.'
            : '@${profile.username} unmuted.'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Nothing changed — the server could not be reached.'),
      ));
    }
  }

  Future<void> _block(PublicProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block @${profile.username}?'),
        content: const Text(
          'Any follow between you is removed and you will not be able to '
          'message each other. They are not told that you blocked them. You '
          'can undo this from Settings › Privacy and security.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.blockUser(profile.username);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('@${profile.username} blocked.')),
      );
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        setState(_reload);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Not blocked — the server could not be reached.'),
      ));
    }
  }

  Future<void> _unblock(PublicProfile profile) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.unblockUser(profile.username);
      if (!mounted) return;
      setState(_reload);
      messenger.showSnackBar(
        SnackBar(content: Text('@${profile.username} unblocked.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Not unblocked — the server could not be reached.'),
      ));
    }
  }

  /// Reports the account, then says what happened. The previous version threw
  /// the error away, so a rejected report looked the same as a sent one.
  Future<void> _showReport(PublicProfile profile) async {
    final submission = await showReportSheet(
      context,
      title: 'Report @${profile.username}',
    );
    if (submission == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.reportUser(
        profile.username,
        submission.reason,
        details: submission.details,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Report sent. It is listed under Settings › Privacy and security.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report not sent — the server could not be reached.'),
        ),
      );
    }
  }

  bool get _isOwn =>
      widget.controller.profile?.username == widget.username;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PublicProfile>(
      future: _profileFuture,
      builder: (context, snap) {
        final profile = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              profile != null ? '@${profile.username}' : 'Profile',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              if (profile != null && !_isOwn)
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => _showMenu(profile),
                ),
            ],
          ),
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snap.hasError
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 52),
                            const SizedBox(height: 12),
                            Text('Profile unavailable: ${snap.error}',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => setState(_reload),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildProfile(profile!),
        );
      },
    );
  }

  /// What to draw where the grid would be when the posts could not be read.
  ///
  /// Three different things arrive here as one error, and they do not mean the
  /// same thing to the reader: an account that is private, an account that is
  /// unavailable because one side blocked the other, and a server that could
  /// not be reached. Only the last one is worth a retry.
  Widget _buildGridNotice(PublicProfile profile, Object? error) {
    final scheme = Theme.of(context).colorScheme;
    final status = error is ApiException ? error.statusCode : null;

    late final IconData icon;
    late final String title;
    late final String detail;
    var canRetry = false;

    if (profile.isPrivate && !profile.followedByViewer) {
      icon = Icons.lock_outline_rounded;
      title = 'This account is private';
      detail = 'Follow @${profile.username} to see their photos and videos.';
    } else if (status == 403) {
      icon = Icons.block_outlined;
      title = 'This account is not available';
      detail = 'You cannot see these posts.';
    } else {
      icon = Icons.wifi_off_rounded;
      title = 'Posts could not be loaded';
      detail = error is ApiException
          ? error.message
          : 'The server could not be reached.';
      canRetry = true;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: scheme.onSurface.withValues(alpha: .45)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: .6)),
            ),
            if (canRetry) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(_reload),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(PublicProfile profile) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _PublicProfileHeader(
                profile: profile,
                isOwn: _isOwn,
                controller: widget.controller,
                onFollowToggled: () => _toggleFollow(profile),
                onEdit: _isOwn
                    ? () async {
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => EditProfileSheet(auth: widget.controller),
                        );
                        setState(_reload);
                      }
                    : null,
                followButton: _buildFollowButton(profile),
                onMessagePressed: !_isOwn
                    ? () {
                        if (profile.followedByViewer || profile.followRequestPending) {
                          _openMessageRequest(profile);
                        } else {
                          _sendMessageRequest(profile);
                        }
                      }
                    : null,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: TabBarDelegate(
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_on_rounded)),
                  ],
                ),
              ),
            ),
          ],
          body: FutureBuilder<List<SocialPost>>(
            future: _postsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              // A refusal is not an empty account. The server answers 403 for a
              // private account the viewer does not follow and for a block, and
              // that used to be drawn as "No posts yet".
              if (snap.hasError) {
                return _buildGridNotice(profile, snap.error);
              }
              final posts = snap.data ?? [];
              if (posts.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 56),
                      SizedBox(height: 12),
                      Text('No posts yet',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }
              return GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: posts.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailPage(
                          post: posts[i], auth: widget.controller),
                    ),
                  ),
                  child: Image.memory(
                    posts[i].media,
                    fit: BoxFit.cover,
                    // A tile whose bytes will not decode stays a tile: without
                    // this the whole grid row raised to a red error box.
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.withValues(alpha: 0.2),
                      child: const Icon(Icons.photo_outlined,
                          color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Header for public profile
// ─────────────────────────────────────────────

class _PublicProfileHeader extends StatelessWidget {
  const _PublicProfileHeader({
    required this.profile,
    required this.isOwn,
    required this.controller,
    required this.onFollowToggled,
    this.onEdit,
    this.followButton,
    this.onMessagePressed,
  });

  final PublicProfile profile;
  final bool isOwn;
  final AccountAuthController controller;
  final VoidCallback onFollowToggled;
  final VoidCallback? onEdit;
  final Widget? followButton;
  final VoidCallback? onMessagePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: profile.avatarBytes != null
                    ? MemoryImage(profile.avatarBytes!)
                    : null,
                child: profile.avatarBytes == null
                    ? Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 28),
                      )
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Each stat takes a third of what is left beside the avatar.
                    // At their natural widths the three labels overflow a 400px
                    // screen — "Followers" and "Following" are wide words — so
                    // the row has to share the space rather than ask for it.
                    Expanded(child: _Stat(label: 'Posts', value: profile.postsCount)),
                    Expanded(
                        child: _Stat(
                            label: 'Followers', value: profile.followersCount)),
                    Expanded(
                        child: _Stat(
                            label: 'Following', value: profile.followingCount)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(profile.displayName,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16)),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(profile.bio, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: isOwn
                    ? OutlinedButton(
                        onPressed: onEdit,
                        child: const Text('Edit profile'),
                      )
                    : followButton ??
                        FilledButton(
                          onPressed: controller.isBusy ? null : onFollowToggled,
                          style: profile.followedByViewer
                              ? FilledButton.styleFrom(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surface,
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                )
                              : null,
                          child: Text(profile.followedByViewer
                              ? 'Following'
                              : 'Follow'),
                        ),
              ),
              if (!isOwn && onMessagePressed != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onMessagePressed,
                  child: Text(profile.followedByViewer || profile.followRequestPending
                      ? 'Message'
                      : 'Request'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          // Ellipsis rather than an overflow stripe when the device is set to a
          // large text scale.
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ],
      );
}
