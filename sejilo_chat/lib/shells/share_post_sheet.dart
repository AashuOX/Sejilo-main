// share_post_sheet.dart — sending a post to somebody inside the app.
//
// Replaces the feed's two fake share actions: a snackbar claiming to have copied
// "https://sejilochat.net/p/<id>" — a link nothing in this build can open, on a
// domain that is not registered — and a second one that only said "Sharing post
// <id>". What happens here is a real direct message: the post's picture plus an
// attribution line, sent through the same
// POST /v1/chat/conversations/:id/messages the Messages tab uses, so it lands in
// both inboxes and survives a restart.

import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/sejilo_theme.dart';

class SharePostSheet extends StatefulWidget {
  const SharePostSheet({required this.auth, required this.post, super.key});

  final AccountAuthController auth;
  final SocialPost post;

  /// Opens the sheet, returning the username the post was sent to — or null if
  /// it was dismissed without sending.
  static Future<String?> show(
    BuildContext context,
    AccountAuthController auth,
    SocialPost post,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SharePostSheet(auth: auth, post: post),
    );
  }

  @override
  State<SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<SharePostSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _note = TextEditingController();
  Timer? _debounce;
  List<PublicProfile> _people = const [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _sendingTo;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The accounts you follow are the default recipients.
  ///
  /// `loadFollowing` falls back to a locally cached list of usernames when the
  /// request fails, and those rows carry a made-up `usr_<name>` id. Offering one
  /// could only produce a send that fails, so they are dropped.
  Future<void> _loadFollowing() async {
    final me = widget.auth.currentUsername;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to send posts to people.';
      });
      return;
    }
    final following = await widget.auth.loadFollowing(me);
    if (!mounted) return;
    setState(() {
      _people =
          following.where((p) => !p.id.startsWith('usr_')).toList(growable: false);
      _loading = false;
      _searching = false;
    });
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = true;
        _searching = false;
      });
      _loadFollowing();
      return;
    }
    // Long enough that typing a handle does not fire a request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _searching = true;
      });
      final me = widget.auth.currentUsername;
      final results = await widget.auth.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _people = results
            .where((p) => p.username != me)
            .toList(growable: false);
        _loading = false;
      });
    });
  }

  Future<void> _send(PublicProfile person) async {
    setState(() {
      _sendingTo = person.username;
      _error = null;
    });
    try {
      await widget.auth.sharePostWithUser(
        recipientUserId: person.id,
        post: widget.post,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context, person.username);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingTo = null;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingTo = null;
        _error = 'Not sent — the server could not be reached.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            _header(theme),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _note,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Add a message (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                autocorrect: false,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search for an account',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null) _errorBanner(_error!),
            const SizedBox(height: 4),
            Flexible(child: _recipients(theme)),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final post = widget.post;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(SejiloRadius.small),
            child: post.media.isEmpty
                ? Container(width: 46, height: 46, color: theme.dividerColor)
                : Image.memory(
                    post.media,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send this post',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'It arrives as a direct message from you, with the picture '
                  'attached.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(SejiloRadius.small),
        ),
        child: Text(
          message,
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      ),
    );
  }

  Widget _recipients(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
        child: Text(
          _searching
              ? 'No account matches that name.'
              : 'You are not following anyone yet. Search for a username above '
                  'to send this post to them.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _people.length,
      itemBuilder: (context, i) => _personTile(theme, _people[i]),
    );
  }

  Widget _personTile(ThemeData theme, PublicProfile person) {
    final sending = _sendingTo == person.username;
    // A send is one tap on the row; the whole row is disabled while one is in
    // flight so the same post cannot be posted twice into the same thread.
    return ListTile(
      onTap: _sendingTo == null ? () => _send(person) : null,
      leading: SejiloAvatar(
        bytes: person.avatarBytes,
        name: person.displayName.isEmpty ? person.username : person.displayName,
        size: SejiloAvatarSize.sm,
      ),
      title: Text(
        person.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: person.displayName.isEmpty
          ? null
          : Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
      trailing: sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.send_rounded, size: 20, color: theme.hintColor),
    );
  }
}
