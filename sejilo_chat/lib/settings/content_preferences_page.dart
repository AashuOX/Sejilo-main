// content_preferences_page.dart — what this device shows you.
//
// Both settings here are device-side by necessity: the API has no hidden-words
// field and no "hide counts" flag, so these change what gets drawn rather than
// what other people can post. The page says so.

import 'package:flutter/material.dart';
import '../core/app_preferences.dart';
import 'settings_section.dart';

class ContentPreferencesPage extends StatefulWidget {
  const ContentPreferencesPage({required this.preferences, super.key});

  final AppPreferences preferences;

  @override
  State<ContentPreferencesPage> createState() => _ContentPreferencesPageState();
}

class _ContentPreferencesPageState extends State<ContentPreferencesPage> {
  final TextEditingController _wordController = TextEditingController();

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _addWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    await widget.preferences.addHiddenWord(word);
    _wordController.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Content preferences',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) {
          final words = preferences.hiddenWords;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSection(
                title: 'Counts',
                icon: Icons.favorite_border_rounded,
                children: [
                  SwitchListTile(
                    value: preferences.hideLikeCounts,
                    onChanged: preferences.setHideLikeCounts,
                    title: const Text('Hide like and comment counts'),
                    subtitle: const Text(
                      'Numbers are hidden in the feed and on posts, including '
                      'your own. Your posts still collect likes.',
                    ),
                    secondary: const Icon(Icons.visibility_off_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSection(
                title: 'Hidden words',
                icon: Icons.filter_alt_outlined,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Comments containing one of these words are hidden from '
                      'you on this device. Whole words are matched, so "ace" '
                      'does not hide "space".',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _wordController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addWord(),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Word or phrase',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _addWord,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  if (words.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text('No hidden words yet.'),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final word in words)
                            InputChip(
                              label: Text(word),
                              onDeleted: () =>
                                  preferences.removeHiddenWord(word),
                            ),
                        ],
                      ),
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
