import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/image_utils.dart';
import '../../core/mesh_client.dart';
import '../../core/responsive.dart';
import '../../design_system/components/aurora_backdrop.dart';
import '../../design_system/components/sejilo_avatar.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/sejilo_theme.dart';
import '../../shells/main_shell.dart';
import '../account_auth_controller.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController(text: 'Hey there! I am using SejiloChat.');
  Uint8List? _avatarBytes;
  String? _avatarMimeType;
  bool _isLoading = false;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    final profile = widget.auth.profile;
    _displayNameController.text = profile?.displayName ?? profile?.username ?? '';
    _birthDate = profile?.birthDate ?? DateTime(2000, 1, 1);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (res != null && res.files.single.bytes != null) {
        final optimized = await ImageUtils.optimizeImage(
          res.files.single.bytes!,
          maxDimension: ImageUtils.maxAvatarDimension,
        );
        if (!mounted) return;
        setState(() {
          _avatarBytes = optimized.bytes;
          _avatarMimeType = optimized.mimeType;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not use that photo: $e')),
        );
      }
    }
  }

  Future<void> _handleComplete() async {
    setState(() => _isLoading = true);
    try {
      final cur = widget.auth.profile;
      final name = _displayNameController.text.trim().isNotEmpty
          ? _displayNameController.text.trim()
          : (cur?.displayName ?? cur?.username ?? 'User');

      await widget.auth.updateProfile(
        username: cur?.username ?? 'user',
        displayName: name,
        bio: _bioController.text.trim(),
        avatarBytes: _avatarBytes,
        avatarMimeType: _avatarMimeType,
        birthDate: _birthDate ?? DateTime(2000, 1, 1),
      );
      if (!mounted) return;
      _navigateToHome();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => MainShell(
          auth: widget.auth,
          preferences: widget.preferences,
          meshClient: widget.meshClient,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000, 1, 1),
      firstDate: DateTime(today.year - 120),
      lastDate: DateTime(today.year - 10, today.month, today.day),
      helpText: 'YOUR BIRTHDAY',
    );
    if (selected != null && mounted) {
      setState(() => _birthDate = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = widget.auth.profile;

    return Scaffold(
      backgroundColor: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
      resizeToAvoidBottomInset: true,
      body: AuroraBackdrop(
        child: SafeArea(
          child: MaxWidthContainer(
            maxWidth: 460,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),

                    // Glass Card Container
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? SejiloColors.darkSurface.withAlpha(200)
                                : Colors.white.withAlpha(230),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withAlpha(25)
                                  : Colors.black.withAlpha(15),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: SejiloColors.darkCyan.withAlpha(25),
                                blurRadius: 36,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Avatar with glowing ring
                              Center(
                                child: Stack(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: SejiloGradients.aurora,
                                      ),
                                      child: SejiloAvatar(
                                        imageBytes: _avatarBytes,
                                        name: profile?.displayName ?? profile?.username ?? 'User',
                                        size: SejiloAvatarSize.xl,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: InkWell(
                                        onTap: _pickAvatar,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: SejiloGradients.aurora,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isDark ? SejiloColors.darkBg : Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton(
                                  onPressed: _pickAvatar,
                                  child: const Text(
                                    'Choose Profile Photo',
                                    style: TextStyle(
                                      color: SejiloColors.darkCyan,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Title
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    SejiloGradients.aurora.createShader(bounds),
                                child: const Text(
                                  'Complete Your Profile',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Personalize your identity on the network',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? SejiloColors.darkTextSecondary
                                      : SejiloColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Display Name
                              SejiloInput(
                                controller: _displayNameController,
                                labelText: 'Display Name',
                                hintText: 'Your Name or Alias',
                                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                              ),
                              const SizedBox(height: 14),

                              // Bio Input
                              SejiloInput(
                                controller: _bioController,
                                labelText: 'About You',
                                hintText: 'Status or bio...',
                                maxLines: 2,
                                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                              ),
                              const SizedBox(height: 14),

                              // Birthday Selector
                              Text(
                                'Birthday',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? SejiloColors.darkMuted : SejiloColors.lightMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickBirthDate,
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? SejiloColors.darkSurfaceElevated
                                        : SejiloColors.lightSurfaceSecondary,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark ? SejiloColors.darkDivider : SejiloColors.lightDivider,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.cake_outlined, size: 20, color: SejiloColors.darkCyan),
                                      const SizedBox(width: 10),
                                      Text(
                                        _birthDate == null
                                            ? 'Select Birthday'
                                            : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const Spacer(),
                                      const Icon(Icons.arrow_drop_down_rounded, size: 22),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Complete Button
                              SejiloButton(
                                label: 'Start Messaging',
                                isLoading: _isLoading,
                                onPressed: _handleComplete,
                              ),
                              const SizedBox(height: 12),

                              // Skip Button
                              Center(
                                child: TextButton(
                                  onPressed: _navigateToHome,
                                  child: Text(
                                    'Skip for now →',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
