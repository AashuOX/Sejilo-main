// profile_page.dart — 100% Instagram-Style Profile
// Features: Story Highlights row, Grid/Reels/Saved/Tagged tabs, Followers/Following modal,
// Edit Profile bottom sheet, and Share Profile card.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../core/app_preferences.dart';
import '../core/image_utils.dart';
import '../core/mesh_client.dart';
import '../design_system/sejilo_theme.dart';
import '../social/create_post_page.dart';
import '../social/post_detail_page.dart';
import '../social/reels/reels_viewer_page.dart';
import '../settings/settings_page.dart';
import 'public_profile_page.dart';

class OwnProfilePage extends StatefulWidget {
  const OwnProfilePage({
    required this.auth,
    this.preferences,
    this.meshClient,
    super.key,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<OwnProfilePage> createState() => _OwnProfilePageState();
}

class _OwnProfilePageState extends State<OwnProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Future<List<SocialPost>> _postsFuture;
  late Future<int> _followersFuture;
  late Future<int> _followingFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _reload();
  }

  void _reload() {
    if (widget.auth.isAuthenticated && widget.auth.profile != null) {
      final username = widget.auth.profile!.username;
      _postsFuture = widget.auth.loadUserPosts(username);
      _followersFuture = widget.auth.loadFollowers(username).then((list) => list.length);
      _followingFuture = widget.auth.loadFollowing(username).then((list) => list.length);
    } else {
      _postsFuture = Future.value([]);
      _followersFuture = Future.value(0);
      _followingFuture = Future.value(0);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Opens the composer, then refreshes the grid so a new post appears without
  /// having to leave and come back.
  Future<void> _openComposer() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreatePostPage(auth: widget.auth),
      ),
    );
    if (mounted) setState(_reload);
  }

  void _openEdit() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditProfileSheet(auth: widget.auth),
    );
    setState(_reload);
  }

  void _openFollowersList(String title) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final username = widget.auth.profile?.username ?? '';
        final isFollowers = title.toLowerCase().contains('follower');
        final future = isFollowers
            ? widget.auth.loadFollowers(username)
            : widget.auth.loadFollowing(username);

        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<PublicProfile>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final users = snapshot.data ?? const [];
                    if (users.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No users to show.'),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, i) => _FollowListRow(
                        auth: widget.auth,
                        user: users[i],
                        // The backend can unfollow someone you follow
                        // (DELETE /v1/users/:id/follow) but has no way to
                        // eject one of your followers, so the Following list
                        // is the only one that gets an action button.
                        canUnfollow: !isFollowers,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showShareProfileDialog() {
    final profile = widget.auth.profile;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SejiloColors.storyGradient,
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: profile?.avatarBytes != null
                      ? MemoryImage(profile!.avatarBytes!)
                      : null,
                  child: profile?.avatarBytes == null
                      ? Text(
                          (profile?.displayName ?? 'U').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile?.displayName ?? 'You',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              Text(
                '@${profile?.username ?? 'you'}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2_rounded, size: 100),
              ),
              const SizedBox(height: 14),
              const Text('Scan to follow on SejiloChat', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings and privacy'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(
                        auth: widget.auth,
                        preferences: widget.preferences ?? AppPreferences(),
                        meshClient: widget.meshClient,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_rounded),
                title: const Text('QR code'),
                onTap: () {
                  Navigator.pop(context);
                  _showShareProfileDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_border_rounded),
                title: const Text('Saved'),
                onTap: () {
                  Navigator.pop(context);
                  _tabs.animateTo(2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: const Text('Log out', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.auth.logout();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Sign in to view your profile.')),
      );
    }

    final profile = widget.auth.profile!;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 16),
            const SizedBox(width: 6),
            Text(
              profile.username,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, size: 24),
            tooltip: 'New post',
            onPressed: _openComposer,
          ),
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            onPressed: _showMenu,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: NestedScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Avatar + Stats Row ───────────────
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SejiloColors.storyGradient,
                            ),
                            child: CircleAvatar(
                              radius: 38,
                              backgroundColor: Colors.grey[300],
                              backgroundImage: profile.avatarBytes != null
                                  ? MemoryImage(profile.avatarBytes!)
                                  : null,
                              child: profile.avatarBytes == null
                                  ? Text(
                                      profile.displayName.substring(0, 1).toUpperCase(),
                                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: FutureBuilder<int>(
                              future: Future.wait([_postsFuture, _followersFuture, _followingFuture])
                                  .then((values) => values[0] as List<SocialPost>)
                                  .then((posts) => posts.length),
                              builder: (context, snapshot) {
                                final postsCount = snapshot.data ?? 0;
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _StatColumn(label: 'Posts', count: _formatCount(postsCount)),
                                    GestureDetector(
                                      onTap: () => _openFollowersList('Followers'),
                                      child: FutureBuilder<int>(
                                        future: _followersFuture,
                                        builder: (context, snapshot) {
                                          final count = snapshot.data ?? 0;
                                          return _StatColumn(label: 'Followers', count: _formatCount(count));
                                        },
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _openFollowersList('Following'),
                                      child: FutureBuilder<int>(
                                        future: _followingFuture,
                                        builder: (context, snapshot) {
                                          final count = snapshot.data ?? 0;
                                          return _StatColumn(label: 'Following', count: _formatCount(count));
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Name & Bio ───────────────────────
                      Text(
                        profile.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      if (profile.bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.bio,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // ── Edit Profile & Share Profile Buttons ──
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _openEdit,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _showShareProfileDialog,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Share profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Story Highlights Row ─────────────
                      _StoryHighlightsRow(),
                    ],
                  ),
                ),
              ),

              // ── Instagram Tab Bar ─────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: TabBarDelegate(
                  TabBar(
                    controller: _tabs,
                    indicatorColor: Theme.of(context).colorScheme.onSurface,
                    indicatorWeight: 1.5,
                    labelColor: Theme.of(context).colorScheme.onSurface,
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on_rounded, size: 22)),
                      Tab(icon: Icon(Icons.movie_creation_outlined, size: 22)),
                      Tab(icon: Icon(Icons.bookmark_border_rounded, size: 22)),
                      Tab(icon: Icon(Icons.account_box_outlined, size: 22)),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabs,
              children: [
                // 1. Grid Posts
                _buildPostsGrid(),

                // 2. Reels
                _buildReelsGrid(),

                // 3. Saved Bookmarks
                _buildSavedGrid(),

                // 4. Tagged
                _buildTaggedGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostsGrid() {
    return FutureBuilder<List<SocialPost>>(
      future: _postsFuture,
      builder: (context, snap) {
        final posts = snap.data ?? [];
        if (posts.isEmpty) {
          return const Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No Posts Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final p = posts[i];
            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PostDetailPage(post: p, auth: widget.auth),
                  ),
                );
              },
              child: p.media.length > 200
                  ? Image.memory(
                      p.media,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.primaries[i % Colors.primaries.length].withValues(alpha: .6),
                        child: const Center(
                          child: Icon(Icons.image_outlined, color: Colors.white70),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.primaries[i % Colors.primaries.length].withValues(alpha: .6),
                      child: const Center(
                        child: Icon(Icons.image_outlined, color: Colors.white70),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildReelsGrid() {
    final reels = widget.auth.posts
        .where((p) => p.media.isNotEmpty)
        .take(6)
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: reels.length,
      itemBuilder: (context, i) {
        final post = reels[i];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReelsViewerPage(
                  posts: reels,
                  initialIndex: i,
                ),
              ),
            );
          },
          child: Image.memory(
            post.media,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[900],
              child: const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSavedGrid() {
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Saved Photos & Videos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text('Only you can see what you have saved.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTaggedGrid() {
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_box_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Photos of you', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text("When people tag you in photos, they'll appear here.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// One row of the Followers / Following sheet
// ─────────────────────────────────────────────

class _FollowListRow extends StatefulWidget {
  const _FollowListRow({
    required this.auth,
    required this.user,
    required this.canUnfollow,
  });

  final AccountAuthController auth;
  final PublicProfile user;
  final bool canUnfollow;

  @override
  State<_FollowListRow> createState() => _FollowListRowState();
}

class _FollowListRowState extends State<_FollowListRow> {
  late bool _following = widget.canUnfollow;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final next = !_following;
    setState(() {
      _busy = true;
      _following = next;
    });
    try {
      await widget.auth.setFollow(widget.user.username, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PublicProfilePage(username: u.username, auth: widget.auth),
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: Colors.grey[300],
        backgroundImage:
            u.avatarBytes != null ? MemoryImage(u.avatarBytes!) : null,
        child: u.avatarBytes == null
            ? Text(u.displayName.isEmpty
                ? '?'
                : u.displayName.substring(0, 1).toUpperCase())
            : null,
      ),
      title: Text(u.username,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      subtitle: Text(u.displayName,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: widget.canUnfollow
          ? OutlinedButton(
              onPressed: _busy ? null : _toggle,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_following ? 'Unfollow' : 'Follow',
                      style: const TextStyle(fontSize: 12)),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────
// Story Highlights Row
// ─────────────────────────────────────────────

class _StoryHighlightsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final highlights = [
      {'name': 'Travel ✈️', 'icon': Icons.flight_takeoff_rounded},
      {'name': 'Work 💻', 'icon': Icons.laptop_mac_rounded},
      {'name': 'Vibes ✨', 'icon': Icons.auto_awesome_rounded},
      {'name': 'Food 🍕', 'icon': Icons.restaurant_rounded},
    ];

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...highlights.map((h) {
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withValues(alpha: .3), width: 1.5),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4),
                    ),
                    child: Icon(h['icon'] as IconData, size: 24),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    h['name'] as String,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.withValues(alpha: .3), width: 1.5),
                  ),
                  child: const Icon(Icons.add, size: 24),
                ),
                const SizedBox(height: 4),
                const Text('New', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────
// Stat Column Helper Widget
// ─────────────────────────────────────────────

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.count});

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

String _formatCount(int count) {
  if (count >= 1_000_000) {
    return '${(count / 1_000_000).toStringAsFixed(1)}m';
  }
  if (count >= 1_000) {
    return '${(count / 1_000).toStringAsFixed(1)}k';
  }
  return count.toString();
}

// ─────────────────────────────────────────────
// Tab Bar Delegate for Pinned Profile Tabs
// ─────────────────────────────────────────────

class TabBarDelegate extends SliverPersistentHeaderDelegate {
  const TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(TabBarDelegate oldDelegate) => false;
}

// ─────────────────────────────────────────────
// Edit Profile Bottom Sheet
// ─────────────────────────────────────────────

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  Uint8List? _avatarBytes;
  String? _avatarMimeType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.auth.profile;
    _nameController.text = profile?.displayName ?? '';
    _usernameController.text = profile?.username ?? '';
    _bioController.text = profile?.bio ?? '';
    _avatarBytes = profile?.avatarBytes;
    _avatarMimeType = profile?.avatarMimeType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes != null) {
      final optimized = await ImageUtils.optimizeImage(
        file!.bytes!,
        maxDimension: ImageUtils.maxAvatarDimension,
      );
      setState(() {
        _avatarBytes = optimized.bytes;
        _avatarMimeType = optimized.mimeType;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.auth.updateProfile(
        username: _usernameController.text.trim(),
        displayName: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        avatarBytes: _avatarBytes,
        avatarMimeType: _avatarMimeType,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, color: SejiloColors.instaBlue, size: 26),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _avatarBytes != null ? MemoryImage(_avatarBytes!) : null,
                  child: _avatarBytes == null ? const Icon(Icons.person, size: 44) : null,
                ),
                TextButton(
                  onPressed: _pickAvatar,
                  child: const Text('Edit picture', style: TextStyle(fontWeight: FontWeight.w700, color: SejiloColors.instaBlue)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
        ],
      ),
    );
  }
}
