import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/app_preferences.dart';
import '../../core/mesh_client.dart';
import '../../core/responsive.dart';
import '../../design_system/components/aurora_backdrop.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/sejilo_theme.dart';
import '../account_auth_controller.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;

  // Real-time strength calculation
  int _passwordStrength = 0; // 0 = empty, 1 = weak, 2 = medium, 3 = strong

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_evalPassword);
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _evalPassword() {
    final pass = _passwordController.text;
    if (pass.isEmpty) {
      setState(() => _passwordStrength = 0);
      return;
    }
    int score = 0;
    if (pass.length >= 8) score++;
    if (pass.length >= 8 && RegExp(r'[0-9]').hasMatch(pass)) score++;
    if (pass.length >= 10 && RegExp(r'[^a-zA-Z0-9]').hasMatch(pass)) score++;
    setState(() => _passwordStrength = score == 0 ? 1 : score);
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim().toLowerCase();
    final email = _emailController.text.trim();

    try {
      await widget.auth.signUp(
        email: email,
        username: username,
        displayName: username,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProfileSetupScreen(
            auth: widget.auth,
            preferences: widget.preferences,
            meshClient: widget.meshClient,
          ),
        ),
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
    final passwordsMatch = _confirmPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text == _passwordController.text;

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

                      // Glass Card Header & Body
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
                                // Glowing Logo Badge
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
                                        Icons.person_add_alt_1_rounded,
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
                                    'Create Account',
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
                                  'Experience ultra-fast cloud & offline mesh chat',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? SejiloColors.darkTextSecondary
                                        : SejiloColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 24),

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

                                // Username Input
                                SejiloInput(
                                  controller: _usernameController,
                                  labelText: 'Username',
                                  hintText: 'e.g. alex_stone',
                                  prefixIcon: const Icon(
                                      Icons.alternate_email_rounded,
                                      size: 20),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Username is required';
                                    }
                                    if (v.trim().length < 3) {
                                      return 'Must be at least 3 characters';
                                    }
                                    if (!RegExp(r'^[a-zA-Z0-9._]+$')
                                        .hasMatch(v.trim())) {
                                      return 'Only letters, numbers, dots & underscores';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Email Input
                                SejiloInput(
                                  controller: _emailController,
                                  labelText: 'Email Address',
                                  hintText: 'name@example.com',
                                  keyboardType: TextInputType.emailAddress,
                                  prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                      size: 20),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Email is required';
                                    }
                                    if (!v.contains('@') || !v.contains('.')) {
                                      return 'Enter a valid email address';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Password Input
                                SejiloInput(
                                  controller: _passwordController,
                                  labelText: 'Password',
                                  hintText: 'At least 8 characters',
                                  isPassword: true,
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (v.length < 8) {
                                      return 'At least 8 characters required';
                                    }
                                    return null;
                                  },
                                ),

                                // Password Strength Meter
                                if (_passwordStrength > 0) ...[
                                  const SizedBox(height: 8),
                                  _buildStrengthBar(isDark),
                                ],

                                const SizedBox(height: 14),

                                // Confirm Password Input
                                SejiloInput(
                                  controller: _confirmPasswordController,
                                  labelText: 'Confirm Password',
                                  hintText: 'Re-enter your password',
                                  isPassword: true,
                                  prefixIcon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 20),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleRegister(),
                                  suffixIcon: _confirmPasswordController
                                          .text.isNotEmpty
                                      ? Icon(
                                          passwordsMatch
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          size: 18,
                                          color: passwordsMatch
                                              ? SejiloColors.statusOnline
                                              : SejiloColors.danger,
                                        )
                                      : null,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Please confirm your password';
                                    }
                                    if (v != _passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 24),

                                // Main Register Button
                                SejiloButton(
                                  label: 'Create Account',
                                  isLoading: _isLoading,
                                  onPressed: _handleRegister,
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
                            'Already have an account? ',
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
                                  builder: (_) => LoginScreen(
                                    auth: widget.auth,
                                    preferences: widget.preferences,
                                    meshClient: widget.meshClient,
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Log In',
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

  Widget _buildStrengthBar(bool isDark) {
    Color barColor;
    String label;

    switch (_passwordStrength) {
      case 1:
        barColor = SejiloColors.danger;
        label = 'Weak';
        break;
      case 2:
        barColor = Colors.orange;
        label = 'Good';
        break;
      case 3:
      default:
        barColor = SejiloColors.statusOnline;
        label = 'Strong';
        break;
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _passwordStrength / 3.0,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: barColor,
          ),
        ),
      ],
    );
  }
}
