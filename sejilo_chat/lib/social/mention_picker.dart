import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/sejilo_theme.dart';

/// Lets the author pick a real account to mention in a caption.
///
/// Backed by `GET /v1/users/search`, so the names offered are accounts that
/// actually exist — and the resulting `@username` is tappable in the feed,
/// because [HashtagText] resolves mentions to a profile.
///
/// Returns the chosen username without the leading `@`, or null if dismissed.
Future<String?> showMentionPicker(
  BuildContext context,
  AccountAuthController auth,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MentionPickerSheet(auth: auth),
  );
}

class _MentionPickerSheet extends StatefulWidget {
  const _MentionPickerSheet({required this.auth});

  final AccountAuthController auth;

  @override
  State<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<_MentionPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<PublicProfile> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    // One request per pause in typing rather than one per keystroke.
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final users = await widget.auth.searchUsers(query);
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _results = users;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tag people',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by name or username',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not search right now.\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }
    if (_query.text.trim().isEmpty) {
      return const Center(
        child: Text(
          'Start typing to find someone to tag.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No accounts matched that search.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final user = _results[i];
        return ListTile(
          leading: SejiloAvatar(
            imageBytes: user.avatarBytes,
            name: user.displayName,
            size: SejiloAvatarSize.sm,
          ),
          title: Text(user.username,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: user.displayName.isEmpty ? null : Text(user.displayName),
          onTap: () => Navigator.pop(context, user.username),
        );
      },
    );
  }
}
