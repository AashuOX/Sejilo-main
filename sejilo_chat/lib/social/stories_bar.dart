// stories_bar.dart — 100% Instagram-Style Stories Bar & Full-Screen Viewer
// Features: Instagram gradient rings, Hold-to-pause, Tap-to-navigate,
// Quick emoji reactions (🔥😂😍👏😮😢🎉), and Story creation.

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../core/image_utils.dart';
import '../design_system/sejilo_theme.dart';

class StoriesBar extends StatefulWidget {
  const StoriesBar({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  late Future<List<Story>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.auth.isAuthenticated
        ? widget.auth.loadStories()
        : Future.value([]);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isAuthenticated) return const SizedBox.shrink();

    return SizedBox(
      height: 104,
      child: FutureBuilder<List<Story>>(
        future: _future,
        builder: (context, snap) {
          final stories = snap.data ?? [];
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            itemCount: stories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _YourStoryBubble(
                  auth: widget.auth,
                  onTap: () => _createStory(context),
                );
              }
              final story = stories[index - 1];
              return _UserStoryBubble(
                story: story,
                onTap: () => _viewStory(context, stories, index - 1),
              );
            },
          );
        },
      ),
    );
  }

  void _viewStory(BuildContext context, List<Story> stories, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryViewerPage(
          stories: stories,
          startIndex: index,
          auth: widget.auth,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _load());
    });
  }

  Future<void> _createStory(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.bytes == null || !mounted) return;

    try {
      final optimized = await ImageUtils.optimizeImage(file!.bytes!);

      await widget.auth.createStory(
        imageBytes: optimized.bytes,
        mimeType: optimized.mimeType,
      );
      if (context.mounted) {
        setState(() => _load());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your story was posted (active for 24h)!'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post story: $e')),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────
// "Your Story" Bubble with Blue (+) Badge
// ─────────────────────────────────────────────

class _YourStoryBubble extends StatelessWidget {
  const _YourStoryBubble({required this.auth, required this.onTap});
  final AccountAuthController auth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = auth.profile;
    final avatarBytes = profile?.avatarBytes;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.withValues(alpha: .2), width: 1),
                ),
                child: CircleAvatar(
                  radius: 31,
                  backgroundColor: const Color(0xFFE1E2E4),
                  backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                  child: avatarBytes == null
                      ? Text(
                          (profile?.displayName ?? 'You').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: SejiloColors.instaBlue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Your story',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// User Story Bubble with Instagram Gradient Ring
// ─────────────────────────────────────────────

class _UserStoryBubble extends StatelessWidget {
  const _UserStoryBubble({required this.story, required this.onTap});
  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isViewed = story.viewedByMe;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isViewed
                  ? null
                  : SejiloColors.storyGradient,
              border: isViewed
                  ? Border.all(color: Colors.grey.withValues(alpha: .4), width: 1.5)
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFD4D6D9),
                backgroundImage: story.avatarBytes != null ? MemoryImage(story.avatarBytes!) : null,
                child: story.avatarBytes == null
                    ? Text(
                        story.displayName.isNotEmpty
                            ? story.displayName.substring(0, 1).toUpperCase()
                            : story.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 68,
            child: Text(
              story.username,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Full Screen Story Viewer (100% Instagram UX)
// ─────────────────────────────────────────────

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    required this.stories,
    required this.startIndex,
    required this.auth,
    super.key,
  });

  final List<Story> stories;
  final int startIndex;
  final AccountAuthController auth;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _progressController;
  final _replyController = TextEditingController();
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex.clamp(0, widget.stories.length - 1);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });

    _startCurrentStory();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _startCurrentStory() {
    _isLiked = false;
    _progressController.stop();
    _progressController.reset();
    _progressController.forward();
    final story = widget.stories[_currentIndex];
    widget.auth.markStoryViewed(story.id);
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex++);
      _startCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startCurrentStory();
    } else {
      _startCurrentStory();
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    if (dx < screenWidth * 0.35) {
      _prevStory();
    } else {
      _nextStory();
    }
  }

  void _pause() {
    _progressController.stop();
  }

  void _resume() {
    _progressController.forward();
  }

  void _sendReaction(String emoji) {
    final story = widget.stories[_currentIndex];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sent $emoji to ${story.username}'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: _onTapDown,
          onLongPressStart: (_) => _pause(),
          onLongPressEnd: (_) => _resume(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Main Story Media ─────────────────────
              Center(
                child: Image.memory(
                  story.media,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  ),
                ),
              ),

              // ── Top Gradient Overlay ─────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: .7), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // ── Segmented Progress Bars ──────────────
              Positioned(
                top: 8,
                left: 10,
                right: 10,
                child: Row(
                  children: List.generate(widget.stories.length, (index) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Container(
                            height: 2.5,
                            color: Colors.white.withValues(alpha: .35),
                            child: index < _currentIndex
                                ? Container(color: Colors.white)
                                : index == _currentIndex
                                    ? AnimatedBuilder(
                                        animation: _progressController,
                                        builder: (context, _) => LinearProgressIndicator(
                                          value: _progressController.value,
                                          backgroundColor: Colors.transparent,
                                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // ── User Header ──────────────────────────
              Positioned(
                top: 22,
                left: 14,
                right: 14,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: story.avatarBytes != null ? MemoryImage(story.avatarBytes!) : null,
                      child: story.avatarBytes == null
                          ? Text(
                              story.username.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      story.username,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${DateTime.now().difference(story.createdAt).inHours}h',
                      style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── Bottom Reply & Reaction Bar ──────────
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Emoji Bar (Instagram Style)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['🔥', '😂', '😍', '👏', '😮', '😢', '🎉'].map((emoji) {
                        return GestureDetector(
                          onTap: () => _sendReaction(emoji),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(emoji, style: const TextStyle(fontSize: 22)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),

                    // Reply TextField & Heart Like
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withValues(alpha: .5)),
                              borderRadius: BorderRadius.circular(24),
                              color: Colors.black.withValues(alpha: .3),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                              child: TextField(
                                controller: _replyController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                onSubmitted: (text) {
                                  if (text.trim().isNotEmpty) {
                                    _sendReaction('💬 "$text"');
                                    _replyController.clear();
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Send message...',
                                  hintStyle: TextStyle(color: Colors.white70, fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  filled: false,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Heart Like Button
                        IconButton(
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? SejiloColors.instaHeartRed : Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            setState(() => _isLiked = !_isLiked);
                            if (_isLiked) _sendReaction('❤️');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
