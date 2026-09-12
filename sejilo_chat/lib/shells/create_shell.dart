import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_app_bar.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/sejilo_theme.dart';
import '../../auth/account_auth_controller.dart';
import '../../social/mention_picker.dart';

class CreateShell extends StatefulWidget {
  const CreateShell({super.key, required this.auth});

  final AccountAuthController auth;

  @override
  State<CreateShell> createState() => _CreateShellState();
}

class _CreateShellState extends State<CreateShell> {
  Uint8List? _selectedImageBytes;
  final _captionController = TextEditingController();
  bool _isPublishing = false;
  String _location = '';

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res != null && res.files.single.bytes != null) {
        setState(() {
          _selectedImageBytes = res.files.single.bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  /// Asks for a place name and keeps it until publish, where it is appended to
  /// the caption — the posts API has no separate location column, so the caption
  /// is the only field that can carry it.
  Future<void> _addLocation() async {
    final controller = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'City, venue or country'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _location = result);
  }

  /// Appends a real account as `@username`, chosen from `/v1/users/search`.
  ///
  /// The mention lives in the caption because there is no tagged-users field on
  /// a post server-side; the feed renders it as a link to that profile.
  Future<void> _addMention() async {
    final username = await showMentionPicker(context, widget.auth);
    if (username == null || !mounted) return;
    if (_captionController.text.contains('@$username')) return;
    setState(() {
      _captionController.text =
          '${_captionController.text} @$username'.trim();
    });
  }

  Future<void> _handlePublish() async {
    if (_selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final caption = _captionController.text.trim();
      await widget.auth.createPost(
        image: _selectedImageBytes!,
        caption: _location.isEmpty ? caption : '$caption\n📍 $_location'.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('🎉 Post published successfully!'),
        ),
      );

      setState(() {
        _selectedImageBytes = null;
        _captionController.clear();
        _location = '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish post: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: SejiloAppBar(
        title: 'New Post',
        actions: [
          if (_selectedImageBytes != null)
            TextButton(
              onPressed: _isPublishing ? null : _handlePublish,
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Share',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: SejiloColors.primary,
                      ),
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 600,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image Picker / Preview Area
                if (_selectedImageBytes == null)
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 280,
                      decoration: BoxDecoration(
                        color: isDark
                            ? SejiloColors.darkCard
                            : SejiloColors.lightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? SejiloColors.darkOutline
                              : SejiloColors.lightOutline,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  SejiloColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 48,
                              color: SejiloColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Select photo or image to share',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Supports PNG, JPG, WEBP (Auto-optimized)',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon:
                                const Icon(Icons.folder_open_rounded, size: 18),
                            label: const Text('Browse Files'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SejiloColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Image.memory(
                            _selectedImageBytes!,
                            fit: BoxFit.cover,
                            // The picker can hand back a file this platform has
                            // no codec for. Saying so beats a red error box
                            // where the preview should be.
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.withValues(alpha: 0.2),
                              child: const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'This image could not be previewed. Choose '
                                    'another one.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 18,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                            onPressed: () =>
                                setState(() => _selectedImageBytes = null),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Change',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 20),

                // Caption Input
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SejiloAvatar(
                      name: widget.auth.profile?.displayName ?? 'You',
                      imageBytes: widget.auth.profile?.avatarBytes,
                      size: SejiloAvatarSize.sm,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Write a caption… #hashtag @mention',
                          border: InputBorder.none,
                          hintStyle:
                              TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),

                // Location / Tags shortcut options
                ListTile(
                  leading: Icon(
                    Icons.location_on_outlined,
                    color: _location.isEmpty ? Colors.grey : SejiloColors.primary,
                  ),
                  title: Text(
                    _location.isEmpty ? 'Add Location' : _location,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: _location.isEmpty
                      ? const Icon(Icons.chevron_right,
                          color: Colors.grey, size: 20)
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove location',
                          onPressed: () => setState(() => _location = ''),
                        ),
                  onTap: _addLocation,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tag_rounded, color: Colors.grey),
                  title: const Text('Tag people',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Adds @username to your caption',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey, size: 20),
                  onTap: _addMention,
                ),
                const SizedBox(height: 24),

                // Publish CTA Button
                if (_selectedImageBytes != null)
                  SejiloButton(
                    label: _isPublishing ? 'Publishing Post…' : 'Publish Post',
                    isLoading: _isPublishing,
                    onPressed: _handlePublish,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
