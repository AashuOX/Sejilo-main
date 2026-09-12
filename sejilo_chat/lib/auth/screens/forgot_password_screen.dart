import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../design_system/components/sejilo_app_bar.dart';
import '../../design_system/components/sejilo_button.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/sejilo_theme.dart';
import '../account_auth_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.auth});

  final AccountAuthController auth;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.auth.requestPasswordReset(_emailController.text.trim());
      if (mounted) setState(() => _isSent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const SejiloAppBar(title: 'Reset Password'),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 440,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: _isSent ? _buildSuccessView(isDark) : _buildFormView(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: SejiloColors.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_reset_rounded, color: SejiloColors.primary, size: 34),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Trouble logging in?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your email and we'll send you a link to reset your password.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? SejiloColors.darkMuted : SejiloColors.lightMuted,
            ),
          ),
          const SizedBox(height: 28),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SejiloColors.danger.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SejiloColors.danger.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: SejiloColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: SejiloColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SejiloInput(
            controller: _emailController,
            labelText: 'Email Address',
            hintText: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SejiloButton(
            label: 'Send Reset Link',
            isLoading: _isLoading,
            onPressed: _handleReset,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SejiloColors.statusOnline.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_outlined, size: 48, color: SejiloColors.statusOnline),
          ),
          const SizedBox(height: 20),
          const Text(
            'Reset Link Sent',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'We have sent password reset instructions to ${_emailController.text.trim()}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? SejiloColors.darkMuted : SejiloColors.lightMuted, fontSize: 13),
          ),
          const SizedBox(height: 28),
          SejiloButton(
            label: 'Back to Log In',
            variant: SejiloButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
