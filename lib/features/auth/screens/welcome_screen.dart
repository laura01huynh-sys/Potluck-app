import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../services/firebase_service.dart';
import '../widgets/auth_form.dart';
import '../widgets/sign_up_sheet_content.dart';

/// Welcome / auth screen: sign in and sign up (sign up can open in a modal).
class WelcomeScreen extends StatefulWidget {
  /// Called when sign-up succeeds — app shows Chef Identity step next.
  final VoidCallback? onSignUpSuccess;

  /// Called when sign-in succeeds — app goes to Home.
  final VoidCallback? onSignInSuccess;

  const WelcomeScreen({super.key, this.onSignUpSuccess, this.onSignInSuccess});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  void _showSignUpModal(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.66;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => SizedBox(
        height: height,
        child: SignUpSheetContent(
          onSuccess: () {
            Navigator.pop(modalContext);
            widget.onSignUpSuccess?.call();
          },
          onClose: () => Navigator.pop(modalContext),
        ),
      ),
    );
  }

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
      if (_isSignUp) {
        await FirebaseService.signUp(email, password).timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw Exception('Connection timed out. Check your network.'),
        );
      } else {
        await FirebaseService.signIn(email, password).timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw Exception('Connection timed out. Check your network.'),
        );
      }
      if (!mounted) return;
      if (FirebaseService.isSignedIn) {
        setState(() => _loading = false);
        if (!mounted) return;
        if (_isSignUp) {
          widget.onSignUpSuccess?.call();
        } else {
          widget.onSignInSuccess?.call();
        }
      } else {
        setState(() {
          _error = _isSignUp
              ? 'Account created! Check your email to confirm, then sign in.'
              : 'Sign-in failed. Please try again.';
          _loading = false;
        });
      }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSignUp = _isSignUp;

    return Scaffold(
      backgroundColor: isSignUp
          ? kDeepForestGreen.withOpacity(0.06)
          : kBoneCreame,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSignUp) _buildSignUpHeader(),
                if (!isSignUp) _buildSignInHeader(),
                if (isSignUp)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AuthForm(
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
                  )
                else
                  AuthForm(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    error: _error,
                    loading: _loading,
                    isSignUp: false,
                    obscurePassword: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    onSubmit: _submit,
                  ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    if (isSignUp) {
                      setState(() {
                        _isSignUp = false;
                        _error = null;
                      });
                    } else {
                      _showSignUpModal(context);
                    }
                  },
                  child: Text.rich(
                    TextSpan(
                      text: isSignUp
                          ? 'Already have an account? '
                          : "Don't have an account? ",
                      style: TextStyle(color: kSoftSlateGray, fontSize: 14),
                      children: [
                        TextSpan(
                          text: isSignUp ? 'Sign In' : 'Sign Up',
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
      ),
    );
  }

  Widget _buildSignUpHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: 28,
            horizontal: 24,
          ),
          decoration: BoxDecoration(
            color: kDeepForestGreen,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kDeepForestGreen.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Column(
            children: [
              Icon(
                Icons.restaurant_menu,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 12),
              Text(
                'Join Potluck',
                style: TextStyle(
                  fontFamily: 'Lora',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildSignInHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: kDeepForestGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kDeepForestGreen.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.restaurant_menu,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome back',
          style: TextStyle(
            fontFamily: 'Lora',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: kDeepForestGreen,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to continue',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: kSoftSlateGray,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

}
