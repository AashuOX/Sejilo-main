// create_post_page.dart — 100% Instagram-Style Content Creation Studio
// Features: Post/Story/Reel mode switcher, Filter Presets (Clarendon, Juno, Valencia, Mono),
// Hashtag suggestions, Location tagger, and instant feed publishing.

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/account_auth_controller.dart';
import '../core/image_utils.dart';
import '../design_system/sejilo_theme.dart';
import 'mention_picker.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({required this.auth, super.key});
  final AccountAuthController auth;

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  Uint8List? _imageBytes;
  String _mimeType = 'image/jpeg';
  final _caption = TextEditingController();
  String _selectedFilter = 'Normal';
  String _location = '';
  bool _publishing = false;
  int _modeIndex = 0; // 0: Post, 1: Story, 2: Reel

  static const List<String> _filters = [
    'Normal',
    'Clarendon',
    'Juno',
    'Ludwig',
    'Valencia',
    'Moon',
  ];

  static const List<String> _suggestedTags = [
    '#photography',
    '#travel',
    '#art',
    '#vibes',
    '#sunset',
    '#nature',
    '#aesthetic',
  ];

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes == null || !mounted) return;

    final optimized = await ImageUtils.optimizeImage(file!.bytes!);

    setState(() {
      _imageBytes = optimized.bytes;
      // Whatever the optimiser actually produced — guessing here is what used
      // to label PNG bytes as JPEG.
      _mimeType = optimized.mimeType;
    });
  }

  Future<void> _publish() async {
    if (_imageBytes == null || _publishing) return;
    setState(() => _publishing = true);

    try {
      if (_modeIndex == 1) {
        // Publish as Story
        await widget.auth.createStory(
          imageBytes: _imageBytes!,
          mimeType: _mimeType,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Story published successfully!')),
          );
        }
      } else {
        // Publish as Post / Reel
        final fullCaption = _location.isNotEmpty
            ? '${_caption.text}\n📍 $_location'
            : _caption.text;

        await widget.auth.createPost(
          image: _imageBytes!,
          mimeType: _mimeType,
          caption: fullCaption,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post shared to feed!')),
          );
        }
      }
      setState(() {
        _imageBytes = null;
        _caption.clear();
        _location = '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not publish: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _addTag(String tag) {
    setState(() {
      _caption.text = '${_caption.text} $tag'.trim();
    });
  }

  /// Adds a real account to the caption as `@username`.
  ///
  /// There is no separate "tagged users" field on a post server-side, so the
  /// mention lives in the caption — where [HashtagText] renders it as a link to
  /// that profile, which is what makes the tag do something for a reader.
  Future<void> _addMention() async {
    final username = await showMentionPicker(context, widget.auth);
    if (username == null || !mounted) return;
    if (_caption.text.contains('@$username')) return;
    setState(() {
      _caption.text = '${_caption.text} @$username'.trim();
    });
  }

  void _addLocation() async {
    final controller = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'City, venue or country'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (result != null) {
      setState(() => _location = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New post', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: (_imageBytes == null || _publishing) ? null : _publish,
              child: _publishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(
                      'Share',
                      style: TextStyle(
                        color: SejiloColors.instaBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            children: [
              // ── Mode Switcher: Post / Story / Reel ───
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: ['POST', 'STORY', 'REEL'].asMap().entries.map((entry) {
                    final isSelected = _modeIndex == entry.key;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _modeIndex = entry.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Media Box with Filter Preview ────────
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 320,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imageBytes != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_imageBytes!, fit: BoxFit.cover),
                            if (_selectedFilter == 'Moon')
                              Container(color: Colors.black.withValues(alpha: .3))
                            else if (_selectedFilter == 'Valencia')
                              Container(color: Colors.amber.withValues(alpha: .15))
                            else if (_selectedFilter == 'Clarendon')
                              Container(color: Colors.blue.withValues(alpha: .15)),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('Tap to choose a photo or video', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('JPEG, PNG or WebP — large photos are compressed for you', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: .5))),
                          ],
                        ),
                ),
              ),

              if (_imageBytes != null) ...[
                const SizedBox(height: 12),

                // ── Filters Row ────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _filters[i];
                      final isSelected = f == _selectedFilter;

                      return ChoiceChip(
                        label: Text(f, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedFilter = f),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Caption & User Info ──────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: widget.auth.profile?.avatarBytes != null
                        ? MemoryImage(widget.auth.profile!.avatarBytes!)
                        : null,
                    child: widget.auth.profile?.avatarBytes == null
                        ? Text(
                            (widget.auth.profile?.username ?? 'U').substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      maxLines: 4,
                      maxLength: 2200,
                      decoration: const InputDecoration(
                        hintText: 'Write a caption...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                        filled: false,
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(),

              // ── Quick Hashtag Suggestions ────────────
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _suggestedTags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final tag = _suggestedTags[i];
                    return ActionChip(
                      label: Text(tag, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _addTag(tag),
                      padding: EdgeInsets.zero,
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // ── Add Location ─────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(_location.isEmpty ? 'Add location' : _location),
                trailing: const Icon(Icons.chevron_right),
                onTap: _addLocation,
              ),

              // ── Tag People ───────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Tag people'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _addMention,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
