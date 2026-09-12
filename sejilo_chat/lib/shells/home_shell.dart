import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_app_bar.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_state_views.dart';
import '../../design_system/sejilo_theme.dart';
import '../../auth/account_auth_controller.dart';
import '../../security/report_sheet.dart';
import 'comments_sheet.dart';
import 'notifications_sheet.dart';
import 'share_post_sheet.dart';
import 'story_creator_screen.dart';
import 'story_viewer_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.auth, this.onOpenMessages});

  final AccountAuthController auth;

  /// Lets the app bar's chat icon actually put the Messages tab on screen.
  /// `MainShell` owns the tab index, so it hands the feed a way to ask for it
  /// rather than the feed telling the reader to go and find the tab.
  final VoidCallback? onOpenMessages;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scrollController = ScrollController();
  List<SocialPost> _posts = [];
  List<UserStoryGroup> _storyGroups = [];
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _followingFeed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoadingMore && _nextCursor != null) {
        _loadMore();
      }
    }
  }

  /// Tells the reader that a like or a save did not land. The controller has
  /// already undone its optimistic change by the time this runs, so the row is
  /// left showing the state the server actually holds.
  void _reportActionFailure(Object error) {
    if (!mounted) return;
    final message =
        error is ApiException ? error.message : 'Could not reach the server.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Which endpoint the two chips stand for. `/v1/feed` is already scoped to the
  /// accounts you follow and `/v1/explore` is the global timeline, and both page
  /// by cursor, so switching tabs only changes which one is called — no backend
  /// work was needed for this.
  Future<FeedPage> _fetchPage({String? cursor}) => _followingFeed
      ? widget.auth.loadFeed(cursor: cursor)
      : widget.auth.loadExplore(cursor: cursor);

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _fetchPage(),
      widget.auth.loadGroupedStories(),
    ]);

    if (mounted) {
      final feedPage = results[0] as FeedPage;
      final stories = results[1] as List<UserStoryGroup>;
      setState(() {
        // Copied rather than adopted: the offline fallback hands back an
        // unmodifiable list, and this one is appended to by _loadMore and
        // written in place by the like and save handlers.
        _posts = List<SocialPost>.of(feedPage.posts);
        _nextCursor = feedPage.nextCursor;
        _storyGroups = stories;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStories() async {
    final stories = await widget.auth.loadGroupedStories();
    if (mounted) {
      setState(() {
        _storyGroups = stories;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null) return;
    setState(() => _isLoadingMore = true);
    final page = await _fetchPage(cursor: _nextCursor);
    if (mounted) {
      setState(() {
        _posts.addAll(page.posts);
        _nextCursor = page.nextCursor;
        _isLoadingMore = false;
      });
    }
  }

  void _setFeedMode(bool following) {
    if (_followingFeed == following) return;
    setState(() {
      _followingFeed = following;
      // The cursor belongs to the endpoint that produced it, so it goes with the
      // posts. Keeping it would page one feed with the other's bookmark.
      _posts = [];
      _nextCursor = null;
      _isLoading = true;
    });
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final myUsername = widget.auth.currentUsername?.toLowerCase();
    final myGroupIndex =
        _storyGroups.indexWhere((g) => g.username.toLowerCase() == myUsername);
    final myStoryGroup = myGroupIndex >= 0 ? _storyGroups[myGroupIndex] : null;
    final hasMyStory = myStoryGroup != null && myStoryGroup.stories.isNotEmpty;

    return Scaffold(
      appBar: SejiloAppBar(
        showBrandLogo: true,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_border_rounded, size: 24),
                onPressed: () => NotificationsSheet.show(context, widget.auth),
              ),
              if (widget.auth.unreadNotificationsCount > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: SejiloColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Messages',
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
            onPressed: widget.onOpenMessages,
          ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 680,
            child: RefreshIndicator(
              onRefresh: _loadInitial,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Feed mode toggle
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          _FeedModeChip(
                            label: 'For You',
                            selected: !_followingFeed,
                            onTap: () => _setFeedMode(false),
                          ),
                          const SizedBox(width: 8),
                          _FeedModeChip(
                            label: 'Following',
                            selected: _followingFeed,
                            onTap: () => _setFeedMode(true),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Stories horizontal row
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 106,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      scrollDirection: Axis.horizontal,
                      itemCount: _storyGroups.length + (hasMyStory ? 0 : 1),
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        // If current user hasn't posted, slot 0 is "Add Your Story"
                        if (!hasMyStory && index == 0) {
                          return GestureDetector(
                            onTap: () async {
                              final created = await StoryCreatorScreen.open(
                                  context, widget.auth);
                              if (created == true) _loadStories();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  children: [
                                    SejiloAvatar(
                                      name: widget.auth.profile?.displayName ??
                                          'Me',
                                      imageBytes:
                                          widget.auth.profile?.avatarBytes,
                                      size: SejiloAvatarSize.md,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: SejiloColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(2),
                                        child: const Icon(Icons.add,
                                            color: Colors.white, size: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text('Your story',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          );
                        }

                        final groupIndex = hasMyStory ? index : index - 1;
                        final group = _storyGroups[groupIndex];
                        final isMe = group.username.toLowerCase() == myUsername;

                        return GestureDetector(
                          onTap: () async {
                            await StoryViewerScreen.open(
                              context,
                              auth: widget.auth,
                              groups: _storyGroups,
                              initialGroupIndex: groupIndex,
                            );
                            _loadStories();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  SejiloAvatar(
                                    name: group.displayName,
                                    imageBytes: group.avatarBytes,
                                    size: SejiloAvatarSize.md,
                                    hasStoryRing: true,
                                    hasUnseenStory: group.hasUnseenStory,
                                  ),
                                  if (isMe)
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () async {
                                          final created =
                                              await StoryCreatorScreen.open(
                                                  context, widget.auth);
                                          if (created == true) _loadStories();
                                        },
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: SejiloColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(2),
                                          child: const Icon(Icons.add,
                                              color: Colors.white, size: 10),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isMe ? 'Your story' : group.username,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: Divider(height: 1)),

                // Posts Feed
                if (_isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SejiloFeedSkeleton(itemCount: 2),
                    ),
                  )
                else if (_posts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: SejiloEmptyView(
                      icon: Icons.photo_library_outlined,
                      // Which chip is selected decides what an empty screen
                      // means, so it decides what to suggest: following nobody
                      // is not the same as nobody having posted.
                      title: _followingFeed
                          ? 'Nothing from the people you follow'
                          : 'No posts yet',
                      description: _followingFeed
                          ? 'Posts from the accounts you follow appear here. '
                              'Switch to For You to see everything else.'
                          : 'Nothing has been posted yet. Add the first one '
                              'from the Create tab.',
                      actionLabel: 'Refresh',
                      onAction: _loadInitial,
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == _posts.length) {
                          return _isLoadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : const SizedBox.shrink();
                        }
                        final post = _posts[index];
                        return _SocialPostCard(
                          post: post,
                          auth: widget.auth,
                          onAuthorBlocked: () {
                            // The server leaves a blocked author out of every
                            // feed it builds, so the cards already on screen go
                            // too instead of lingering until the next refresh.
                            final author = post.username.toLowerCase();
                            setState(() => _posts.removeWhere(
                                (p) => p.username.toLowerCase() == author));
                          },
                          onDelete: () async {
                            await widget.auth.deletePost(post.id);
                            setState(() =>
                                _posts.removeWhere((p) => p.id == post.id));
                          },
                          onLikeToggle: (liked) async {
                            try {
                              await widget.auth.setLike(post.id, liked);
                            } catch (e) {
                              // setLike rolls the controller's own copy back, so
                              // the only thing left to do is say why the heart
                              // did not change.
                              _reportActionFailure(e);
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              final p = _posts[index];
                              _posts[index] = SocialPost(
                                id: p.id,
                                userId: p.userId,
                                username: p.username,
                                displayName: p.displayName,
                                caption: p.caption,
                                media: p.media,
                                createdAt: p.createdAt,
                                likes: liked
                                    ? p.likes + 1
                                    : (p.likes > 0 ? p.likes - 1 : 0),
                                comments: p.comments,
                                liked: liked,
                                saved: p.saved,
                                avatarBytes: p.avatarBytes,
                              );
                            });
                          },
                          onSaveToggle: (saved) async {
                            try {
                              await widget.auth.setSave(post.id, saved);
                            } catch (e) {
                              _reportActionFailure(e);
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              final p = _posts[index];
                              _posts[index] = SocialPost(
                                id: p.id,
                                userId: p.userId,
                                username: p.username,
                                displayName: p.displayName,
                                caption: p.caption,
                                media: p.media,
                                createdAt: p.createdAt,
                                likes: p.likes,
                                comments: p.comments,
                                liked: p.liked,
                                saved: saved,
                                avatarBytes: p.avatarBytes,
                              );
                            });
                          },
                        );
                      },
                      childCount: _posts.length + (_nextCursor != null ? 1 : 0),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialPostCard extends StatefulWidget {
  const _SocialPostCard({
    required this.post,
    required this.auth,
    required this.onDelete,
    required this.onLikeToggle,
    required this.onSaveToggle,
    required this.onAuthorBlocked,
  });

  final SocialPost post;
  final AccountAuthController auth;
  final VoidCallback onDelete;
  final ValueChanged<bool> onLikeToggle;
  final ValueChanged<bool> onSaveToggle;

  /// Called once a block has actually been recorded by the server.
  final VoidCallback onAuthorBlocked;

  @override
  State<_SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<_SocialPostCard>
    with SingleTickerProviderStateMixin {
  bool _showHeartAnim = false;
  late AnimationController _heartAnimController;

  /// Device settings, reached through the auth controller because that is where
  /// the live instance is held. Null only if the app was built without stored
  /// preferences, in which case every default applies.
  AppPreferences? get _prefs => widget.auth.preferences;

  /// Honours Settings → Content preferences → "Hide like counts". Until now the
  /// switch wrote a value nothing ever read, so turning it on changed nothing.
  bool get _hideCounts => _prefs?.hideLikeCounts ?? false;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Redraw when a preference changes so the toggle takes effect on the cards
    // already on screen instead of only on the next cold start.
    _prefs?.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _heartAnimController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (!widget.post.liked) {
      widget.onLikeToggle(true);
    }
    setState(() => _showHeartAnim = true);
    _heartAnimController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeartAnim = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.auth.profile?.id == widget.post.userId ||
        widget.auth.profile?.username.toLowerCase() ==
            widget.post.username.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF22222E) : const Color(0xFFEEEEF2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SejiloAvatar(
                  name: widget.post.displayName,
                  imageBytes: widget.post.avatarBytes,
                  size: SejiloAvatarSize.sm,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.username,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (widget.post.displayName.isNotEmpty &&
                          widget.post.displayName != widget.post.username)
                        Text(
                          widget.post.displayName,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: Colors.grey),
                  onSelected: _onMenuSelected,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Send post to…'),
                        ],
                      ),
                    ),
                    if (!isMe) ...[
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 18, color: SejiloColors.danger),
                            SizedBox(width: 8),
                            Text('Report'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'mute',
                        child: Row(
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 18),
                            SizedBox(width: 8),
                            // Not "Mute user": the server's mute row silences
                            // notifications and is documented never to hide
                            // content, so promising the posts would disappear
                            // would be a lie.
                            Text('Mute notifications'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(Icons.block_outlined, size: 18, color: SejiloColors.danger),
                            SizedBox(width: 8),
                            Text('Block user'),
                          ],
                        ),
                      ),
                    ],
                    if (isMe)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete Post',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Post Media with Double-Tap Heart Animation
          GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Image.memory(
                    widget.post.media,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.withValues(alpha: 0.2),
                      child: const Center(
                          child: Icon(Icons.broken_image_rounded,
                              size: 48, color: Colors.grey)),
                    ),
                  ),
                ),
                if (_showHeartAnim)
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.5, end: 1.3).animate(
                      CurvedAnimation(
                          parent: _heartAnimController,
                          curve: Curves.elasticOut),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 90,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 16),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Action Buttons Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.post.liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: widget.post.liked ? SejiloColors.primary : null,
                    size: 26,
                  ),
                  onPressed: () => widget.onLikeToggle(!widget.post.liked),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 24),
                  onPressed: () =>
                      CommentsSheet.show(context, widget.auth, widget.post.id),
                ),
                IconButton(
                  tooltip: 'Send this post to somebody',
                  icon: const Icon(Icons.send_outlined, size: 24),
                  onPressed: _sharePost,
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    widget.post.saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: widget.post.saved ? SejiloColors.accent : null,
                    size: 26,
                  ),
                  onPressed: () => widget.onSaveToggle(!widget.post.saved),
                ),
              ],
            ),
          ),

          // Likes Count
          if (widget.post.likes > 0 && !_hideCounts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${widget.post.likes} ${widget.post.likes == 1 ? 'like' : 'likes'}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),

          // Caption
          if (widget.post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: '${widget.post.username} ',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    TextSpan(
                      text: widget.post.caption,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // View Comments Trigger
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: GestureDetector(
              onTap: () =>
                  CommentsSheet.show(context, widget.auth, widget.post.id),
              child: Text(
                widget.post.comments == 0
                    ? 'Add a comment…'
                    // The count itself is suppressed under "Hide like and
                    // comment counts", but the way into the thread is not.
                    : _hideCounts
                        ? 'View comments'
                        : 'View all ${widget.post.comments} comments',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),

          // Timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Text(
              _formatTimeAgo(widget.post.createdAt),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'delete':
        _confirmDelete();
      case 'share':
        await _sharePost();
      case 'report':
        await _reportPost();
      case 'mute':
        await _muteAuthor();
      case 'block':
        await _blockAuthor();
    }
  }

  /// Sends the post to somebody inside the app.
  ///
  /// This used to claim it had copied `https://sejilochat.net/p/<id>` to the
  /// clipboard. Nothing in this build registers a deep link and there is no web
  /// front end, so that address opened nothing for whoever received it. The
  /// sheet sends a real direct message with the picture attached instead.
  Future<void> _sharePost() async {
    final sentTo = await SharePostSheet.show(context, widget.auth, widget.post);
    if (sentTo == null) return;
    _toast('Sent to @$sentTo.');
  }

  Future<void> _reportPost() async {
    final submission = await showReportSheet(context, title: 'Report this post');
    if (submission == null || !mounted) return;
    try {
      await widget.auth.reportPost(
        widget.post.id,
        submission.reason,
        details: submission.details,
      );
      _toast('Report sent. It is listed under Settings › Privacy and security.');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Report not sent — the server could not be reached.');
    }
  }

  /// Mutes notifications from the author. The posts deliberately stay: the
  /// server's mute row silences alerts and is documented never to hide content.
  Future<void> _muteAuthor() async {
    try {
      await widget.auth.setMuted(widget.post.username, true);
      _toast('@${widget.post.username} muted. Their posts still appear — '
          'manage this under Settings › Privacy and security.');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Not muted — the server could not be reached.');
    }
  }

  Future<void> _blockAuthor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block @${widget.post.username}?'),
        content: const Text(
            'Any follow between you is removed and you will not be able to '
            'message each other. They are not told that you blocked them. You '
            'can undo this from Settings › Privacy and security.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.auth.blockUser(widget.post.username);
      _toast('@${widget.post.username} blocked.');
      if (mounted) widget.onAuthorBlocked();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Not blocked — the server could not be reached.');
    }
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post?'),
        content: const Text(
            'Are you sure you want to permanently delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete();
            },
            child: const Text('Delete',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inHours < 1) return '${diff.inMinutes} MINUTES AGO';
    if (diff.inDays < 1) return '${diff.inHours} HOURS AGO';
    if (diff.inDays < 7) return '${diff.inDays} DAYS AGO';
    return '${dt.day}/${dt.month}/${dt.year}'.toUpperCase();
  }
}

class _FeedModeChip extends StatelessWidget {
  const _FeedModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SejiloColors.primary.withValues(alpha: .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? SejiloColors.primary.withValues(alpha: .4) : Colors.grey.withValues(alpha: .3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? SejiloColors.primary : Colors.grey,
          ),
        ),
      ),
    );
  }
}
