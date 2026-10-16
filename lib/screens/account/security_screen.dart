import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  static const Color _background = Color(0xFF000000);
  static const Color _surface = Color(0xFF1C1C20);
  static const Color _border = Color(0xFF303036);
  static const Color _muted = Color(0xFFB8B8C0);
  static const Color _accent = Color(0xFF6B46FF);

  bool _sendingReset = false;
  bool _sendingVerification = false;

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  User? get _user => FirebaseAuth.instance.currentUser;

  String get _providerLabel {
    final user = _user;
    if (user == null) return 'Tidak diketahui';

    final providers = user.providerData
        .map((provider) => provider.providerId)
        .toSet();

    final labels = <String>[];
    if (providers.contains('google.com')) labels.add('Google');
    if (providers.contains('password')) labels.add('Email dan password');
    if (labels.isEmpty) labels.add('Firebase Authentication');

    return labels.join(' • ');
  }

  Future<void> _sendPasswordReset() async {
    final email = _user?.email?.trim();
    if (email == null || email.isEmpty) {
      _showMessage(
        'Email akun tidak tersedia. Tambahkan alamat email terlebih dahulu.',
        isError: true,
      );
      return;
    }

    setState(() => _sendingReset = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _showMessage('Link reset password telah dikirim ke $email.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'invalid-email' => 'Alamat email akun tidak valid.',
        'too-many-requests' =>
          'Terlalu banyak permintaan. Coba lagi beberapa saat.',
        'network-request-failed' =>
          'Koneksi internet bermasalah. Periksa koneksi lalu coba lagi.',
        _ => 'Gagal mengirim email reset password. Coba lagi nanti.',
      };
      _showMessage(message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Terjadi kesalahan saat mengirim email reset password.',
          isError: true);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _sendVerificationEmail() async {
    final user = _user;
    if (user == null) return;

    if (user.emailVerified) {
      _showMessage('Email akun ini sudah terverifikasi.');
      return;
    }

    setState(() => _sendingVerification = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      _showMessage('Link verifikasi telah dikirim ke ${user.email ?? 'email akun'}.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'too-many-requests' =>
          'Terlalu banyak permintaan. Coba lagi beberapa saat.',
        'network-request-failed' =>
          'Koneksi internet bermasalah. Periksa koneksi lalu coba lagi.',
        _ => 'Gagal mengirim email verifikasi. Coba lagi nanti.',
      };
      _showMessage(message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Terjadi kesalahan saat mengirim email verifikasi.',
          isError: true);
    } finally {
      if (mounted) setState(() => _sendingVerification = false);
    }
  }

  Future<void> _refreshVerificationStatus() async {
    final user = _user;
    if (user == null) return;

    try {
      await user.reload();
      if (!mounted) return;
      setState(() {});
      _showMessage(
        FirebaseAuth.instance.currentUser?.emailVerified == true
            ? 'Status email: sudah terverifikasi.'
            : 'Email belum terverifikasi. Periksa inbox dan folder spam.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Tidak dapat memperbarui status email.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context);
    final accent = isError
        ? const Color(0xFFFBBF24)
        : const Color(0xFF9B83FF);

    _toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -18 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222225),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.32),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            isError
                                ? Icons.info_outline_rounded
                                : Icons.check_rounded,
                            color: accent,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            _toastTimer?.cancel();
                            _toastEntry?.remove();
                            _toastEntry = null;
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFFB8B8C0),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(milliseconds: 3200), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Keamanan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: user == null
            ? const Center(
                child: Text(
                  'Tidak ada akun yang sedang masuk.',
                  style: TextStyle(color: _muted),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  const Text(
                    'Akun dan keamanan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kelola informasi akun dan akses keamanan Upatt melalui Firebase Authentication.',
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('INFORMASI AKUN'),
                  const SizedBox(height: 10),
                  _panel(
                    children: [
                      _infoRow(
                        label: 'Nama',
                        value: user.displayName?.trim().isNotEmpty == true
                            ? user.displayName!.trim()
                            : 'Belum diatur',
                      ),
                      const Divider(color: _border, height: 1),
                      _infoRow(
                        label: 'Email',
                        value: user.email ?? 'Tidak tersedia',
                      ),
                      const Divider(color: _border, height: 1),
                      _infoRow(
                        label: 'Metode masuk',
                        value: _providerLabel,
                      ),
                      const Divider(color: _border, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Text(
                                'Verifikasi email',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  user.emailVerified
                                      ? 'Terverifikasi'
                                      : 'Belum terverifikasi',
                                  style: TextStyle(
                                    color: user.emailVerified
                                        ? const Color(0xFF4ADE80)
                                        : const Color(0xFFFBBF24),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (!user.emailVerified)
                                  TextButton(
                                    onPressed: _sendingVerification
                                        ? null
                                        : _sendVerificationEmail,
                                    child: Text(
                                      _sendingVerification
                                          ? 'Mengirim...'
                                          : 'Kirim verifikasi',
                                    ),
                                  ),
                                TextButton(
                                  onPressed: _refreshVerificationStatus,
                                  child: const Text('Periksa status'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('AKSES AKUN'),
                  const SizedBox(height: 10),
                  _panel(
                    children: [
                      _actionRow(
                        icon: Icons.lock_reset_rounded,
                        title: 'Reset password',
                        description:
                            'Kirim tautan untuk membuat password baru ke email akun.',
                        trailing: _sendingReset
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _accent,
                                ),
                              )
                            : const Icon(
                                Icons.chevron_right_rounded,
                                color: _muted,
                              ),
                        onTap: _sendingReset ? null : _sendPasswordReset,
                      ),
                      const Divider(color: _border, height: 1),
                      _actionRow(
                        icon: Icons.info_outline_rounded,
                        title: 'Tentang keamanan',
                        description:
                            'Autentikasi akun dikelola oleh Firebase. Password tidak ditampilkan di aplikasi.',
                        trailing: const Icon(
                          Icons.verified_user_outlined,
                          color: _accent,
                        ),
                        onTap: () => _showMessage(
                          'Untuk keamanan, Upatt tidak pernah menampilkan atau menyimpan password dalam bentuk teks.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Reset password memerlukan alamat email yang dapat diakses. Jika masuk dengan Google, pengaturan password Google dilakukan melalui akun Google.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: _muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _panel({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String description,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
