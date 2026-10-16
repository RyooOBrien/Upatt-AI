import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

  static const Color _background = Color(0xFF000000);
  static const Color _card = Color(0xFF2D2D30);
  static const Color _divider = Color(0xFF48484D);
  static const Color _muted = Color(0xFFB8B8C0);

  User? get _user => FirebaseAuth.instance.currentUser;

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
          'Akun',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: _divider, width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _detailRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: user?.email ?? 'Email tidak tersedia',
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: _divider,
                  ),
                  _detailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Usia',
                    value: 'Belum diatur',
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: _divider,
                  ),
                  _detailRow(
                    icon: Icons.add_box_outlined,
                    label: 'Langganan',
                    value: 'Gratis',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Informasi akun yang terhubung ke Upatt.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 25),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                color: _muted,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
