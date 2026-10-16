import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security_screen.dart';

import 'memory_screen.dart';
import 'general_screen.dart';
import 'usage_limits_screen.dart';
import 'account_details_screen.dart';



class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const Color _background = Color(0xFF000000);
  static const Color _card = Color(0xFF2D2D30);
  static const Color _divider = Color(0xFF48484D);
  static const Color _muted = Color(0xFFB8B8C0);

  User? get _user => FirebaseAuth.instance.currentUser;

  String get _displayName {
    final name = _user?.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = _user?.email?.trim() ?? '';
    return email.isNotEmpty ? email.split('@').first : 'Pengguna Upatt';
  }

  String get _initials {
    final parts = _displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _editName() async {
    final user = _user;
    if (user == null) return;
    final controller = TextEditingController(text: user.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222225),
        title: const Text('Ubah nama', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama yang ditampilkan',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null || result.trim().isEmpty) return;
    try {
      await user.updateDisplayName(result.trim());
      await user.reload();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama akun berhasil diperbarui.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memperbarui nama akun.')),
      );
    }
  }

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldConfirm = prefs.getBool('confirm_before_sign_out') ?? true;

    final confirmed = shouldConfirm
        ? await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222225),
        title: const Text('Keluar dari Upatt?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Kamu perlu masuk kembali untuk menggunakan akun ini.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5485D)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    )
        : true;
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openAccountDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AccountDetailsScreen(),
      ),
    );
  }

  Future<void> _openConversationMemory() async {
    if (_user == null) {
      _showInfo(
        'Memori percakapan',
        'Masuk ke akun Upatt untuk melihat memori percakapan.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MemoryScreen(),
      ),
    );
  }

  Future<void> _openGeneralScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const GeneralScreen(),
      ),
    );
  }

  Future<void> _openUsageLimitsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const UsageLimitsScreen(),
      ),
    );
  }

  Future<void> _openSecurityScreen() async {
    if (_user == null) {
      _showInfo(
        'Keamanan',
        'Masuk ke akun Upatt untuk mengelola keamanan akun.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SecurityScreen(),
      ),
    );
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222225),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF414145)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _rowItem({
    required IconData icon,
    required String title,
    String? trailing,
    VoidCallback? onTap,
    Color iconColor = Colors.white,
    bool showChevron = false,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        child: Row(
          children: [
            Icon(icon, size: 24, color: isDestructive ? const Color(0xFFFF6B75) : iconColor),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDestructive ? const Color(0xFFFF6B75) : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 14),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 7),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 22),
            ],
          ],
        ),
      ),
    );
  }

  Widget _withDividers(List<Widget> items) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const Divider(height: 1, thickness: 1, color: _divider, indent: 58));
      children.add(items[i]);
    }
    return _sectionCard(children);
  }

  Widget _sectionHeading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Akun', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A86B),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF414148), width: 3),
                        ),
                        child: Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w400)),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: const Color(0xFF202024),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Ubah nama',
                            onPressed: _editName,
                            icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 19),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(_displayName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(user?.email ?? 'Email tidak tersedia', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _withDividers([
              _rowItem(
                icon: Icons.account_circle_outlined,
                title: 'Akun',
                trailing: user?.email ?? 'Email tidak tersedia',
                onTap: _openAccountDetails,
                showChevron: true,
              ),
              _rowItem(
                icon: Icons.work_outline_rounded,
                title: 'Workspace',
                trailing: 'Pribadi',
                onTap: null,
                showChevron: false,
              ),
            ]),
            _sectionHeading('Preferensi Upatt'),
            _withDividers([
              _rowItem(
                icon: Icons.psychology_outlined,
                title: 'Memori percakapan',
                onTap: _openConversationMemory,
                showChevron: true,
              ),
            ]),
            _sectionHeading('Pengaturan'),
            _withDividers([
              _rowItem(
                icon: Icons.tune_rounded,
                title: 'Umum',
                onTap: _openGeneralScreen,
                showChevron: true,
              ),
              _rowItem(
                icon: Icons.data_usage_outlined,
                title: 'Penggunaan dan batasan',
                onTap: _openUsageLimitsScreen,
                showChevron: true,
              ),
              _rowItem(
                icon: Icons.security_outlined,
                title: 'Keamanan',
                onTap: _openSecurityScreen,
                showChevron: true,
              ),
            ]),
            _sectionHeading(''),
            _withDividers([
              _rowItem(
                icon: Icons.logout_rounded,
                title: 'Keluar',
                onTap: _signOut,
                isDestructive: true,
              ),
            ]),
            const SizedBox(height: 18),
            const Center(
              child: Text('Upatt AI', style: TextStyle(color: Color(0xFF777780), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
