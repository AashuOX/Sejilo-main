import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/mesh_client.dart';
import '../../design_system/sejilo_theme.dart';
import '../../design_system/components/aurora_backdrop.dart';
import '../account_auth_controller.dart';
import 'welcome_screen.dart';
import '../../shells/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.auth, this.preferences, this.meshClient});

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    if (widget.auth.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MainShell(
            auth: widget.auth,
            preferences: widget.preferences,
            meshClient: widget.meshClient,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WelcomeScreen(
            auth: widget.auth,
            preferences: widget.preferences,
            meshClient: widget.meshClient,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
      body: AuroraBackdrop(
          child: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            gradient: SejiloColors.sejiloGradient,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: SejiloColors.primary.withAlpha(100),
                                blurRadius: 28,
                                offset: const Offset(0, 8),
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
                        const SizedBox(height: 20),
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              SejiloColors.sejiloGradient.createShader(bounds),
                          child: const Text(
                            'SejiloChat',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Social & Decentralized Mesh Messaging',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? SejiloColors.darkMuted
                                : SejiloColors.lightMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'from Sejilo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color:
                      isDark ? SejiloColors.darkMuted : SejiloColors.lightMuted,
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }
}
