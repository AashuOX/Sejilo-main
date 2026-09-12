// account_screens.dart — 100% Instagram-Style Authentication
// Features: Phone Number (SMS/OTP flow with Country Codes), Google Sign-In,
// Email/Username Login, Sign Up, and Offline Continuity.

export '../profile/profile_page.dart';
export '../profile/public_profile_page.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'account_auth_controller.dart';

class AccountAuthScreen extends StatefulWidget {
  const AccountAuthScreen({
    required this.controller,
    this.onContinueOffline,
    super.key,
  });

  final AccountAuthController controller;
  final VoidCallback? onContinueOffline;

  @override
  State<AccountAuthScreen> createState() => _AccountAuthScreenState();
}

class _AccountAuthScreenState extends State<AccountAuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Mode: login vs register vs reset vs otp
  bool _isSignUp = false;
  bool _isReset = false;
  bool _isEnteringOtp = false;

  // Controllers
  final _phoneController = TextEditingController();
  final _emailUsernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _otpController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _newPasswordController = TextEditingController();

  // State
  bool _obscurePassword = true;
  String _selectedCountryCode = '+1';
  String _selectedCountryFlag = '🇺🇸';
  int _otpCountdown = 45;
  Timer? _countdownTimer;

  // Country Code Catalog
  static const List<Map<String, String>> _countryCodes = [
    {'code': '+1', 'flag': '🇺🇸', 'name': 'United States'},
    {'code': '+44', 'flag': '🇬🇧', 'name': 'United Kingdom'},
    {'code': '+91', 'flag': '🇮🇳', 'name': 'India'},
    {'code': '+977', 'flag': '🇳🇵', 'name': 'Nepal'},
    {'code': '+1', 'flag': '🇨🇦', 'name': 'Canada'},
    {'code': '+61', 'flag': '🇦🇺', 'name': 'Australia'},
    {'code': '+49', 'flag': '🇩🇪', 'name': 'Germany'},
    {'code': '+33', 'flag': '🇫🇷', 'name': 'France'},
    {'code': '+81', 'flag': '🇯🇵', 'name': 'Japan'},
    {'code': '+55', 'flag': '🇧🇷', 'name': 'Brazil'},
    {'code': '+971', 'flag': '🇦🇪', 'name': 'United Arab Emirates'},
    {'code': '+966', 'flag': '🇸🇦', 'name': 'Saudi Arabia'},
    {'code': '+92', 'flag': '🇵🇰', 'name': 'Pakistan'},
    {'code': '+880', 'flag': '🇧🇩', 'name': 'Bangladesh'},
    {'code': '+60', 'flag': '🇲🇾', 'name': 'Malaysia'},
    {'code': '+65', 'flag': '🇸🇬', 'name': 'Singapore'},
    {'code': '+82', 'flag': '🇰🇷', 'name': 'South Korea'},
    {'code': '+39', 'flag': '🇮🇹', 'name': 'Italy'},
    {'code': '+34', 'flag': '🇪🇸', 'name': 'Spain'},
    {'code': '+7', 'flag': '🇷🇺', 'name': 'Russia'},
    {'code': '+234', 'flag': '🇳🇬', 'name': 'Nigeria'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _emailUsernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    _resetTokenController.dispose();
    _newPasswordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startOtpTimer() {
    _countdownTimer?.cancel();
    setState(() => _otpCountdown = 45);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpCountdown > 0) {
        setState(() => _otpCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _fullPhoneNumber =>
      '$_selectedCountryCode ${_phoneController.text.trim()}';

  // ── Auth Actions ─────────────────────────────

  Future<void> _handleSendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number.')),
      );
      return;
    }

    try {
      final code = await widget.controller.sendPhoneOtp('$_selectedCountryCode$phone');
      _startOtpTimer();
      setState(() => _isEnteringOtp = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $_fullPhoneNumber (Code: $code)'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _handleVerifyPhoneOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit confirmation code.')),
      );
      return;
    }

    try {
      await widget.controller.verifyPhoneOtp(
        phoneNumber: '$_selectedCountryCode${_phoneController.text.trim()}',
        otp: otp,
        displayName: _fullNameController.text.trim().isNotEmpty
            ? _fullNameController.text.trim()
            : null,
        username: _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim()
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _handleEmailPasswordAuth() async {
    final input = _emailUsernameController.text.trim();
    final pass = _passwordController.text;

    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email or username.')),
      );
      return;
    }

    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }

    try {
      if (_isSignUp) {
        final email = input.contains('@') ? input : '$input@sejilochat.net';
        final username = _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim()
            : input.split('@').first;
        final name = _fullNameController.text.trim().isNotEmpty
            ? _fullNameController.text.trim()
            : username;

        await widget.controller.signUp(
          email: email,
          password: pass,
          username: username,
          displayName: name,
        );
      } else {
        final email = input.contains('@') ? input : '$input@sejilochat.net';
        await widget.controller.login(email: email, password: pass);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }



  void _showCountryPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select Country',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _countryCodes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = _countryCodes[i];
                      return ListTile(
                        leading: Text(item['flag']!, style: const TextStyle(fontSize: 24)),
                        title: Text(item['name']!),
                        trailing: Text(
                          item['code']!,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedCountryCode = item['code']!;
                            _selectedCountryFlag = item['flag']!;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo / Header ────────────────────────
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'SejiloChat',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [
                                  Color(0xFFF58529),
                                  Color(0xFFDD2A7B),
                                  Color(0xFF8134AF),
                                  Color(0xFF515BD4),
                                ],
                              ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'End-to-End Encrypted Social & Mesh Messenger',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: .6),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Main Card ────────────────────────────
                      if (_isEnteringOtp)
                        _buildOtpView(theme)
                      else if (_isReset)
                        _buildResetView(theme)
                      else
                        _buildMainAuthView(theme),

                      const SizedBox(height: 24),

                      // ── Footer: Switch Login / Sign Up ───────
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp
                                  ? 'Have an account? '
                                  : "Don't have an account? ",
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withValues(alpha: .7),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _isReset = false;
                                  _isEnteringOtp = false;
                                });
                              },
                              child: Text(
                                _isSignUp ? 'Log in' : 'Sign up',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Offline Mesh Continuation ────────────
                      if (widget.onContinueOffline != null) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: widget.onContinueOffline,
                          child: Text(
                            'Continue without account (Nearby Mesh Only)',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: .5),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Main Tabbed View (Phone / Email) ─────────

  Widget _buildMainAuthView(ThemeData theme) {
    return Column(
      children: [
        // Tab Header: PHONE vs EMAIL
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 2.5,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: .5),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.8),
            tabs: const [
              Tab(text: 'PHONE'),
              Tab(text: 'EMAIL / USERNAME'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          height: _isSignUp ? 340 : 220,
          child: TabBarView(
            controller: _tabController,
            children: [
              // ── Phone Input View ─────────────────────
              _buildPhoneTab(theme),

              // ── Email / Username View ────────────────
              _buildEmailTab(theme),
            ],
          ),
        ),
      ],
    );
  }

  // ── Phone Tab ────────────────────────────────

  Widget _buildPhoneTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSignUp) ...[
          _buildTextField(
            controller: _fullNameController,
            hintText: 'Full Name',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _usernameController,
            hintText: 'Username',
            icon: Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 10),
        ],

        // Country code + Phone Number row
        Row(
          children: [
            // Country picker button
            InkWell(
              onTap: _showCountryPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedCountryFlag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 4),
                    Text(
                      _selectedCountryCode,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Phone field
            Expanded(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Phone number',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Text(
          'You may receive SMS updates from SejiloChat for verification.',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: .5),
          ),
        ),
        const Spacer(),

        // Next / Send Code Button
        _GradientActionButton(
          text: _isSignUp ? 'Sign Up with Phone' : 'Send Login Code',
          onPressed: widget.controller.isBusy ? null : _handleSendPhoneOtp,
          isLoading: widget.controller.isBusy,
        ),
      ],
    );
  }

  // ── Email / Username Tab ─────────────────────

  Widget _buildEmailTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSignUp) ...[
          _buildTextField(
            controller: _fullNameController,
            hintText: 'Full Name',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _usernameController,
            hintText: 'Username',
            icon: Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 10),
        ],

        _buildTextField(
          controller: _emailUsernameController,
          hintText: 'Email or username',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 10),

        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),

        if (!_isSignUp) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _isReset = true),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 4)),
              child: const Text('Forgotten password?', style: TextStyle(fontSize: 12)),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
        ],

        const Spacer(),

        // Log In / Sign Up Button
        _GradientActionButton(
          text: _isSignUp ? 'Sign Up' : 'Log In',
          onPressed: widget.controller.isBusy ? null : _handleEmailPasswordAuth,
          isLoading: widget.controller.isBusy,
        ),
      ],
    );
  }

  // ── OTP Verification View ────────────────────

  Widget _buildOtpView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 52, color: Color(0xFFE91E63)),
        const SizedBox(height: 14),
        const Text(
          'Enter confirmation code',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter the 6-digit confirmation code we sent to $_fullPhoneNumber.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: .6)),
        ),
        const SizedBox(height: 24),

        // OTP Code Input
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w800),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: const TextStyle(letterSpacing: 10, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 16),

        _GradientActionButton(
          text: 'Confirm & Sign In',
          onPressed: widget.controller.isBusy ? null : _handleVerifyPhoneOtp,
          isLoading: widget.controller.isBusy,
        ),
        const SizedBox(height: 12),

        // Resend timer
        Center(
          child: _otpCountdown > 0
              ? Text(
                  'Resend code in 0:${_otpCountdown.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: .5)),
                )
              : TextButton(
                  onPressed: _handleSendPhoneOtp,
                  child: const Text('Resend confirmation code', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
        ),
        TextButton(
          onPressed: () => setState(() => _isEnteringOtp = false),
          child: const Text('Change Phone Number'),
        ),
      ],
    );
  }

  // ── Password Reset View ──────────────────────

  Widget _buildResetView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset_rounded, size: 52, color: Color(0xFFE91E63)),
        const SizedBox(height: 14),
        const Text(
          'Trouble with logging in?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your email or username and we will send you a login link or security token.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: .6)),
        ),
        const SizedBox(height: 20),

        _buildTextField(
          controller: _emailUsernameController,
          hintText: 'Email or username',
          icon: Icons.mail_outline_rounded,
        ),
        const SizedBox(height: 16),

        _GradientActionButton(
          text: 'Send Login Link',
          onPressed: () async {
            final email = _emailUsernameController.text.trim();
            if (email.isNotEmpty) {
              await widget.controller.requestPasswordReset(email);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password reset instructions sent.')),
                );
                setState(() => _isReset = false);
              }
            }
          },
          isLoading: widget.controller.isBusy,
        ),
        const SizedBox(height: 12),

        TextButton(
          onPressed: () => setState(() => _isReset = false),
          child: const Text('Back to Login', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // ── UI Helper Widgets ────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Gradient Action Button (Instagram-Style)
// ─────────────────────────────────────────────

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                colors: [
                  Color(0xFFF58529),
                  Color(0xFFDD2A7B),
                  Color(0xFF8134AF),
                ],
              ),
        color: onPressed == null ? Colors.grey.withValues(alpha: .3) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}


