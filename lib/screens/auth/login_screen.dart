import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/home_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // =========================
  // CONTROLLERS
  // =========================

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // =========================
  // STATE
  // =========================

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  String? _emailError;
  String? _passwordError;

  bool _emailTouched = false;
  bool _passwordTouched = false;

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    });
  }

  // =========================
  // CEK LOGIN VALID
  // =========================

  bool get _isLoginValid {
    return _emailController.text.trim().isNotEmpty &&
        _emailError == null &&
        _passwordController.text.isNotEmpty &&
        _passwordController.text.length >= 6 &&
        _passwordError == null;
  }

  // =========================
  // LOGIN EMAIL & PASSWORD
  // =========================

  Future<void> _login() async {
    if (!_isLoginValid || _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message = 'Email or password is incorrect.';
          break;

        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
          message = 'Incorrect password.';
          break;

        case 'invalid-email':
          message = 'The email address is invalid.';
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. Please try again later.';
          break;

        default:
          message = e.message ?? 'Login failed.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
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
  // LOGIN GOOGLE
  // =========================

  Future<void> _signInWithGoogle() async {
    if (_isGoogleLoading) {
      return;
    }

    setState(() {
      _isGoogleLoading = true;
    });

    try {
      // Google Login untuk Web
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();

        await FirebaseAuth.instance.signInWithPopup(
          googleProvider,
        );
      } else {
        // Android & iOS akan dikonfigurasi
        // pada tahap berikutnya.
        throw Exception(
          'Google Sign-In untuk Android/iOS belum dikonfigurasi.',
        );
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login Google gagal: ${e.message ?? e.code}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login Google gagal: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  // =========================
  // INPUT DECORATION
  // =========================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      errorText: errorText,
    );
  }

  // =========================
  // BUILD
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),

      body: Stack(
        children: [
          // =========================
          // BASE BLACK
          // =========================

          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF050505),
            ),
          ),

          // =========================
          // BOTTOM PURPLE GLOW
          // =========================

          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 1.15),
                  radius: 1.15,
                  colors: [
                    Color(0xFF382070),
                    Color(0xFF120D20),
                    Color(0x00050505),
                  ],
                  stops: [
                    0.0,
                    0.45,
                    1.0,
                  ],
                ),
              ),
            ),
          ),

          // =========================
          // SUBTLE GRAY TOP RIGHT
          // =========================

          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.15, -1.05),
                  radius: 0.9,
                  colors: [
                    Color(0xFF3A3A40),
                    Color(0x00050505),
                  ],
                  stops: [
                    0.0,
                    1.0,
                  ],
                ),
              ),
            ),
          ),

          // =========================
          // CONTENT
          // =========================

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),

                  // =========================
                  // LOGO UPATT
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
                      'Welcome Back!',
                      style: AppTextStyles.heading,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      'Chat smarter with Upatt',
                      style: AppTextStyles.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // =========================
                  // EMAIL
                  // =========================

                  Text(
                    'Email',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: _validateEmail,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Enter your email',
                      prefixIcon: Icons.email_outlined,
                      errorText:
                          _emailTouched ? _emailError : null,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // =========================
                  // PASSWORD
                  // =========================

                  Text(
                    'Password',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onChanged: _validatePassword,
                    onSubmitted: (_) {
                      if (_isLoginValid) {
                        _login();
                      }
                    },
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Enter your password',
                      prefixIcon: Icons.lock_outline,
                      errorText: _passwordTouched
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
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // =========================
                  // FORGOT PASSWORD
                  // =========================

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ForgotPasswordScreen(
                              initialEmail:
                                  _emailController.text.trim(),
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password?',
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // =========================
                  // LOGIN BUTTON
                  // =========================

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          _isLoginValid && !_isLoading
                              ? _login
                              : null,
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
                              'LOGIN',
                              style: AppTextStyles.button,
                            ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // DIVIDER
                  // =========================

                  Row(
                    children: [
                      const Expanded(
                        child: Divider(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        child: Text(
                          'or continue',
                          style:
                              AppTextStyles.bodySecondary,
                        ),
                      ),
                      const Expanded(
                        child: Divider(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // GOOGLE LOGIN
                  // =========================

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isGoogleLoading
                          ? null
                          : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF151518),
                        side: const BorderSide(
                          color: AppColors.border,
                        ),
                        foregroundColor:
                            AppColors.textPrimary,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                      ),
                      child: _isGoogleLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                    AppColors.primary,
                              ),
                            )
                          : Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment:
                                      Alignment.center,
                                  decoration:
                                      BoxDecoration(
                                    shape:
                                        BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          AppColors.border,
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/images/google_logo.png',
                                    width: 22,
                                    height: 22,
                                  ),
                                ),

                                const SizedBox(width: 10),

                                Text(
                                  'Continue with Google',
                                  style:
                                      AppTextStyles.body
                                          .copyWith(
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // REGISTER
                  // =========================

                  Center(
                    child: Text.rich(
                      TextSpan(
                        text:
                            "Don't have an account? ",
                        style:
                            AppTextStyles.bodySecondary,
                        children: [
                          WidgetSpan(
                            alignment:
                                PlaceholderAlignment
                                    .middle,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const RegisterScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Register',
                                style:
                                    AppTextStyles.body
                                        .copyWith(
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
          ),
        ],
      ),
    );
  }
}