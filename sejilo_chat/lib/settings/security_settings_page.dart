// security_settings_page.dart — the account controls that really exist.
//
// What used to be here was decoration: a password row claiming "last changed 30
// days ago", a two-factor switch wired to `(_) {}`, an "active sessions: 1
// device" row and a "connected accounts: Google, Phone, Email" row. None of
// those had a backend. The API does expose account privacy, password-reset
// requests, block/mute lists, filed reports, sign-out and account deletion, so
// that is what this page is.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../security/blocked_users_page.dart';
import '../security/muted_accounts_page.dart';
import '../security/my_reports_page.dart';
import 'settings_section.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _privacyBusy = false;
  bool _resetBusy = false;

  void _nav(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _setPrivate(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _privacyBusy = true);
    try {
      await widget.auth.setAccountPrivate(value);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Your account is private. New followers have to be approved.'
                : 'Your account is public.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the server.')),
      );
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send a reset link?'),
        content: Text(
          'A link that lets you choose a new password will be sent to $email. '
          'Your current password keeps working until you use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetBusy = true);
    try {
      await widget.auth.requestPasswordReset(email);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Reset link sent to $email.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the server.')),
      );
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<void> _confirmLogout() async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again. Messages already on this device stay '
          'on it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.auth.logout();
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }

  /// Deletion is irreversible and asks for the username as confirmation, since
  /// a stray tap here cannot be undone.
  Future<void> _confirmDelete(String username) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matches = controller.text.trim() == username;
          return AlertDialog(
            title: const Text('Delete this account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your profile, posts, comments, likes, follows and online '
                  'messages are removed from the server. This cannot be undone.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autocorrect: false,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Type $username to confirm',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  'Delete forever',
                  style: TextStyle(
                    color: matches ? Colors.red : Theme.of(ctx).disabledColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (confirmed != true) return;
    try {
      await widget.auth.deleteAccount();
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Account not deleted: ${e.message}')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Account not deleted — the server could not be reached. Nothing '
            'was removed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy and security',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) {
          final profile = widget.auth.profile;
          if (profile == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sign in to manage privacy and security.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSection(
                title: 'Who can see you',
                icon: Icons.lock_outline_rounded,
                children: [
                  SwitchListTile(
                    value: profile.isPrivate,
                    onChanged: _privacyBusy ? null : _setPrivate,
                    title: const Text('Private account'),
                    subtitle: const Text(
                      'Follows become requests you approve, and your posts and '
                      'profile stay hidden from people who do not follow you. '
                      'Enforced on the server.',
                    ),
                    secondary: _privacyBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            profile.isPrivate
                                ? Icons.lock_rounded
                                : Icons.public_rounded,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'Password',
                icon: Icons.password_rounded,
                children: [
                  ListTile(
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: const Text('Send a password reset link'),
                    subtitle: Text(
                      profile.email.isEmpty
                          ? 'This account has no email address, so a reset link '
                              'cannot be sent.'
                          : profile.email,
                    ),
                    trailing: _resetBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    enabled: profile.email.isNotEmpty && !_resetBusy,
                    onTap: () => _sendPasswordReset(profile.email),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'People',
                icon: Icons.people_outline_rounded,
                children: [
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: const Text('Blocked accounts'),
                    subtitle: const Text(
                      'They cannot see your posts, follow you or message you',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(BlockedUsersPage(auth: widget.auth)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_off_outlined),
                    title: const Text('Muted accounts'),
                    subtitle: const Text('Silenced without being blocked'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(MutedAccountsPage(auth: widget.auth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'Reports',
                icon: Icons.flag_outlined,
                children: [
                  ListTile(
                    leading: const Icon(Icons.list_alt_rounded),
                    title: const Text('Reports you have filed'),
                    subtitle: const Text('What you sent, and its status'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(MyReportsPage(auth: widget.auth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'This account',
                icon: Icons.logout_rounded,
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: Text('Log out of @${profile.username}'),
                    onTap: _confirmLogout,
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded,
                        color: Colors.red),
                    title: const Text(
                      'Delete account',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Permanent, and takes your posts with it'),
                    onTap: () => _confirmDelete(profile.username),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
