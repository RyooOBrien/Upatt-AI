import 'package:flutter/material.dart';

class UsageLimitsScreen extends StatelessWidget {
  const UsageLimitsScreen({super.key});

  static const Color _background = Color(0xFF000000);
  static const Color _surface = Color(0xFF1C1C20);
  static const Color _border = Color(0xFF303036);
  static const Color _muted = Color(0xFFB8B8C0);
  static const Color _accent = Color(0xFF9B83FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Penggunaan dan batasan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          const Text(
            'Penggunaan AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Informasi penggunaan yang dapat ditampilkan saat ini.',
            style: TextStyle(color: _muted, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 22),
          _infoCard(
            icon: Icons.query_stats_rounded,
            title: 'Statistik permintaan',
            value: 'Belum tersedia',
            description:
                'Backend Upatt saat ini belum menyediakan endpoint statistik jumlah permintaan atau token. Angka penggunaan tidak ditampilkan agar tidak memberikan data perkiraan seolah-olah akurat.',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.speed_rounded,
            title: 'Batas penggunaan',
            value: 'Dikelola server',
            description:
                'Batas permintaan mengikuti konfigurasi backend dan penyedia model AI yang terhubung. Batas dan sisa kuota belum dapat dibaca langsung dari aplikasi.',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.cloud_done_outlined,
            title: 'Koneksi layanan AI',
            value: 'Melalui backend Upatt',
            description:
                'Permintaan chat dikirim melalui layanan backend yang dikonfigurasi. Informasi biaya, token, dan kuota penyedia tidak otomatis tersedia di aplikasi tanpa dukungan endpoint dari backend.',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: _accent, size: 20),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Tidak ada angka penggunaan atau kuota yang dibuat-buat. Statistik real-time baru bisa ditampilkan setelah backend menyediakan data penggunaan.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: _accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            value,
            style: const TextStyle(
              color: _accent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            description,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
