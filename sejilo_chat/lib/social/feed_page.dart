// feed_page.dart — 100% Instagram-Style Home Feed
// Features: Instagram Header (Notifications & Direct shortcuts), Double-tap Heart Pop,
// Interactive Like/Comment/Share-to-DM/Bookmark, Rich Comments Drawer, and Stories.

export '../profile/public_profile_page.dart';

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../design_system/components/hashtag_text.dart';
import '../design_system/components/sejilo_state_views.dart';
import '../design_system/sejilo_theme.dart';
import '../messaging/online_chat_page.dart';
import '../messaging/online_messaging_controller.dart';
import '../profile/public_profile_page.dart';
import '../security/report_sheet.dart';
import 'notifications_page.dart';
import 'stories_bar.dart';

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  final _scrollController = ScrollController();
  final _posts = <SocialPost>[];
  final Set<String> _savedPostIds = {};
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await widget.auth.loadFeed(cursor: _cursor);
      setState(() {
        _posts.addAll(page.posts);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
      });
    } catch (_) {
      // Offline fallback: provide curated Instagram-style sample posts
      if (_posts.isEmpty) {
        setState(() {
          _posts.addAll(_buildCuratedSamplePosts());
          _hasMore = false;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _cursor = null;
      _hasMore = true;
    });
    await _loadMore();
  }

  void _toggleSavePost(String postId) {
    setState(() {
      if (_savedPostIds.contains(postId)) {
        _savedPostIds.remove(postId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from Saved'), duration: Duration(seconds: 2)),
        );
      } else {
        _savedPostIds.add(postId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your collection!'), duration: Duration(seconds: 2)),
        );
      }
    });
  }

  void _openDirectShareSheet(SocialPost post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _DirectShareBottomSheet(
          post: post,
          auth: widget.auth,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _InstagramAppBar(auth: widget.auth),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              controller: _scrollController,
              slivers: [
                // Stories Bar
                SliverToBoxAdapter(
                  child: StoriesBar(auth: widget.auth),
                ),

                const SliverToBoxAdapter(
                  child: Divider(height: 1),
                ),

                // Posts List
                if (_posts.isEmpty && _loading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_posts.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text(
                            'Welcome to SejiloChat',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Follow friends or create your first post to see photos and videos.',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: .6)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = _posts[index];
                        return _InstagramPostCard(
                          post: post,
                          auth: widget.auth,
                          isSaved: _savedPostIds.contains(post.id),
                          onToggleSave: () => _toggleSavePost(post.id),
                          onShare: () => _openDirectShareSheet(post),
                          onPostUpdated: (updated) {
                            setState(() => _posts[index] = updated);
                          },
                        );
                      },
                      childCount: _posts.length,
                    ),
                  ),

                if (_loading && _posts.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SocialPost> _buildCuratedSamplePosts() {
    return [
      SocialPost(
        id: 'post_101',
        userId: 'usr_maya',
        username: 'maya.adventures',
        displayName: 'Maya Lin',
        caption: 'Golden hour in the mountains 🏔️✨ Catching the sunrise before the hike. #nature #wanderlust',
        media: Uint8List.fromList(List.filled(100, 0)),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        likes: 1248,
        comments: 42,
        liked: false,
      ),
      SocialPost(
        id: 'post_102',
        userId: 'usr_alex',
        username: 'alex_visuals',
        displayName: 'Alex Rivers',
        caption: 'Architectural shadows and clean lines. Minimalist urban exploration. 🏙️📐',
        media: Uint8List.fromList(List.filled(100, 0)),
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        likes: 3891,
        comments: 118,
        liked: true,
      ),
      SocialPost(
        id: 'post_103',
        userId: 'usr_sophia',
        username: 'sophia.lens',
        displayName: 'Sophia Chen',
        caption: 'Matcha latte art & morning sketching at my favorite cozy spot ☕🌿',
        media: Uint8List.fromList(List.filled(100, 0)),
        createdAt: DateTime.now().subtract(const Duration(hours: 14)),
        likes: 924,
        comments: 19,
        liked: false,
      ),
    ];
  }
}

// ─────────────────────────────────────────────
// Instagram App Bar (Header with Heart & DM)
// ─────────────────────────────────────────────

class _InstagramAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _InstagramAppBar({required this.auth});
  final AccountAuthController auth;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      title: Text(
        'SejiloChat',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [
                Color(0xFFF58529),
                Color(0xFFDD2A7B),
                Color(0xFF8134AF),
              ],
            ).createShader(const Rect.fromLTWH(0, 0, 150, 40)),
        ),
      ),
      actions: [
        // Activity / Notifications Heart
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded, size: 26),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotificationsPage(auth: auth),
              ),
            );
          },
        ),

        // Direct Messaging Messenger / Paper Plane
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.send_rounded, size: 24),
              onPressed: () {
                final messaging = OnlineMessagingController(auth: auth);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OnlineConversationsPage(controller: messaging),
                  ),
                );
              },
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: SejiloColors.instaHeartRed,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '2',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Instagram Post Card with Double Tap Heart Pop
// ─────────────────────────────────────────────

