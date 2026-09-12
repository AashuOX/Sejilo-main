// settings_page.dart — the settings hub.
//
// Three things were wrong with the old hub. The Account tile pushed
// SettingsPage into itself, so tapping your own name opened a second copy of
// the settings screen. Every tile that needed preferences or the mesh client
// fell back to `AppPreferences()` / `MeshClient(...)` — fresh objects wired to
// nothing, so a switch flipped on a sub-page wrote to an instance the app never
// read. And two tiles (Help Center, About) had no onTap at all.
//
// Now: preferences come from the controller when a caller does not pass them,
// the mesh tile only appears when there is a live client to configure, and the
// version string is the one in pubspec.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../core/app_preferences.dart';
import '../core/mesh_client.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../profile/profile_page.dart' show EditProfileSheet;
import 'appearance_settings_page.dart';
import 'content_preferences_page.dart';
import 'data_storage_settings_page.dart';
import 'mesh_settings_page.dart';
import 'notification_settings_page.dart';
import 'security_settings_page.dart';
import 'server_settings_page.dart';
import 'settings_section.dart';

/// Kept in step with `version:` in pubspec.yaml by hand — the app does not
/// depend on package_info_plus, so there is nothing to read it from at runtime.
const String kSejiloVersion = '0.5.0 (10)';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.auth,
    this.preferences,
    this.meshClient,
    super.key,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  void _nav(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _editProfile(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditProfileSheet(auth: auth),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.dark => 'Dark',
        ThemeMode.light => 'Light',
      };

  @override
  Widget build(BuildContext context) {
    // A caller that has no reference of its own still gets the instance the
    // rest of the app is using, because the controller was built with it.
    final prefs = preferences ?? auth.preferences;
    final mesh = meshClient;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final profile = auth.profile;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (profile != null) ...[
                SettingsSection(
                  title: 'Account',
                  icon: Icons.person_outline_rounded,
                  children: [
                    ListTile(
                      leading: SejiloAvatar(
                        bytes: profile.avatarBytes,
                        name: profile.displayName.isEmpty
                            ? profile.username
                            : profile.displayName,
                        size: SejiloAvatarSize.sm,
                      ),
                      title: Text(
                        profile.displayName.isEmpty
                            ? '@${profile.username}'
                            : profile.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('@${profile.username}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editProfile(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (prefs != null) ...[
                SettingsSection(
                  title: 'App',
                  icon: Icons.tune_rounded,
                  children: [
                    ListenableBuilder(
                      listenable: prefs,
                      builder: (context, _) => Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.palette_outlined),
                            title: const Text('Appearance'),
                            subtitle: Text(
                              '${_themeLabel(prefs.themeMode)} theme · aurora '
                              '${prefs.auroraEffects ? 'on' : 'off'}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _nav(
                              context,
                              AppearanceSettingsPage(preferences: prefs),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.notifications_outlined),
                            title: const Text('Notifications'),
                            subtitle: Text(switch (prefs.notificationLevel) {
                              NotificationLevel.all => 'Every message',
                              NotificationLevel.important =>
                                'Verified contacts only',
                              NotificationLevel.none => 'Paused',
                            }),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _nav(
                              context,
                              NotificationSettingsPage(preferences: prefs),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.filter_alt_outlined),
                            title: const Text('Content preferences'),
                            subtitle: Text(
                              prefs.hiddenWords.isEmpty
                                  ? 'Hidden words, like and comment counts'
                                  : '${prefs.hiddenWords.length} hidden word(s)',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _nav(
                              context,
                              ContentPreferencesPage(preferences: prefs),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.storage_outlined),
                            title: const Text('Data and storage'),
                            subtitle: Text(
                              prefs.highQualityUploads
                                  ? 'Full-size uploads'
                                  : 'Smaller uploads to save data',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _nav(
                              context,
                              DataStorageSettingsPage(preferences: prefs),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SettingsSection(
                title: 'Privacy and security',
                icon: Icons.shield_outlined,
                children: [
                  ListTile(
                    leading: const Icon(Icons.security_rounded),
                    title: const Text('Privacy and security'),
                    subtitle: const Text(
                      'Account privacy, password, blocked and muted accounts, '
                      'reports',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(context, SecuritySettingsPage(auth: auth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (mesh != null) ...[
                SettingsSection(
                  title: 'Mesh',
                  icon: Icons.bluetooth_outlined,
                  children: [
                    ListenableBuilder(
                      listenable: mesh,
                      builder: (context, _) => ListTile(
                        leading: Icon(
                          mesh.shareNearby
                              ? Icons.bluetooth_rounded
                              : Icons.bluetooth_disabled_rounded,
                        ),
                        title: const Text('Mesh network'),
                        subtitle: Text(
                          mesh.shareNearby
                              ? '${mesh.nearbyPeers.length} peer(s) in range'
                              : 'Off',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            _nav(context, MeshSettingsPage(meshClient: mesh)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SettingsSection(
                title: 'Connection',
                icon: Icons.dns_outlined,
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_rounded),
                    title: const Text('Server'),
                    subtitle: Text(auth.baseUrl),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(context, ServerSettingsPage(auth: auth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'About',
                icon: Icons.info_outline_rounded,
                children: [
                  const ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('SejiloChat'),
                    subtitle: Text('Version $kSejiloVersion'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('How mesh messaging works'),
                    subtitle: const Text('What travels over Bluetooth, and how far'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _nav(context, const AboutMeshPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// The honest version of a "Help Center" tile: no support desk exists behind
/// this app, so instead of a dead link this explains the two transports and the
/// limits that follow from them.
class AboutMeshPage extends StatelessWidget {
  const AboutMeshPage({super.key});

  static const List<(String, String)> _facts = [
    (
      'Two ways a message travels',
      'With internet, messages go through the Sejilo server and are delivered '
          'to anyone, anywhere. Without internet, they hop between phones over '
          'Bluetooth LE.',
    ),
    (
      'Bluetooth range is short',
      'Expect 10–30 m indoors. A message reaches further only by being relayed '
          'through other phones that are in range and running SejiloChat, and '
          'each message carries a hop limit.',
    ),
    (
      'Mesh messages are signed',
      'Every mesh message is signed by the sending device and checked on '
          'arrival, so a relay cannot change what it forwards. A message shown '
          'as unverified failed that check.',
    ),
    (
      'Notifications come from this device',
      'There is no push service in this build. Alerts are raised while '
          'SejiloChat is running; anything that arrives while it is fully '
          'closed is shown the next time you open it.',
    ),
    (
      'Saved posts stay on this device',
      'Saving a post records it locally. It does not sync to another phone you '
          'sign in on.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'How it works',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _facts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (context, index) {
          final (title, body) = _facts[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
