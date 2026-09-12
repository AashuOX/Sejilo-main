import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/mesh_client.dart';
import '../../core/responsive.dart';
import '../../design_system/components/aurora_backdrop.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/sejilo_theme.dart';
import '../../shells/main_shell.dart';
import '../account_auth_controller.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.auth.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
      resizeToAvoidBottomInset: true,
      body: AuroraBackdrop(
        child: SafeArea(
          child: MaxWidthContainer(
            maxWidth: 460,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Form(
              key: _formKey,
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
                                // Glowing Lock Logo
                                Center(
                                  child: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      gradient: SejiloGradients.aurora,
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: SejiloColors.darkCyan.withAlpha(90),
                                          blurRadius: 28,
                                          offset: const Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: SejiloColors.darkMagenta.withAlpha(60),
                                          blurRadius: 18,
                                          offset: const Offset(4, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.lock_outline_rounded,
                                        color: Colors.white,
                                        size: 32,
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
                                    'Welcome Back',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.6,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Enter your credentials to access your account',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? SejiloColors.darkTextSecondary
                                        : SejiloColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Server Connection Chip
                                _ServerStatusChip(auth: widget.auth),
                                const SizedBox(height: 12),

                                // Error Banner if present
                                if (_errorMessage != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: SejiloColors.danger.withAlpha(25),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: SejiloColors.danger.withAlpha(80)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded,
                                            color: SejiloColors.danger, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: const TextStyle(
                                              color: SejiloColors.danger,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Email/Username Input
                                SejiloInput(
                                  controller: _emailController,
                                  labelText: 'Email or Username',
                                  hintText: 'name@example.com or username',
                                  keyboardType: TextInputType.text,
                                  prefixIcon: const Icon(
                                      Icons.person_outline_rounded,
                                      size: 20),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Email or Username is required';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Password Input
                                SejiloInput(
                                  controller: _passwordController,
                                  labelText: 'Password',
                                  hintText: '••••••••',
                                  isPassword: true,
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleLogin(),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    return null;
                                  },
                                ),

                                // Forgot Password Link
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ForgotPasswordScreen(
                                              auth: widget.auth),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        color: SejiloColors.darkCyan,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Login Button
                                SejiloButton(
                                  label: 'Log In',
                                  isLoading: _isLoading,
                                  onPressed: _handleLogin,
                                ),


                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Footer Navigation
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => RegisterScreen(
                                    auth: widget.auth,
                                    preferences: widget.preferences,
                                    meshClient: widget.meshClient,
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                color: SejiloColors.darkCyan,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerStatusChip extends StatefulWidget {
  const _ServerStatusChip({required this.auth});

  final AccountAuthController auth;

  @override
  State<_ServerStatusChip> createState() => _ServerStatusChipState();
}

class _ServerStatusChipState extends State<_ServerStatusChip> {
  bool _checking = false;
  ServerProbe? _probe;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _probe = null;
    });
    final probe = await widget.auth.probeServer();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _probe = probe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final probe = _probe;
    final color = probe == null
        ? Colors.grey
        : probe.isReady
            ? Colors.green
            : probe.reachable
                ? Colors.orange
                : Colors.red;
    return Center(
      child: TextButton.icon(
        onPressed: _checking ? null : _check,
        icon: _checking
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                probe?.reachable == true
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
                size: 16,
                color: color),
        label: Text(
          probe?.detail ?? 'Test server connection',
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54),
        ),
      ),
    );
  }
}
