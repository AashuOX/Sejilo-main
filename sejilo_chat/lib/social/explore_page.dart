// explore_page.dart — 100% Instagram-Style Explore & Friend Search Studio
// Features: High-performance Friend Search, Recent Search History with 1-tap removal,
// Search Tabs (Top, Accounts, Tags, Places), Suggested Friends carousel,
// Staggered 3-column media grid with Reel badges, and interactive post viewer.

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../design_system/sejilo_theme.dart';
import '../profile/public_profile_page.dart';
import '../social/hashtag/hashtag_page.dart';
import 'post_detail_page.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  int _searchTabIndex = 0; // 0: Top, 1: Accounts/Friends, 2: Tags, 3: Places
  String _selectedCategory = 'For You';

  Future<List<PublicProfile>>? _searchFuture;
  late Future<List<PublicProfile>> _recommendedFuture;
  late Future<List<SocialPost>> _discoverFuture;

  final Set<String> _followedUsers = {};
  final List<String> _recentSearches = [
    'alex.wanderer',
    'elena_art',
    '#travelphotography',
    'leo.creator',
    '#aestheticvibes',
  ];

  static const List<String> _categories = [
    'For You',
    'Travel ✈️',
    'Photography 📸',
    'Architecture 🏛️',
    'Style 👗',
    'Tech 💻',
    'Nature 🌿',
    'Art 🎨',
    'Food 🍕',
  ];

  static const List<String> _searchTabs = [
    'Top',
    'Accounts',
    'Tags',
    'Places',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _recommendedFuture = widget.auth.isAuthenticated
        ? widget.auth.searchUsers('')
        : Future.value([]);
    _discoverFuture = widget.auth.isAuthenticated
        ? widget.auth.discoverPosts()
        : Future.value([]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    setState(() {
      _query = trimmed;
      _searchFuture = trimmed.isEmpty ? null : widget.auth.searchUsers(trimmed);
    });
  }

  void _addRecentSearch(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _recentSearches.remove(text);
      _recentSearches.insert(0, text);
      if (_recentSearches.length > 8) _recentSearches.removeLast();
    });
  }

  void _removeRecentSearch(String text) {
    setState(() {
      _recentSearches.remove(text);
    });
  }

  void _clearAllRecentSearches() {
    setState(() {
      _recentSearches.clear();
    });
  }

  void _openProfile(String username) {
    _addRecentSearch(username);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(username: username, auth: widget.auth),
      ),
    );
  }

  void _toggleFollow(String username) {
    setState(() {
      if (_followedUsers.contains(username)) {
        _followedUsers.remove(username);
      } else {
        _followedUsers.add(username);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSearching = _focusNode.hasFocus || _query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search friends, tags, or places...',
              hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: .5)),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
              filled: false,
            ),
          ),
        ),
        actions: [
          if (isSearching)
            TextButton(
              onPressed: () {
                _focusNode.unfocus();
                _searchController.clear();
                _onSearchChanged('');
              },
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
        ],
      ),
      body: isSearching
          ? _buildSearchBody(theme)
          : _buildExploreFeed(theme),
    );
  }

  // ── Search Mode Body ──────────────────────────

  Widget _buildSearchBody(ThemeData theme) {
    return Column(
      children: [
        // Search Tabs
        Container(
          height: 42,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: .3))),
          ),
          child: Row(
            children: List.generate(_searchTabs.length, (index) {
              final title = _searchTabs[index];
              final isSelected = _searchTabIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _searchTabIndex = index),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? theme.colorScheme.primary : Colors.grey,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Results or Recent Searches
        Expanded(
          child: _query.isNotEmpty
              ? _buildSearchResults(theme)
              : _buildRecentSearchesAndSuggestions(theme),
        ),
      ],
    );
  }

  // ── Recent Searches & Friend Suggestions ──────

  Widget _buildRecentSearchesAndSuggestions(ThemeData theme) {
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Searches',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                GestureDetector(
                  onTap: _clearAllRecentSearches,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SejiloColors.instaBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._recentSearches.map((item) {
            final isTag = item.startsWith('#');
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: isTag
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.grey[300],
                child: Icon(
                  isTag ? Icons.tag_rounded : Icons.person_rounded,
                  size: 18,
                  color: isTag ? theme.colorScheme.onSurface : Colors.black54,
                ),
              ),
              title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(isTag ? 'Trending hashtag' : 'Friend account', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                onPressed: () => _removeRecentSearch(item),
              ),
              onTap: () {
                _searchController.text = item;
                _onSearchChanged(item);
              },
            );
          }),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],

        // Suggested Friends header
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.person_add_outlined, size: 18),
              SizedBox(width: 8),
              Text(
                'Discover & Find Friends',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
        ),

        FutureBuilder<List<PublicProfile>>(
          future: _recommendedFuture,
          builder: (context, snapshot) {
            final users = snapshot.data ?? _buildSampleFriends();
            return Column(
              children: users.take(6).map((u) => _buildFriendSearchTile(u, theme)).toList(),
            );
          },
        ),
      ],
    );
  }

  // ── Search Results List ──────────────────────

  Widget _buildSearchResults(ThemeData theme) {
    if (_searchTabIndex == 2) {
      // Tags search mode
      return _buildTagResults(theme);
    }

    return FutureBuilder<List<PublicProfile>>(
      future: _searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          // If server query returns empty, provide matching sample accounts
          final filtered = _buildSampleFriends()
              .where((u) =>
                  u.username.toLowerCase().contains(_query.toLowerCase()) ||
                  u.displayName.toLowerCase().contains(_query.toLowerCase()))
              .toList();

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off_rounded, size: 54, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text('No results for "$_query"', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Check the spelling or try another name.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: filtered.length,
            itemBuilder: (context, i) => _buildFriendSearchTile(filtered[i], theme),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: users.length,
          itemBuilder: (context, index) => _buildFriendSearchTile(users[index], theme),
        );
      },
    );
  }

  Widget _buildTagResults(ThemeData theme) {
    final tags = [
      '#${_query.replaceAll('#', '')}',
      '#${_query.replaceAll('#', '')}photography',
      '#${_query.replaceAll('#', '')}vibes',
      '#${_query.replaceAll('#', '')}daily',
      '#${_query.replaceAll('#', '')}life',
    ];

    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: tags.length,
      itemBuilder: (context, i) {
        final tag = tags[i];
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor.withValues(alpha: .4)),
            ),
            child: const Icon(Icons.tag_rounded, size: 22),
          ),
          title: Text(tag, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text('${(i + 1) * 24}K posts', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          onTap: () {
            _addRecentSearch(tag);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HashtagPage(tag: tag, auth: widget.auth),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendSearchTile(PublicProfile user, ThemeData theme) {
    final isFollowing = _followedUsers.contains(user.username) || user.followedByViewer;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: GestureDetector(
        onTap: () => _openProfile(user.username),
        child: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[300],
              backgroundImage: user.avatarBytes != null ? MemoryImage(user.avatarBytes!) : null,
              child: user.avatarBytes == null
                  ? Text(
                      user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16),
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.username,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.verified_rounded, size: 14, color: SejiloColors.instaBlue),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.displayName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text('Followed by friends • 4 mutual', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: .5))),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () => _toggleFollow(user.username),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: isFollowing
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6)
                  : SejiloColors.instaBlue,
              foregroundColor: isFollowing
                  ? theme.colorScheme.onSurface
                  : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              isFollowing ? 'Following' : 'Follow',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      onTap: () => _openProfile(user.username),
    );
  }

  // ── Main Explore Feed with Categories & Grid ─

  Widget _buildExploreFeed(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loadData());
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Category Pills Carousel ──────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? theme.scaffoldBackgroundColor : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Suggested Accounts Carousel ──────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Suggested for You',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _focusNode.requestFocus();
                          });
                        },
                        child: const Text(
                          'See All',
                          style: TextStyle(
                            color: SejiloColors.instaBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 185,
                  child: FutureBuilder<List<PublicProfile>>(
                    future: _recommendedFuture,
                    builder: (context, snapshot) {
                      final users = (snapshot.data?.isNotEmpty == true)
                          ? snapshot.data!
                          : _buildSampleFriends();

                      return ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final u = users[index];
                          final isFollowing = _followedUsers.contains(u.username) || u.followedByViewer;

                          return Container(
                            width: 135,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor.withValues(alpha: .3)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: u.avatarBytes != null ? MemoryImage(u.avatarBytes!) : null,
                                  child: u.avatarBytes == null
                                      ? Text(u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87))
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  u.username,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Suggested for you',
                                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .5)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 28,
                                  child: ElevatedButton(
                                    onPressed: () => _toggleFollow(u.username),
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: isFollowing
                                          ? theme.colorScheme.surfaceContainerHighest
                                          : SejiloColors.instaBlue,
                                      foregroundColor: isFollowing
                                          ? theme.colorScheme.onSurface
                                          : Colors.white,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: Text(
                                      isFollowing ? 'Following' : 'Follow',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 12),
          ),

          // ── 3-Column Staggered Media Grid ────────
          FutureBuilder<List<SocialPost>>(
            future: _discoverFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }

              final posts = (snapshot.data?.isNotEmpty == true)
                  ? snapshot.data!
                  : _buildSampleDiscoverPosts();

              return SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = posts[index % posts.length];
                    final isReel = index % 3 == 0; // Staggered Reel video badge

                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PostDetailPage(post: post, auth: widget.auth),
                          ),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            color: Colors.grey[900],
                            child: post.media.length > 200
                                ? Image.memory(
                                    post.media,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.primaries[index % Colors.primaries.length].withValues(alpha: .6),
                                      child: Center(
                                        child: Icon(
                                          isReel ? Icons.movie_creation_outlined : Icons.photo_library_outlined,
                                          color: Colors.white70,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.primaries[index % Colors.primaries.length].withValues(alpha: .6),
                                    child: Center(
                                      child: Icon(
                                        isReel ? Icons.movie_creation_outlined : Icons.photo_library_outlined,
                                        color: Colors.white70,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                          ),
                          if (isReel)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                  childCount: posts.length * 3, // Endless aesthetic grid
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<PublicProfile> _buildSampleFriends() {
    return [
      PublicProfile(
        id: 'u_alex',
        username: 'alex.wanderer',
        displayName: 'Alex Rivers',
        bio: 'Explorer & Mountain Biker 🚵‍♂️',
        followersCount: 1420,
        followingCount: 380,
        avatarBytes: null,
        avatarMimeType: null,
        followedByViewer: false,
      ),
      PublicProfile(
        id: 'u_elena',
        username: 'elena_art',
        displayName: 'Elena Rostova',
        bio: 'Visual artist & digital creator 🎨✨',
        followersCount: 3200,
        followingCount: 410,
        avatarBytes: null,
        avatarMimeType: null,
        followedByViewer: true,
      ),
      PublicProfile(
        id: 'u_leo',
        username: 'leo.creator',
        displayName: 'Leo Sterling',
        bio: 'Architecture • Aesthetics • Film 📸',
        followersCount: 980,
        followingCount: 210,
        avatarBytes: null,
        avatarMimeType: null,
        followedByViewer: false,
      ),
      PublicProfile(
        id: 'u_sophia',
        username: 'sophia.vibes',
        displayName: 'Sophia Bennett',
        bio: 'Coffee, books & sunsets ☕📖',
        followersCount: 2450,
        followingCount: 520,
        avatarBytes: null,
        avatarMimeType: null,
        followedByViewer: false,
      ),
    ];
  }

  List<SocialPost> _buildSampleDiscoverPosts() {
    return [
      SocialPost(
        id: 'disc_1',
        userId: 'u_alex',
        username: 'alex.wanderer',
        displayName: 'Alex Rivers',
        caption: 'Alpine lakes in autumn 🍁 #travel #wanderlust',
        media: Uint8List(0),
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        likes: 3420,
        comments: 182,
        liked: false,
      ),
      SocialPost(
        id: 'disc_2',
        userId: 'u_elena',
        username: 'elena_art',
        displayName: 'Elena Rostova',
        caption: 'New gallery opening tonight! ✨ #art #minimalism',
        media: Uint8List(0),
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        likes: 5120,
        comments: 310,
        liked: true,
      ),
    ];
  }
}
