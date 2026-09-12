import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/sejilo_theme.dart';

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.auth,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  final AccountAuthController auth;
  final List<UserStoryGroup> groups;
  final int initialGroupIndex;

  static Future<void> open(
    BuildContext context, {
    required AccountAuthController auth,
    required List<UserStoryGroup> groups,
    int initialGroupIndex = 0,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => StoryViewerScreen(
          auth: auth,
          groups: groups,
          initialGroupIndex: initialGroupIndex,
        ),
      ),
    );
  }

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _currentGroupIndex;
  late int _currentStoryIndex;
  late AnimationController _animController;
  bool _isPaused = false;
  final TextEditingController _replyController = TextEditingController();

  static const List<LinearGradient> _textGradients = [
    LinearGradient(
      colors: [Color(0xFF833AB4), Color(0xFFE1306C), Color(0xFFF77737)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF130CB7), Color(0xFF52E5E7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2C3E50), Color(0xFF000000)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF654EA3), Color(0xFFEAAFC8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentGroupIndex =
        widget.initialGroupIndex.clamp(0, widget.groups.length - 1);
    _currentStoryIndex = 0;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onNextStory();
      }
    });

    _startCurrentStory();
  }

  @override
  void dispose() {
    _animController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  UserStoryGroup get _currentGroup => widget.groups[_currentGroupIndex];
  Story get _currentStory => _currentGroup.stories[_currentStoryIndex];
  bool get _isOwnStory {
    final myUsername = widget.auth.currentUsername?.toLowerCase();
    return _currentStory.username.toLowerCase() == myUsername;
  }

  void _startCurrentStory() {
    _animController.stop();
    _animController.reset();

    // Mark as viewed on backend/local state
    widget.auth.markStoryViewed(_currentStory.id);

    _animController.forward();
  }

  void _onNextStory() {
    if (_currentStoryIndex < _currentGroup.stories.length - 1) {
      setState(() {
        _currentStoryIndex++;
      });
      _startCurrentStory();
    } else if (_currentGroupIndex < widget.groups.length - 1) {
      setState(() {
        _currentGroupIndex++;
        _currentStoryIndex = 0;
      });
      _startCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onPreviousStory() {
    if (_currentStoryIndex > 0) {
      setState(() {
        _currentStoryIndex--;
      });
      _startCurrentStory();
    } else if (_currentGroupIndex > 0) {
      setState(() {
        _currentGroupIndex--;
        _currentStoryIndex =
            widget.groups[_currentGroupIndex].stories.length - 1;
      });
      _startCurrentStory();
    } else {
      _startCurrentStory();
    }
  }

  void _pause() {
    setState(() => _isPaused = true);
    _animController.stop();
  }

  void _resume() {
    setState(() => _isPaused = false);
    _animController.forward();
  }

  LinearGradient _resolveTextGradient(String? styleKey) {
    if (styleKey != null && styleKey.startsWith('gradient_')) {
      final idx = int.tryParse(styleKey.replaceFirst('gradient_', ''));
      if (idx != null && idx >= 0 && idx < _textGradients.length) {
        return _textGradients[idx];
      }
    }
    return _textGradients[0];
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  void _showViewersSheet() {
    _pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<StoryViewerInfo>>(
          future: widget.auth.loadStoryViewers(_currentStory.id),
          builder: (context, snapshot) {
            final viewers = snapshot.data ?? [];
            final count = _currentStory.viewsCount;

            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.remove_red_eye_rounded,
                            color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Viewed by $count ${count == 1 ? 'person' : 'people'}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator()))
                    else if (viewers.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No views yet. Share with friends!',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: viewers.length,
                          separatorBuilder: (_, __) =>
                              const Divider(color: Colors.white10),
                          itemBuilder: (context, i) {
                            final v = viewers[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: SejiloAvatar(
                                bytes: v.avatarBytes,
                                label: v.displayName,
                                customSize: 36,
                              ),
                              title: Text(v.displayName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text('@${v.username}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              trailing: Text(
                                _formatTimeAgo(v.viewedAt),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => _resume());
  }

  void _showDeleteDialog() {
    _pause();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title:
            const Text('Delete Story?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently remove this story before its 24-hour expiration.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.auth.deleteStory(_currentStory.id);
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Story deleted')),
                );
              }
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(() => _resume());
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final group = _currentGroup;
    final totalInGroup = group.stories.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width * 0.35) {
            _onPreviousStory();
          } else {
            _onNextStory();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background / Story Content ──────────────
            if (story.type == StoryType.image && story.mediaBytes != null)
              Image.memory(
                story.mediaBytes!,
                fit: BoxFit.cover,
              )
            else
              Container(
                decoration: BoxDecoration(
                    gradient: _resolveTextGradient(story.backgroundStyle)),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  story.textContent ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 16)],
                  ),
                ),
              ),

            // Optional bottom text for image story
            if (story.type == StoryType.image &&
                story.textContent != null &&
                story.textContent!.isNotEmpty)
              Positioned(
                bottom: _isOwnStory ? 70 : 80,
                left: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    story.textContent!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),

            // ── Overlay UI (Progress Bars & Header) ────
            if (!_isPaused)
              SafeArea(
                child: Column(
                  children: [
                    // Segmented Progress Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: List.generate(totalInGroup, (idx) {
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white30,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: idx < _currentStoryIndex
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    )
                                  : idx == _currentStoryIndex
                                      ? AnimatedBuilder(
                                          animation: _animController,
                                          builder: (context, child) {
                                            return FractionallySizedBox(
                                              alignment: Alignment.centerLeft,
                                              widthFactor:
                                                  _animController.value,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          );
                        }),
                      ),
                    ),

                    // User Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          SejiloAvatar(
                            bytes: group.avatarBytes,
                            label: group.displayName,
                            customSize: 34,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  group.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black54, blurRadius: 4)
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatTimeAgo(story.createdAt),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black54, blurRadius: 4)
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isOwnStory)
                            IconButton(
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white),
                              onPressed: _showDeleteDialog,
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // ── Bottom Action Bar ───────────────────────
            if (!_isPaused)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: _isOwnStory
                      ? Center(
                          child: GestureDetector(
                            onTap: _showViewersSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.remove_red_eye_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${story.viewsCount} views',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: TextField(
                                  controller: _replyController,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Send message to ${group.displayName}…',
                                    hintStyle: const TextStyle(
                                        color: Colors.white60, fontSize: 13),
                                    border: InputBorder.none,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.send_rounded,
                                          color: SejiloColors.primary,
                                          size: 18),
                                      onPressed: () {
                                        if (_replyController.text
                                            .trim()
                                            .isNotEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Replied to ${group.displayName}')),
                                          );
                                          _replyController.clear();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.favorite_rounded,
                                    color: Colors.redAccent, size: 22),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Liked ${group.displayName}\'s story ❤️')),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
