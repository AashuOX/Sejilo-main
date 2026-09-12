// appearance_settings_page.dart — theme and visual effects.
//
// Both settings were already real; this version wraps them in a
// ListenableBuilder so the page repaints from the preference itself rather than
// relying on an ancestor rebuild, and uses the shared section header.

import 'package:flutter/material.dart';
import '../core/app_preferences.dart';
import 'settings_section.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({required this.preferences, super.key});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Appearance',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsSection(
              title: 'Theme',
              icon: Icons.palette_outlined,
              children: [
                RadioGroup<ThemeMode>(
                  groupValue: preferences.themeMode,
                  onChanged: (value) {
                    if (value != null) preferences.setThemeMode(value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: Text('System'),
                        subtitle: Text('Follow the device setting'),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: Text('Dark'),
                        subtitle: Text('Aurora dark palette'),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: Text('Light'),
                        subtitle: Text('Clean light palette'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Effects',
              icon: Icons.auto_awesome_outlined,
              children: [
                SwitchListTile(
                  value: preferences.auroraEffects,
                  onChanged: preferences.setAuroraEffects,
                  title: const Text('Aurora effects'),
                  subtitle: const Text(
                    'Gradient accents and glow. Off is plainer and draws less.',
                  ),
                  secondary: const Icon(Icons.gradient_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
