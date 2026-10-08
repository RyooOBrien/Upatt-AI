import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/upatt_auth_background.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  String? _emailError;
  bool _emailTouched = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialEmail != null &&
        widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _validateEmail(String value) {
    setState(() {
      _emailTouched = true;

      if (value.trim().isEmpty) {
        _emailError = 'Email is required';
      } else {
        final emailRegex = RegExp(
          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
        );

        if (!emailRegex.hasMatch(value.trim())) {
          _emailError = 'Enter a valid email address';
        } else {
          _emailError = null;
        }
      }
    });
  }

  bool get _isFormValid {
    return _emailController.text.trim().isNotEmpty &&
        _emailError == null;
  }

  Future<void> _sendResetEmail() async {
    _validateEmail(_emailController.text);

    if (!_isFormValid || _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1D),
            surfaceTintColor: Colors.transparent,
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.primary,
              size: 48,
            ),
            title: Text(
              'Check Your Email',
              style: AppTextStyles.heading.copyWith(
                color: Colors.white,
                fontSize: 22,
              ),
              textAlign: TextAlign.center,
            ),
            content: Text(
              'If an account exists for this email address, '
              'we have sent a password reset link. '
              'Please check your inbox and follow the instructions.',
              style: AppTextStyles.bodySecondary.copyWith(
                color: const Color(0xFF9CA3AF),
              ),
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pop(context);
                },
                child: Text(
                  'BACK TO LOGIN',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        switch (e.code) {
          case 'invalid-email':
            _emailError = 'The email address is invalid.';
            break;

          case 'too-many-requests':
            _emailError =
                'Too many requests. Try again later.';
            break;

          default:
            _emailError =
                e.message ?? 'Failed to send reset email.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _emailError =
            'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpattAuthBackground(
      child: SafeArea(
        child: Column(
          children: [
            // =========================
            // BACK BUTTON
            // =========================
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  top: 8,
                ),
                child: IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
              ),
            ),

            // =========================
            // CONTENT
            // =========================
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),

                    // =========================
                    // ICON
                    // =========================
                    Center(
                      child: Image.asset(
                        'assets/images/upatt_logo.png',
                        width: 104,
                        height: 104,
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // =========================
                    // TITLE
                    // =========================
                    Center(
                      child: Text(
                        'Forgot Password?',
                        style: AppTextStyles.heading.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'Enter your email and we\'ll send you '
                        'a link to reset your password.',
                        style: AppTextStyles.bodySecondary
                            .copyWith(
                          color: const Color(0xFF9CA3AF),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 38),

                    // =========================
                    // EMAIL LABEL
                    // =========================
                    Text(
                      'Email',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // =========================
                    // EMAIL FIELD
                    // =========================
                    TextField(
                      controller: _emailController,
                      keyboardType:
                          TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      onChanged: _validateEmail,
                      onSubmitted: (_) {
                        if (_isFormValid && !_isLoading) {
                          _sendResetEmail();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter your email',
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                        ),
                        errorText: _emailTouched
                            ? _emailError
                            : null,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // =========================
                    // SEND BUTTON
                    // =========================
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _isFormValid && !_isLoading
                                ? _sendResetEmail
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF29292D),
                          disabledForegroundColor:
                              const Color(0xFF77777D),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'SEND RESET LINK',
                                style:
                                    AppTextStyles.button
                                        .copyWith(
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // =========================
                    // BACK TO LOGIN
                    // =========================
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(
                          'Back to Login',
                          style:
                              AppTextStyles.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}