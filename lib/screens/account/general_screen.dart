import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeneralScreen extends StatefulWidget {
  const GeneralScreen({super.key});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  static const Color _background = Color(0xFF000000);
  static const Color _surface = Color(0xFF2C2C2E);
  static const Color _muted = Color(0xFFB8B8C0);
  static const Color _accent = Color(0xFF6B46FF);

  bool _loading = true;
  bool _confirmBeforeSignOut = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _confirmBeforeSignOut =
          prefs.getBool('confirm_before_sign_out') ?? true;
      _loading = false;
    });
  }

  Future<void> _setConfirmBeforeSignOut(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirm_before_sign_out', value);
    if (!mounted) return;
    setState(() => _confirmBeforeSignOut = value);
    _showToast(
      value
          ? 'Konfirmasi keluar diaktifkan.'
          : 'Konfirmasi keluar dinonaktifkan.',
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF29292F),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Umum',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _accent),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _settingTile(
                    title: 'Bahasa',
                    value: 'Indonesia',
                    onTap: _showLanguageInfo,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 28, 16, 12),
                    child: Text(
                      'Gunakan secara otomatis',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: _accent,
                      title: const Text(
                        'Konfirmasi sebelum keluar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      value: _confirmBeforeSignOut,
                      onChanged: _setConfirmBeforeSignOut,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Tampilkan konfirmasi sebelum keluar dari akun Upatt.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _settingTile({
    required String title,
    required String value,
    Widget? leading,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 15,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageInfo() {
    _showInfo(
      'Bahasa',
      'Saat ini Upatt menggunakan Bahasa Indonesia untuk halaman ini. Pilihan bahasa aplikasi secara menyeluruh belum diaktifkan.',
    );
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222225),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          message,
          style: const TextStyle(color: _muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }
}
