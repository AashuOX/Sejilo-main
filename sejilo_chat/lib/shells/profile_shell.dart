import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/image_utils.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_app_bar.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/components/sejilo_state_views.dart';
import '../../design_system/sejilo_theme.dart';
import '../../auth/account_auth_controller.dart';
import '../../core/app_preferences.dart';
import '../../core/mesh_client.dart';
import '../../profile/follow_requests_page.dart';
import '../../settings/settings_page.dart';
import 'comments_sheet.dart';

class ProfileShell extends StatefulWidget {
  const ProfileShell({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;

  /// The live instances, handed down so Settings writes to the objects the app
  /// actually reads. Passing null used to make Settings build throwaway copies,
  /// so every switch in there changed nothing.
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<ProfileShell> createState() => _ProfileShellState();
}

class _ProfileShellState extends State<ProfileShell> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PublicProfile? _publicProfile;
  List<SocialPost> _userPosts = [];
  List<SocialPost> _savedPosts = [];
  bool _isLoading = true;
  String? _loadError;
  int _followRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfileData();
    // The grid badges read a preference, so redraw when Settings changes one.
    _prefs?.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Device settings: the instance handed down by the shell, falling back to the
  /// one the auth controller holds so the getter works whichever way this page
  /// was constructed.
  AppPreferences? get _prefs => widget.preferences ?? widget.auth.preferences;

  /// Honours Settings → Content preferences → "Hide like and comment counts".
  bool get _hideCounts => _prefs?.hideLikeCounts ?? false;

  /// Says why a like or a save did not land. [setLike] and [setSave] have
  /// already rolled their own state back before this runs.
  void _reportActionFailure(Object error) {
    if (!mounted) return;
    final message =
        error is ApiException ? error.message : 'Could not reach the server.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Loads counts, posts and saves. Each call is caught on its own so one
  /// failing request cannot leave the whole screen on its skeleton — which is
  /// what happened once loadPublicProfile started reporting server errors
  /// instead of inventing a profile.
  Future<void> _loadProfileData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final username = widget.auth.profile?.username ?? '';
    if (username.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    PublicProfile? prof;
    var posts = const <SocialPost>[];
    var saved = const <SocialPost>[];
    String? error;
    try {
      prof = await widget.auth.loadPublicProfile(username);
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Your counts could not be refreshed — the server could not be '
          'reached.';
    }
    try {
      posts = await widget.auth.loadUserPosts(username);
    } catch (_) {
      error ??= 'Your posts could not be loaded.';
    }
    try {
      saved = await widget.auth.loadSavedPosts();
    } catch (_) {
      error ??= 'Your saved posts could not be loaded.';
    }

    // Pending follow requests, so the badge counts real rows rather than
    // appearing on every profile.
    var requests = 0;
    try {
      requests = (await widget.auth.getFollowRequests()).length;
    } catch (_) {
      requests = _followRequestCount;
    }

    if (!mounted) return;
    setState(() {
      if (prof != null) _publicProfile = prof;
      _userPosts = posts;
      _savedPosts = saved;
      _followRequestCount = requests;
      _loadError = error;
      _isLoading = false;
    });
  }

  void _openEditProfileSheet() {
    final cur = widget.auth.profile;
    final nameController = TextEditingController(text: cur?.displayName ?? '');
    final bioController = TextEditingController(text: cur?.bio ?? '');
    Uint8List? newAvatarBytes = cur?.avatarBytes;
    String? newAvatarMime = cur?.avatarMimeType;
    bool removeAvatar = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final surfaceColor = isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface;
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              children: [
                // Header
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const Text(
                        'Edit Profile',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await widget.auth.updateProfile(
                              username: cur?.username ?? 'user',
                              displayName: nameController.text.trim(),
                              bio: bioController.text.trim(),
                              avatarBytes: newAvatarBytes,
                              avatarMimeType: newAvatarMime,
                              removeAvatar: removeAvatar,
                            );
                          } catch (e) {
                            // The sheet used to close before the save was even
                            // attempted, so a rejected edit looked like it had
                            // been applied. Keep it open with the reason.
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Could not save profile: $e')),
                              );
                            }
                            return;
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadProfileData();
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.bold, color: SejiloColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Avatar picker
                      Center(
                        child: Column(
                          children: [
                            SejiloAvatar(
                              name: nameController.text.isNotEmpty ? nameController.text : 'User',
                              imageBytes: removeAvatar ? null : newAvatarBytes,
                              size: SejiloAvatarSize.xl,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      final res = await FilePicker.platform.pickFiles(
                                        type: FileType.image,
                                        withData: true,
                                      );
                                      if (res != null && res.files.single.bytes != null) {
                                        // Downscale before it ever reaches the
                                        // API, and record the format the
                                        // optimiser actually produced instead
                                        // of assuming JPEG.
                                        final optimized = await ImageUtils.optimizeImage(
                                          res.files.single.bytes!,
                                          maxDimension: ImageUtils.maxAvatarDimension,
                                        );
                                        setSheetState(() {
                                          newAvatarBytes = optimized.bytes;
                                          newAvatarMime = optimized.mimeType;
                                          removeAvatar = false;
                                        });
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(content: Text('Could not use that photo: $e')),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Change photo'),
                                ),
                                if (newAvatarBytes != null || cur?.avatarBytes != null) ...[
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {
                                      setSheetState(() {
                                        newAvatarBytes = null;
                                        newAvatarMime = null;
                                        removeAvatar = true;
                                      });
                                    },
                                    child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Display Name', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 6),
                      SejiloInput(
                        controller: nameController,
                        hintText: 'Your name',
                      ),
                      const SizedBox(height: 16),
                      const Text('Bio', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 6),
                      SejiloInput(
                        controller: bioController,
                        hintText: 'Tell the world about yourself',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.auth.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final postsCount = _userPosts.length;
    final followersCount = _publicProfile?.followersCount ?? 0;
    final followingCount = _publicProfile?.followingCount ?? 0;

    return Scaffold(
      appBar: SejiloAppBar(
        title: profile?.username ?? 'Profile',
        actions: [
          if (_followRequestCount > 0 || (profile?.isPrivate ?? false))
            IconButton(
              tooltip: 'Follow requests',
              icon: Badge(
                isLabelVisible: _followRequestCount > 0,
                label: Text('$_followRequestCount'),
                child: const Icon(Icons.person_add_alt_outlined, size: 24),
              ),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FollowRequestsPage(auth: widget.auth),
                  ),
                );
                if (mounted) await _loadProfileData();
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 24),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    auth: widget.auth,
                    preferences: widget.preferences,
                    meshClient: widget.meshClient,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 720,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _isLoading
              ? const SejiloProfileSkeleton()
              : RefreshIndicator(
                  onRefresh: _loadProfileData,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // What did not load. Counts fall back to the last values
                      // that did, so the numbers on screen are never invented.
                      if (_loadError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 16,
                                  color:
                                      Theme.of(context).colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _loadError!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadProfileData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      // Header Row: Avatar + Stats
                      Row(
                        children: [
                          SejiloAvatar(
                            imageBytes: profile?.avatarBytes,
                            name: profile?.displayName ?? 'User',
                            size: SejiloAvatarSize.lg,
                            hasStoryRing: true,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStat('$postsCount', 'Posts'),
                                _buildStat('$followersCount', 'Followers'),
                                _buildStat('$followingCount', 'Following'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Name & Bio
                      Text(
                        profile?.displayName ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (profile?.bio.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile!.bio,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Profile Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: SejiloButton(
                              label: 'Edit profile',
                              variant: SejiloButtonVariant.secondary,
                              height: 36,
                              onPressed: _openEditProfileSheet,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SejiloButton(
                              label: 'Share profile',
                              variant: SejiloButtonVariant.secondary,
                              height: 36,
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Profile link copied: https://sejilochat.net/@${profile?.username}'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Tab Bar
                      TabBar(
                        controller: _tabController,
                        indicatorColor: SejiloColors.primary,
                        labelColor: SejiloColors.primary,
                        unselectedLabelColor: Colors.grey,
                        tabs: const [
                          Tab(icon: Icon(Icons.grid_on_rounded, size: 22)),
                          Tab(icon: Icon(Icons.bookmark_border_rounded, size: 24)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Own Posts Grid
                  _buildPostsGrid(_userPosts, emptyTitle: 'No posts yet', emptyDesc: 'When you share photos, they will appear here on your profile.'),
                  // Tab 2: Saved Posts Grid
                  _buildPostsGrid(_savedPosts, emptyTitle: 'No saved posts', emptyDesc: 'Save photos and videos that you want to see again.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostsGrid(List<SocialPost> posts, {required String emptyTitle, required String emptyDesc}) {
    if (_isLoading) {
      return const Center(child: SejiloLoadingView(message: 'Loading posts…'));
    }

    if (posts.isEmpty) {
      return SejiloEmptyView(
        icon: Icons.photo_library_outlined,
        title: emptyTitle,
        description: emptyDesc,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
        childAspectRatio: 1.0,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return GestureDetector(
          onTap: () => _showPostDetail(post),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                post.media,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.withValues(alpha: 0.2),
                  child: const Icon(Icons.photo_outlined, color: Colors.grey),
                ),
              ),
              if (post.likes > 0 && !_hideCounts)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 10, color: Colors.white),
                        const SizedBox(width: 2),
                        Text('${post.likes}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPostDetail(SocialPost post) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: SejiloAvatar(
                    name: post.displayName,
                    imageBytes: post.avatarBytes,
                    size: SejiloAvatarSize.sm,
                  ),
                  title: Text(post.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(post.displayName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Image.memory(post.media, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              post.liked ? Icons.favorite : Icons.favorite_border,
                              color: post.liked ? SejiloColors.primary : null,
                            ),
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              try {
                                await widget.auth.setLike(post.id, !post.liked);
                              } catch (e) {
                                navigator.pop();
                                _reportActionFailure(e);
                                return;
                              }
                              navigator.pop();
                              _loadProfileData();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: () {
                              Navigator.pop(ctx);
                              CommentsSheet.show(context, widget.auth, post.id);
                            },
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              post.saved ? Icons.bookmark : Icons.bookmark_border,
                              color: post.saved ? SejiloColors.accent : null,
                            ),
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              try {
                                await widget.auth.setSave(post.id, !post.saved);
                              } catch (e) {
                                navigator.pop();
                                _reportActionFailure(e);
                                return;
                              }
                              navigator.pop();
                              _loadProfileData();
                            },
                          ),
                        ],
                      ),
                      if (post.caption.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(ctx).style,
                            children: [
                              TextSpan(text: '${post.username} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: post.caption),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
