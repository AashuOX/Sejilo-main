import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../../core/app_preferences.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_state_views.dart';
import '../../design_system/sejilo_theme.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.auth, required this.postId});

  final AccountAuthController auth;
  final String postId;

  static Future<void> show(
      BuildContext context, AccountAuthController auth, String postId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(auth: auth, postId: postId),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _commentController = TextEditingController();
  bool _isLoading = true;
  bool _isSending = false;
  List<PostComment> _comments = [];

  @override
  void initState() {
    super.initState();
    _load();
    // The hidden-words filter is applied on every build, so a change made while
    // this sheet is open should redraw it.
    _prefs?.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Device settings, held by the auth controller.
  AppPreferences? get _prefs => widget.auth.preferences;

  /// The comments this reader should see: Settings → Content preferences →
  /// "Hidden words" drops the rest. Filtering is local — the comment is still
  /// there for everyone else, including its author.
  List<PostComment> get _visibleComments {
    final prefs = _prefs;
    if (prefs == null) return _comments;
    return _comments.where((c) => !prefs.isHidden(c.text)).toList();
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final list = await widget.auth.loadComments(widget.postId);
    if (mounted) {
      setState(() {
        _comments = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAddComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _commentController.clear();

    try {
      await widget.auth.addComment(widget.postId, text);
      final updated = await widget.auth.loadComments(widget.postId);
      if (mounted) {
        setState(() => _comments = updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
    try {
      await widget.auth.deleteComment(widget.postId, comment.id);
      final updated = await widget.auth.loadComments(widget.postId);
      if (mounted) setState(() => _comments = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete comment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Comments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          // Comments list
          Expanded(child: _buildCommentsArea(context)),
          const Divider(height: 1),
          // Comment input
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SejiloAvatar(
                  name: widget.auth.profile?.displayName ?? 'You',
                  imageBytes: widget.auth.profile?.avatarBytes,
                  size: SejiloAvatarSize.sm,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      hintStyle:
                          const TextStyle(fontSize: 14, color: Colors.grey),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1E28)
                          : const Color(0xFFF0F0F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _handleAddComment(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded,
                          color: SejiloColors.primary),
                  onPressed: _isSending ? null : _handleAddComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The list, its two empty states, and the note that says how many comments
  /// the hidden-words filter removed. Without that note a filtered comment
  /// would simply be missing, with nothing to explain why.
  Widget _buildCommentsArea(BuildContext context) {
    if (_isLoading) {
      return const Center(child: SejiloLoadingView(message: 'Loading comments…'));
    }

    final visible = _visibleComments;
    final hiddenCount = _comments.length - visible.length;

    if (visible.isEmpty) {
      return hiddenCount > 0
          ? const SejiloEmptyView(
              icon: Icons.filter_alt_outlined,
              title: 'Comments hidden',
              description:
                  'Every comment on this post matches one of your hidden '
                  'words. Change them in Settings → Content preferences.',
            )
          : const SejiloEmptyView(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No comments yet',
              description: 'Be the first to leave a comment on this post.',
            );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      // One extra leading row for the "n hidden" note when there is one.
      itemCount: visible.length + (hiddenCount > 0 ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (hiddenCount > 0 && index == 0) {
          return Text(
            hiddenCount == 1
                ? '1 comment hidden by your hidden words.'
                : '$hiddenCount comments hidden by your hidden words.',
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          );
        }
        final c = visible[hiddenCount > 0 ? index - 1 : index];
        final isOwn = c.userId == widget.auth.profile?.id;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SejiloAvatar(
              name: c.displayName,
              imageBytes: c.avatarBytes,
              size: SejiloAvatarSize.sm,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: c.username,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(text: c.text),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimeAgo(c.createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // Only your own comments can be removed; the backend rejects
            // deleting anyone else's.
            if (isOwn)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.grey),
                tooltip: 'Delete comment',
                onPressed: () => _deleteComment(c),
              ),
          ],
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