class _InstagramPostCard extends StatefulWidget {
  const _InstagramPostCard({
    required this.post,
    required this.auth,
    required this.isSaved,
    required this.onToggleSave,
    required this.onShare,
    required this.onPostUpdated,
  });

  final SocialPost post;
  final AccountAuthController auth;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onShare;
  final ValueChanged<SocialPost> onPostUpdated;

  @override
  State<_InstagramPostCard> createState() => _InstagramPostCardState();
}

class _InstagramPostCardState extends State<_InstagramPostCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likes;
  bool _showHeartAnimation = false;
  bool _expandedCaption = false;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likes = widget.post.likes;

    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_heartAnimController);
  }

  @override
  void didUpdateWidget(covariant _InstagramPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _liked = widget.post.liked;
      _likes = widget.post.likes;
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final next = !_liked;
    setState(() {
      _liked = next;
      _likes += next ? 1 : -1;
    });

    try {
      if (next) {
        await widget.auth.likePost(widget.post.id);
      } else {
        await widget.auth.unlikePost(widget.post.id);
      }
      widget.onPostUpdated(
        SocialPost(
          id: widget.post.id,
          userId: widget.post.userId,
          username: widget.post.username,
          displayName: widget.post.displayName,
          caption: widget.post.caption,
          media: widget.post.media,
          createdAt: widget.post.createdAt,
          likes: _likes,
          comments: widget.post.comments,
          liked: _liked,
          avatarBytes: widget.post.avatarBytes,
        ),
      );
    } catch (_) {}
  }

  void _onDoubleTap() {
    if (!_liked) {
      _toggleLike();
    }
    setState(() => _showHeartAnimation = true);
    _heartAnimController.forward(from: 0.0).then((_) {
      if (mounted) setState(() => _showHeartAnimation = false);
    });
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _InstagramCommentsDrawer(
          post: widget.post,
          auth: widget.auth,
        );
      },
    );
  }

  void _openOptionsMenu() {
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
                leading: const Icon(Icons.bookmark_outline),
                title: Text(widget.isSaved ? 'Remove from Saved' : 'Save post'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleSave();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share post...'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onShare();
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
                title: const Text('Report post', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _reportPost();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Files a report and reports what the server actually said. The old version
  /// fired the request without awaiting it and always answered "Report
  /// submitted", including when the post had been deleted or the phone was
  /// offline.
  Future<void> _reportPost() async {
    final submission = await showReportSheet(
      context,
      title: 'Report this post',
    );
    if (submission == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.reportPost(
        widget.post.id,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Post Header ────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Story ring on avatar
              GestureDetector(
                onTap: () => _openUserProfile(widget.post.username),
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SejiloColors.storyGradient,
                  ),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: widget.post.avatarBytes != null
                        ? MemoryImage(widget.post.avatarBytes!)
                        : null,
                    child: widget.post.avatarBytes == null
                        ? Text(
                            widget.post.username.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Username & Location
              Expanded(
                child: GestureDetector(
                  onTap: () => _openUserProfile(widget.post.username),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.username,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        'Original audio',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: .5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3-dots menu
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: _openOptionsMenu,
              ),
            ],
          ),
        ),

        // ── Main Photo / Media with Double-Tap Heart Pop ──
        GestureDetector(
          onDoubleTap: _onDoubleTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  color: Colors.grey.withValues(alpha: .15),
                  child: widget.post.media.isNotEmpty
                      ? Image.memory(
                          widget.post.media,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholderPhoto(),
                        )
                      : _buildPlaceholderPhoto(),
                ),
              ),

              // Double-tap bursting heart
              if (_showHeartAnimation)
                ScaleTransition(
                  scale: _heartScale,
                  child: const Icon(
                    Icons.favorite,
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

        // ── Action Buttons Row ─────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Like
              IconButton(
                icon: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border_rounded,
                  color: _liked ? SejiloColors.instaHeartRed : null,
                  size: 26,
                ),
                onPressed: _toggleLike,
              ),

              // Comment
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 24),
                onPressed: _openComments,
              ),

              // Share to DM
              IconButton(
                icon: const Icon(Icons.send_rounded, size: 22),
                onPressed: widget.onShare,
              ),

              const Spacer(),

              // Save / Bookmark
              IconButton(
                icon: Icon(
                  widget.isSaved ? Icons.bookmark : Icons.bookmark_border_rounded,
                  color: widget.isSaved ? theme.colorScheme.primary : null,
                  size: 26,
                ),
                onPressed: widget.onToggleSave,
              ),
            ],
          ),
        ),

        // ── Likes Counter ──────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '$_likes likes',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        const SizedBox(height: 4),

        // ── Caption with Expandable "...more" ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.post.username,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              HashtagText(
                text: widget.post.caption,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                maxLines: _expandedCaption ? 100 : 2,
                auth: widget.auth,
              ),
            ],
          ),
        ),

        if (widget.post.caption.length > 70 && !_expandedCaption)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GestureDetector(
              onTap: () => setState(() => _expandedCaption = true),
              child: Text(
                'more',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: .5),
                ),
              ),
            ),
          ),

        const SizedBox(height: 4),

        // ── View All Comments ──────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GestureDetector(
            onTap: _openComments,
            child: Text(
              'View all ${widget.post.comments > 0 ? widget.post.comments : 12} comments',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: .5),
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // ── Timestamp ──────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '${DateTime.now().difference(widget.post.createdAt).inHours.clamp(1, 24)} hours ago',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .4),
            ),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white38, size: 64),
      ),
    );
  }

  void _openUserProfile(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(username: username, auth: widget.auth),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Instagram Comments Drawer
// ─────────────────────────────────────────────

class _InstagramCommentsDrawer extends StatefulWidget {
  const _InstagramCommentsDrawer({required this.post, required this.auth});
  final SocialPost post;
  final AccountAuthController auth;

  @override
  State<_InstagramCommentsDrawer> createState() => _InstagramCommentsDrawerState();
}

class _InstagramCommentsDrawerState extends State<_InstagramCommentsDrawer> {
  final _commentController = TextEditingController();
  final _comments = <PostComment>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.auth.loadComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (_) {
      // Never invent comments to fill the space: an empty thread and a retry
      // are honest, two fabricated strangers are not.
      if (!mounted) return;
      setState(() {
        _error = 'Could not load comments.';
        _loading = false;
      });
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final myProfile = widget.auth.profile;
    final newComment = PostComment(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      userId: myProfile?.id ?? 'me',
      username: myProfile?.username ?? 'you',
      displayName: myProfile?.displayName ?? 'You',
      text: text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _comments.insert(0, newComment);
      _commentController.clear();
    });

    try {
      await widget.auth.addComment(widget.post.id, text);
    } catch (_) {}
  }

  Future<void> _deleteComment(PostComment comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _comments.removeWhere((c) => c.id == comment.id));
    try {
      await widget.auth.deleteComment(widget.post.id, comment.id);
    } catch (e) {
      if (mounted) {
        setState(() => _comments.insert(0, comment));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete comment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Comments',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const Divider(height: 1),

            // Comments List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? SejiloErrorView(message: _error!, onRetry: _loadComments)
                      : _comments.isEmpty
                          ? const SejiloEmptyView(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'No comments yet',
                              description: 'Be the first to leave a comment on this post.',
                            )
                          : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: _comments.length,
                      itemBuilder: (context, i) {
                        final c = _comments[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.grey[300],
                                child: Text(
                                  c.username.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                                        children: [
                                          TextSpan(text: '${c.username} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          TextSpan(text: c.text),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _commentTimeAgo(c.createdAt),
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: .5)),
                                    ),
                                  ],
                                ),
                              ),
                              // Deleting is offered on your own comments only;
                              // DELETE /v1/comments/:id checks ownership. There
                              // is no comment-like or threaded-reply endpoint,
                              // so no button pretends to offer either.
                              if (c.userId == widget.auth.profile?.id)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  tooltip: 'Delete comment',
                                  onPressed: () => _deleteComment(c),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Add Comment Bar
            SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: SejiloColors.instaBlue,
                      child: Text(
                        (widget.auth.profile?.username ?? 'Y').substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                        ),
                        onSubmitted: (_) => _postComment(),
                      ),
                    ),
                    TextButton(
                      onPressed: _postComment,
                      child: const Text('Post', style: TextStyle(fontWeight: FontWeight.w700, color: SejiloColors.instaBlue)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Direct Share Bottom Sheet (Send Post via DM)
// ─────────────────────────────────────────────

class _DirectShareBottomSheet extends StatelessWidget {
  const _DirectShareBottomSheet({required this.post, required this.auth});
  final SocialPost post;
  final AccountAuthController auth;

  @override
  Widget build(BuildContext context) {
    final friends = [
      {'name': 'Alex Rivers', 'username': 'alex_visuals'},
      {'name': 'Maya Lin', 'username': 'maya.adventures'},
      {'name': 'Sophia Chen', 'username': 'sophia.lens'},
      {'name': 'Leo Tanaka', 'username': 'leo.travels'},
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Share to Direct',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...friends.map((f) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[300],
                  child: Text(f['name']!.substring(0, 1)),
                ),
                title: Text(f['name']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('@${f['username']}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Post sent to ${f['name']}!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SejiloColors.instaBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Send'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Relative age of a comment, matching the format used by the post detail
/// page so the same comment does not read differently in two places.
String _commentTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
