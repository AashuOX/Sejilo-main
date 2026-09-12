import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/sejilo_theme.dart';

class StoryCreatorScreen extends StatefulWidget {
  const StoryCreatorScreen({super.key, required this.auth});

  final AccountAuthController auth;

  static Future<bool?> open(BuildContext context, AccountAuthController auth) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => StoryCreatorScreen(auth: auth),
      ),
    );
  }

  @override
  State<StoryCreatorScreen> createState() => _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends State<StoryCreatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Uint8List? _selectedImageBytes;
  final _captionController = TextEditingController();
  final _textStoryController = TextEditingController();
  int _selectedGradientIndex = 0;
  bool _isPublishing = false;

  static const List<LinearGradient> _textGradients = [
    LinearGradient(
      colors: [Color(0xFF833AB4), Color(0xFFE1306C), Color(0xFFF77737)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF130CB7), Color(0xFF52E5E7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2C3E50), Color(0xFF000000)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF654EA3), Color(0xFFEAAFC8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _captionController.dispose();
    _textStoryController.dispose();
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
          SnackBar(content: Text('Failed to pick photo: $e')),
        );
      }
    }
  }

  Future<void> _publishImageStory() async {
    if (_selectedImageBytes == null) return;
    setState(() => _isPublishing = true);

    try {
      await widget.auth.createImageStory(
        imageBytes: _selectedImageBytes!,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('✨ Added to Your Story!'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish story: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _publishTextStory() async {
    final text = _textStoryController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type something to share')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      await widget.auth.createTextStory(
        text: text,
        backgroundStyle: 'gradient_$_selectedGradientIndex',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('✨ Added to Your Story!'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish story: $e')),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Add to Story',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: SejiloColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Photo Story'),
            Tab(text: 'Text Story'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Photo Story Creator
            _buildPhotoStoryTab(isDark),
            // Tab 2: Text Story Creator
            _buildTextStoryTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoStoryTab(bool isDark) {
    if (_selectedImageBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Share a photo or moment',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Disappears automatically after 24 hours',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: const Text('Select Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SejiloColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                _selectedImageBytes!,
                fit: BoxFit.cover,
              ),
              Positioned(
                top: 16,
                right: 16,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  radius: 18,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _selectedImageBytes = null),
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _captionController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Add a text overlay / caption…',
                      hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black,
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SejiloButton(
                  label: _isPublishing ? 'Sharing…' : 'Share to Your Story',
                  isLoading: _isPublishing,
                  onPressed: _publishImageStory,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextStoryTab() {
    final gradient = _textGradients[_selectedGradientIndex];

    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(gradient: gradient),
            padding: const EdgeInsets.symmetric(horizontal: 32),
            alignment: Alignment.center,
            child: TextField(
              controller: _textStoryController,
              textAlign: TextAlign.center,
              maxLines: 8,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black38, blurRadius: 12),
                ],
              ),
              decoration: const InputDecoration(
                hintText: 'Tap to type…',
                hintStyle: TextStyle(
                    color: Colors.white60,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        // Gradient selector bar & Publish button
        Container(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _textGradients.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedGradientIndex;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedGradientIndex = index),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _textGradients[index],
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : Border.all(color: Colors.white24, width: 1),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SejiloButton(
                label: _isPublishing ? 'Sharing…' : 'Share to Your Story',
                isLoading: _isPublishing,
                onPressed: _publishTextStory,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
