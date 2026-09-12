import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../core/app_preferences.dart';
import '../design_system/components/hashtag_text.dart';

// ─────────────────────────────────────────────
// Post detail page — full post + comments
// ─────────────────────────────────────────────

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({required this.post, required this.auth, super.key});

  final SocialPost post;
  final AccountAuthController auth;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late Future<List<PostComment>> _commentsFuture;
  late bool _liked;
  late int _likeCount;
  final _commentText = TextEditingController();
  final _commentFocus = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likeCount = widget.post.likes;
    _commentsFuture = widget.auth.loadComments(widget.post.id);
    // Both the like count and the comment list are filtered by device settings,
    // so redraw when one of those settings changes.
    _prefs?.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Device settings, reached through the auth controller, which is where the
  /// live instance lives.
  AppPreferences? get _prefs => widget.auth.preferences;

  /// Honours Settings → Content preferences → "Hide like and comment counts".
  bool get _hideCounts => _prefs?.hideLikeCounts ?? false;

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _commentText.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final newLiked = !_liked;
    setState(() {
      _liked = newLiked;
      _likeCount += newLiked ? 1 : -1;
    });
    try {
      await widget.auth.setLike(widget.post.id, newLiked);
    } catch (e) {
      // The heart goes back to what the server actually holds, and says why —
      // a silent revert reads as the tap having missed.
      setState(() {
        _liked = !newLiked;
        _likeCount += newLiked ? -1 : 1;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? e.message
              : 'Your like could not be saved — the server could not be '
                  'reached.'),
        ),
      );
    }
  }

  Future<void> _submitComment() async {
    final txt = _commentText.text.trim();
    if (txt.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.auth.addComment(widget.post.id, txt);
      _commentText.clear();
      setState(() => _commentsFuture = widget.auth.loadComments(widget.post.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post comment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      await widget.auth.deleteComment(widget.post.id, comment.id);
      if (mounted) {
        setState(
            () => _commentsFuture = widget.auth.loadComments(widget.post.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete comment: $e')),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
      await widget.auth.deletePost(widget.post.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOwn = widget.post.userId == widget.auth.profile?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          if (isOwn)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete post',
              onPressed: _deletePost,
            ),
        ],
      ),
      body: ListView(
        children: [
          // Post header
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            leading: CircleAvatar(
              backgroundImage: widget.post.avatarBytes != null
                  ? MemoryImage(widget.post.avatarBytes!)
                  : null,
              child: widget.post.avatarBytes == null
                  ? Text(widget.post.displayName.isNotEmpty
                      ? widget.post.displayName[0].toUpperCase()
                      : '?')
                  : null,
            ),
            title: Text(widget.post.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@${widget.post.username}'),
          ),

          // Image
          AspectRatio(
            aspectRatio: 1,
            child: Image.memory(
              widget.post.media,
              fit: BoxFit.cover,
              // Bytes that will not decode — a truncated download, or a format
              // this platform has no codec for — used to raise through to a red
              // error box. A placeholder keeps the rest of the post readable.
              errorBuilder: (_, __, ___) => Container(
                color: scheme.onSurface.withValues(alpha: .06),
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: scheme.onSurface.withValues(alpha: .35),
                  ),
                ),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _liked ? Icons.favorite_rounded : Icons.favorite_outline,
                    color: _liked ? const Color(0xFFE53935) : null,
                  ),
                  onPressed: _toggleLike,
                ),
                if (!_hideCounts)
                  Text(
                    '$_likeCount',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  tooltip: 'Add a comment',
                  onPressed: () => _commentFocus.requestFocus(),
                ),
                const Spacer(),
                Text(
                  _timeAgo(widget.post.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: .5),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),

          // Caption
          if (widget.post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.post.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  HashtagText(
                    text: widget.post.caption,
                    style: DefaultTextStyle.of(context).style,
                    auth: widget.auth,
                  ),
                ],
              ),
            ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Comments',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),

          // Comments
          FutureBuilder<List<PostComment>>(
            future: _commentsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child:
                        Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
              }
              final loaded = snap.data ?? [];
              // Settings → Content preferences → "Hidden words". The filter is
              // local: the comment still exists for everyone else, it is just
              // not drawn for this reader.
              final prefs = _prefs;
              final comments = prefs == null
                  ? loaded
                  : loaded.where((c) => !prefs.isHidden(c.text)).toList();
              final hiddenCount = loaded.length - comments.length;
              if (comments.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(hiddenCount > 0
                        ? 'Every comment here matches one of your hidden words.'
                        : 'No comments yet. Be the first!'),
                  ),
                );
              }
              return Column(
                children: [
                  if (hiddenCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        hiddenCount == 1
                            ? '1 comment hidden by your hidden words.'
                            : '$hiddenCount comments hidden by your hidden '
                                'words.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: .55),
                        ),
                      ),
                    ),
                  ...comments
                    .map((c) => ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(
                              c.displayName.isNotEmpty
                                  ? c.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: DefaultTextStyle.of(context).style,
                              children: [
                                TextSpan(
                                    text: c.username,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const TextSpan(text: '  '),
                                TextSpan(text: c.text),
                              ],
                            ),
                          ),
                          subtitle: Text(_timeAgo(c.createdAt),
                              style: const TextStyle(fontSize: 11)),
                          // The backend only lets you delete your own
                          // comment, so the button is offered on those only.
                          trailing: c.userId == widget.auth.profile?.id
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  tooltip: 'Delete comment',
                                  onPressed: () => _deleteComment(c),
                                )
                              : null,
                        )),
                ],
              );
            },
          ),

          // Comment input
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentText,
                    focusNode: _commentFocus,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment…',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: 8),
                _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send_rounded),
                        onPressed: _submitComment,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
