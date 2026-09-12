import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/components/sejilo_state_views.dart';
import '../../design_system/sejilo_theme.dart';
import '../../auth/account_auth_controller.dart';
import '../../profile/public_profile_page.dart';
import 'comments_sheet.dart';

class ExploreShell extends StatefulWidget {
  const ExploreShell({super.key, required this.auth});

  final AccountAuthController auth;

  @override
  State<ExploreShell> createState() => _ExploreShellState();
}

class _ExploreShellState extends State<ExploreShell> {
  final _searchController = TextEditingController();
  List<SocialPost> _explorePosts = [];
  List<PublicProfile> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _selectedCategory = 'Trending';

  final List<String> _categories = [
    'Trending',
    'Technology',
    'Design',
    'Mesh P2P',
    'Music',
    'Photography',
    'Art',
  ];

  @override
  void initState() {
    super.initState();
    _loadExplore();
    // Rebuild when "Hide like and comment counts" is toggled so the grid badges
    // follow the setting immediately.
    widget.auth.preferences?.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Honours Settings → Content preferences → "Hide like and comment counts".
  bool get _hideCounts => widget.auth.preferences?.hideLikeCounts ?? false;

  /// Says why a like or a save did not land. The controller has already undone
  /// its optimistic change, so nothing here has to repair state.
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
    widget.auth.preferences?.removeListener(_onPrefsChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExplore() async {
    setState(() => _isLoading = true);
    final posts = await widget.auth.discoverPosts();
    if (mounted) {
      setState(() {
        _explorePosts = posts;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await widget.auth.searchUsers(q);
    if (mounted) {
      setState(() => _searchResults = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 900,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              // Search Input
              SejiloInput(
                controller: _searchController,
                hintText: 'Search people, tags, and topics...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 10),

              // Filter Category Chips (when not searching)
              if (!_isSearching) ...[
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = cat == _selectedCategory;
                      return FilterChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedCategory = cat);
                          _loadExplore();
                        },
                        backgroundColor: isDark
                            ? SejiloColors.darkCard
                            : SejiloColors.lightCard,
                        selectedColor:
                            SejiloColors.primary.withValues(alpha: 0.15),
                        checkmarkColor: SejiloColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? SejiloColors.primary
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? SejiloColors.primary
                              : (isDark
                                  ? SejiloColors.darkOutline
                                  : SejiloColors.lightOutline),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Content Area
              Expanded(
                child: _isSearching
                    ? _buildSearchResults(isDark)
                    : _buildExploreGrid(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_searchResults.isEmpty) {
      return SejiloEmptyView(
        icon: Icons.person_search_rounded,
        title: 'No users found',
        description: 'Try searching with a different username or display name.',
      );
    }

    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, index) {
        final u = _searchResults[index];
        final isMe = widget.auth.profile?.username.toLowerCase() ==
            u.username.toLowerCase();

        return ListTile(
          leading: SejiloAvatar(
            name: u.displayName,
            imageBytes: u.avatarBytes,
            size: SejiloAvatarSize.md,
          ),
          title: Text(u.username,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(
            u.displayName.isNotEmpty ? u.displayName : u.bio,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: isMe
              ? null
              : OutlinedButton(
                  onPressed: () async {
                    await widget.auth
                        .setFollow(u.username, !u.followedByViewer);
                    final updated =
                        await widget.auth.searchUsers(_searchController.text);
                    if (mounted) setState(() => _searchResults = updated);
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: u.followedByViewer
                        ? Colors.transparent
                        : SejiloColors.primary,
                    side: BorderSide(
                      color: u.followedByViewer
                          ? Colors.grey
                          : SejiloColors.primary,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  ),
                  child: Text(
                    u.followedByViewer ? 'Following' : 'Follow',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: u.followedByViewer
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.white,
                    ),
                  ),
                ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PublicProfilePage(username: u.username, auth: widget.auth),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExploreGrid(bool isDark) {
    if (_isLoading) {
      return const SejiloExploreSkeleton();
    }

    if (_explorePosts.isEmpty) {
      return SejiloEmptyView(
        icon: Icons.explore_outlined,
        title: 'Discover SejiloChat',
        description:
            'Explore curated posts from creators across decentralized communities.',
        actionLabel: 'Refresh',
        onAction: _loadExplore,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadExplore,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
          childAspectRatio: 1.0,
        ),
        itemCount: _explorePosts.length,
        itemBuilder: (context, index) {
          final post = _explorePosts[index];
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite,
                              size: 10, color: Colors.white),
                          const SizedBox(width: 2),
                          Text('${post.likes}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
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
                  title: Text(post.username,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(post.displayName,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Image.memory(
                    post.media,
                    fit: BoxFit.cover,
                    // Same guard as the grid tile behind this dialog: bytes that
                    // will not decode draw a placeholder instead of raising.
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.withValues(alpha: 0.2),
                      child: const Icon(Icons.photo_outlined,
                          color: Colors.grey),
                    ),
                  ),
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
                              post.liked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: post.liked ? SejiloColors.primary : null,
                            ),
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              try {
                                await widget.auth
                                    .setLike(post.id, !post.liked);
                              } catch (e) {
                                navigator.pop();
                                _reportActionFailure(e);
                                return;
                              }
                              navigator.pop();
                              _loadExplore();
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
                              post.saved
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: post.saved ? SejiloColors.accent : null,
                            ),
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              try {
                                await widget.auth
                                    .setSave(post.id, !post.saved);
                              } catch (e) {
                                navigator.pop();
                                _reportActionFailure(e);
                                return;
                              }
                              navigator.pop();
                              _loadExplore();
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
                              TextSpan(
                                  text: '${post.username} ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
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
}
