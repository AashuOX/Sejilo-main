import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/mesh_client.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/sejilo_theme.dart';
import '../../design_system/components/aurora_backdrop.dart';
import '../account_auth_controller.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? SejiloColors.darkBg : SejiloColors.lightBg;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: AuroraBackdrop(
        child: SafeArea(
          child: MaxWidthContainer(
            maxWidth: 480,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            child: Column(
              children: [
                const Spacer(),

                // Glass Hero Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 36),
                      decoration: BoxDecoration(
                        color: isDark
                            ? SejiloColors.darkSurface.withAlpha(190)
                            : Colors.white.withAlpha(220),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withAlpha(25)
                              : Colors.black.withAlpha(15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: SejiloColors.darkCyan.withAlpha(30),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glowing Logo
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              gradient: SejiloGradients.aurora,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: SejiloColors.darkCyan.withAlpha(100),
                                  blurRadius: 36,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: SejiloColors.darkMagenta.withAlpha(70),
                                  blurRadius: 20,
                                  offset: const Offset(6, 6),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 42,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Title: SejiloChat
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                SejiloGradients.aurora.createShader(bounds),
                            child: const Text(
                              'SejiloChat',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Tagline
                          const Text(
                            'Connect. Share. Anywhere.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Subtitle
                          Text(
                            'Your social network that works online\nand through offline Bluetooth mesh.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: isDark
                                  ? SejiloColors.darkTextSecondary
                                  : SejiloColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Buttons
                SejiloButton(
                  label: 'Create an Account',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RegisterScreen(
                          auth: widget.auth,
                          preferences: widget.preferences,
                          meshClient: widget.meshClient,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),

                SejiloButton(
                  label: 'Log In',
                  variant: SejiloButtonVariant.secondary,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LoginScreen(
                          auth: widget.auth,
                          preferences: widget.preferences,
                          meshClient: widget.meshClient,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Legal footer
                Text(
                  'Encrypted • Decentralized • Connected Anywhere',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? SejiloColors.darkTextMuted
                        : SejiloColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
