import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../services/firebase_service.dart';
import 'auth_form.dart';

/// Sign-up form shown in a modal bottom sheet (e.g. two-thirds height).
class SignUpSheetContent extends StatefulWidget {
  final VoidCallback? onSuccess;
  final VoidCallback onClose;

  const SignUpSheetContent({
    super.key,
    this.onSuccess,
    required this.onClose,
  });

  @override
  State<SignUpSheetContent> createState() => _SignUpSheetContentState();
}

class _SignUpSheetContentState extends State<SignUpSheetContent> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await FirebaseService.signUp(email, password).timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw Exception('Connection timed out. Check your network.'),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (!mounted) return;
      if (FirebaseService.isSignedIn) {
        widget.onSuccess?.call();
        return;
      }
      setState(() {
        _error =
            'Account created! Check your email to confirm, then sign in.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = FirebaseService.friendlyAuthError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Join Potluck',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kCharcoal,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  color: kCharcoal,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  AuthForm(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    error: _error,
                    loading: _loading,
                    isSignUp: true,
                    obscurePassword: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: kSoftSlateGray, fontSize: 14),
                        children: [
                          TextSpan(
                            text: 'Sign In',
                            style: const TextStyle(
                              color: kDeepForestGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
