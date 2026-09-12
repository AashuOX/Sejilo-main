// notification_settings_page.dart — alert settings, each one wired to a real
// consumer in MeshClient's notification path.
//
// Nothing here is decorative: the level gates whether a notification is posted
// at all, previews decide whether the message text is in the body, and sound
// picks the channel used on Android.

import 'package:flutter/material.dart';
import '../core/app_preferences.dart';
import 'settings_section.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({required this.preferences, super.key});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsSection(
              title: 'What gets through',
              icon: Icons.notifications_active_outlined,
              children: [
                RadioGroup<NotificationLevel>(
                  groupValue: preferences.notificationLevel,
                  onChanged: (value) {
                    if (value != null) preferences.setNotificationLevel(value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<NotificationLevel>(
                        value: NotificationLevel.all,
                        title: Text('Everything'),
                        subtitle: Text('Alert me for every incoming message'),
                      ),
                      RadioListTile<NotificationLevel>(
                        value: NotificationLevel.important,
                        title: Text('Verified contacts only'),
                        subtitle: Text(
                          'Only people whose key you have verified in person. '
                          'Other messages still arrive and are saved — they '
                          'just stay quiet.',
                        ),
                      ),
                      RadioListTile<NotificationLevel>(
                        value: NotificationLevel.none,
                        title: Text('Pause all'),
                        subtitle: Text('No alerts at all until you turn this back'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'How they look',
              icon: Icons.tune_rounded,
              children: [
                SwitchListTile(
                  value: preferences.notificationPreviews,
                  onChanged: preferences.notificationLevel == NotificationLevel.none
                      ? null
                      : preferences.setNotificationPreviews,
                  title: const Text('Show message previews'),
                  subtitle: const Text(
                    'Off keeps the text out of the notification, so a glance at '
                    'a locked screen shows only who wrote',
                  ),
                  secondary: const Icon(Icons.visibility_outlined),
                ),
                SwitchListTile(
                  value: preferences.notificationSound,
                  onChanged: preferences.notificationLevel == NotificationLevel.none
                      ? null
                      : preferences.setNotificationSound,
                  title: const Text('Sound'),
                  subtitle: const Text('Off posts alerts silently'),
                  secondary: const Icon(Icons.volume_up_outlined),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _DeliveryNote(),
          ],
        ),
      ),
    );
  }
}

/// States the platform limit rather than letting the switches imply more than
/// they do.
class _DeliveryNote extends StatelessWidget {
  const _DeliveryNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Alerts are posted by this device while SejiloChat is running. '
              'The app has no push service configured, so a message that '
              'arrives while it is fully closed is shown the next time you '
              'open it.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
