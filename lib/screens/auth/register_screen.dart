import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/upatt_auth_background.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // =========================
  // CONTROLLERS
  // =========================

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // =========================
  // STATE
  // =========================

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _confirmPasswordTouched = false;

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // =========================
  // VALIDASI NAME
  // =========================

  void _validateName(String value) {
    setState(() {
      _nameTouched = true;

      if (value.trim().isEmpty) {
        _nameError = 'Name is required';
      } else if (value.trim().length < 2) {
        _nameError = 'Name must be at least 2 characters';
      } else {
        _nameError = null;
      }
    });
  }

  // =========================
  // VALIDASI EMAIL
  // =========================

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

  // =========================
  // VALIDASI PASSWORD
  // =========================

  void _validatePassword(String value) {
    setState(() {
      _passwordTouched = true;

      if (value.isEmpty) {
        _passwordError = 'Password is required';
      } else if (value.length < 6) {
        _passwordError =
            'Password must be at least 6 characters';
      } else {
        _passwordError = null;
      }

      // Validasi confirm password jika
      // user sudah mulai mengisinya.
      if (_confirmPasswordTouched) {
        if (_confirmPasswordController.text.isEmpty) {
          _confirmPasswordError =
              'Please confirm your password';
        } else if (_confirmPasswordController.text != value) {
          _confirmPasswordError = 'Passwords do not match';
        } else {
          _confirmPasswordError = null;
        }
      }
    });
  }

  // =========================
  // VALIDASI CONFIRM PASSWORD
  // =========================

  void _validateConfirmPassword(String value) {
    setState(() {
      _confirmPasswordTouched = true;

      if (value.isEmpty) {
        _confirmPasswordError =
            'Please confirm your password';
      } else if (value != _passwordController.text) {
        _confirmPasswordError =
            'Passwords do not match';
      } else {
        _confirmPasswordError = null;
      }
    });
  }

  // =========================
  // CEK FORM VALID
  // =========================

  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _nameController.text.trim().length >= 2 &&
        _emailController.text.trim().isNotEmpty &&
        _emailError == null &&
        _passwordController.text.length >= 6 &&
        _passwordError == null &&
        _confirmPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text ==
            _passwordController.text &&
        _confirmPasswordError == null;
  }

  // =========================
  // REGISTER FIREBASE
  // =========================

  Future<void> _register() async {
    if (!_isFormValid || _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Membuat akun Firebase
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Simpan nama user ke Firebase Authentication
      await userCredential.user?.updateDisplayName(
        _nameController.text.trim(),
      );

      // Logout sementara supaya user kembali ke
      // halaman Login dan bisa melakukan login normal.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created successfully!',
          ),
        ),
      );

      // Kembali ke Login
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message =
              'This email is already registered.';
          break;

        case 'invalid-email':
          message =
              'The email address is invalid.';
          break;

        case 'weak-password':
          message =
              'The password is too weak.';
          break;

        case 'operation-not-allowed':
          message =
              'Email/Password authentication is not enabled.';
          break;

        default:
          message =
              e.message ?? 'Registration failed.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // =========================
  // BUILD
  // =========================

  @override
  Widget build(BuildContext context) {
    return UpattAuthBackground(
      child: SafeArea(
        child: Stack(
          children: [

            // =========================
            // CONTENT
            // =========================

            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                24,
                48,
                24,
                24,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // =========================
                  // LOGO
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
                      'Create Account',
                      style: AppTextStyles.heading.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // =========================
                  // SUBTITLE
                  // =========================

                  Center(
                    child: Text(
                      'Create your account to start chatting',
                      style:
                          AppTextStyles.bodySecondary.copyWith(
                        color: const Color(0xFF8E8E98),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // =========================
                  // NAME
                  // =========================

                  Text(
                    'Name',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    onChanged: _validateName,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter your name',
                      hintStyle: const TextStyle(
                        color: Color(0xFF777780),
                      ),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF8E8E98),
                      ),
                      errorText:
                          _nameTouched ? _nameError : null,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1F),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF29292F),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                      focusedErrorBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // =========================
                  // EMAIL
                  // =========================

                  Text(
                    'Email',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _emailController,
                    keyboardType:
                        TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: _validateEmail,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      hintStyle: const TextStyle(
                        color: Color(0xFF777780),
                      ),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Color(0xFF8E8E98),
                      ),
                      errorText:
                          _emailTouched ? _emailError : null,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1F),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF29292F),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                      focusedErrorBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // =========================
                  // PASSWORD
                  // =========================

                  Text(
                    'Password',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: _validatePassword,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      hintStyle: const TextStyle(
                        color: Color(0xFF777780),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFF8E8E98),
                      ),
                      errorText:
                          _passwordTouched
                              ? _passwordError
                              : null,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword =
                                !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF8E8E98),
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1F),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF29292F),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                      focusedErrorBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // =========================
                  // CONFIRM PASSWORD
                  // =========================

                  Text(
                    'Confirm Password',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller:
                        _confirmPasswordController,
                    obscureText:
                        _obscureConfirmPassword,
                    textInputAction:
                        TextInputAction.done,
                    onChanged:
                        _validateConfirmPassword,
                    onSubmitted: (_) {
                      if (_isFormValid) {
                        _register();
                      }
                    },
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Confirm your password',
                      hintStyle: const TextStyle(
                        color: Color(0xFF777780),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_reset_outlined,
                        color: Color(0xFF8E8E98),
                      ),
                      errorText:
                          _confirmPasswordTouched
                              ? _confirmPasswordError
                              : null,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword =
                                !_obscureConfirmPassword;
                          });
                        },
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF8E8E98),
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1F),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF29292F),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                      focusedErrorBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // REGISTER BUTTON
                  // =========================

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          _isFormValid && !_isLoading
                              ? _register
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primary,
                        disabledBackgroundColor:
                            const Color(0xFF29292E),
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            const Color(0xFF77777F),
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
                              'REGISTER',
                              style:
                                  AppTextStyles.button.copyWith(
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // LOGIN
                  // =========================

                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style:
                            AppTextStyles.bodySecondary
                                .copyWith(
                          color: const Color(0xFF8E8E98),
                        ),
                        children: [
                          WidgetSpan(
                            alignment:
                                PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: Text(
                                'Login',
                                style:
                                    AppTextStyles.body.copyWith(
                                  color:
                                      AppColors.primary,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
            // =========================
            // BACK BUTTON
            // =========================

            Positioned(
              top: 4,
              left: 8,
              child: IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}