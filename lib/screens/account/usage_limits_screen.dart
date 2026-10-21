import 'package:flutter/material.dart';

import '../../models/usage_models.dart';
import '../../services/usage_service.dart';

/// Halaman penggunaan dan batasan Upatt-AI.
///
/// Seluruh angka (persentase tersisa, tanggal reset, status kredit, dan status
/// koneksi AI) diambil dari backend melalui [UsageService]. Layout/desain
/// dipertahankan sama seperti referensi; hanya datanya dibuat dinamis.
class UsageLimitsScreen extends StatefulWidget {
  const UsageLimitsScreen({super.key});

  @override
  State<UsageLimitsScreen> createState() => _UsageLimitsScreenState();
}

class _UsageLimitsScreenState extends State<UsageLimitsScreen> {
  static const Color _background = Color(0xFF000000);
  static const Color _card = Color(0xFF2D2D2F);
  static const Color _border = Color(0xFF4A4A4D);
  static const Color _muted = Color(0xFFBDBDC2);
  static const Color _accent = Color(0xFFB2C9FF);

  final _service = UsageService.instance;

  bool _loading = true;
  String? _error;

  UsageSummary? _summary;
  UsageLimits? _limits;
  AiStatus? _status;
  AccountUsageSettings? _account;

  static const List<String> _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.fetchLimits(),
        _service.fetchAiStatus(),
        _service.fetchAccountSettings(),
        _service.fetchSummary(),
      ]);

      if (!mounted) return;
      setState(() {
        _limits = results[0] as UsageLimits;
        _status = results[1] as AiStatus;
        _account = results[2] as AccountUsageSettings;
        _summary = results[3] as UsageSummary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day} ${_monthNames[date.month - 1]}';
  }

  String _formatFullDate(DateTime? date) {
    if (date == null) return '-';
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return '${date.day}/${date.month}/$yy';
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF242426),
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

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 30, 4, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _muted,
                fontSize: 19,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border, width: 1.2),
      );

  // Kartu garis besar (skeleton) agar ukuran tidak meloncat saat memuat.
  Widget _skeletonCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: _cardDecoration(),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 16,
            width: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF3A3A3D)),
            ),
          ),
          SizedBox(height: 20),
          SizedBox(
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF3A3A3D)),
            ),
          ),
          SizedBox(height: 18),
          SizedBox(
            height: 13,
            width: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF3A3A3D)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tidak dapat memuat data',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Terjadi kesalahan.',
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'Pastikan backend Upatt berjalan dan alamatnya benar.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  Widget _limitsCard() {
    final fraction = _limits?.remainingFraction ?? 0.0;
    final percentLabel = '${(fraction * 100).round()}% tersisa';
    final resetLabel = 'Reset pada ${_formatDate(_limits?.resetAt)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Batas penggunaan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                percentLabel,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: const Color(0xFF56565A),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            resetLabel,
            style: const TextStyle(color: _muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // Baris info ringkas bergaya sama untuk kartu statistik & status AI.
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Kartu statistik permintaan (dinamis dari /usage/summary).
  Widget _statsCard() {
    final s = _summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistik permintaan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow('Hari ini', '${s?.todayRequests ?? 0} permintaan'),
          _infoRow('7 hari terakhir', '${s?.last7Requests ?? 0} permintaan'),
          _infoRow('30 hari terakhir', '${s?.last30Requests ?? 0} permintaan'),
          _infoRow('Total token', _formatTokens(s?.allTimeTokens ?? 0)),
        ],
      ),
    );
  }

  // Kartu status koneksi layanan AI (dinamis dari /ai/status).
  Widget _aiStatusCard() {
    final st = _status;
    final statusLabel =
        (st?.status.isNotEmpty ?? false) ? st!.status : 'tidak diketahui';
    final statusLower = statusLabel.toLowerCase();
    final statusColor = statusLower == 'online'
        ? const Color(0xFF8FE3A6)
        : statusLower == 'degraded'
            ? const Color(0xFFE3C98F)
            : _muted;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Koneksi layanan AI',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(
            'Model aktif',
            (st?.model.isNotEmpty ?? false) ? st!.model : '-',
          ),
          _infoRow(
            'Provider',
            (st?.provider.isNotEmpty ?? false) ? st!.provider : '-',
          ),
          _infoRow(
            'Latency terakhir',
            st?.latencyMs == null ? '-' : '${st!.latencyMs} ms',
          ),
        ],
      ),
    );
  }

  // Format angka token dengan pemisah ribuan titik.
  String _formatTokens(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '$buffer token';
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
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF303032),
              side: const BorderSide(color: _border),
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 27),
          ),
        ),
        title: const Text(
          'Penggunaan dan batasan',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: _accent,
          backgroundColor: _card,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
            children: [
              _sectionTitle('Batas penggunaan agentic'),
              if (_loading)
                _skeletonCard()
              else if (_error != null)
                _errorCard()
              else ...[
                _limitsCard(),
                const SizedBox(height: 14),
                _statsCard(),
                const SizedBox(height: 14),
                _aiStatusCard(),
              ],

              _sectionTitle(
                'Reset batas penggunaan',
                trailing: IconButton(
                  tooltip: 'Tentang reset batas',
                  onPressed: () => _showInfo(
                    'Reset batas penggunaan',
                    'Batas harian direset setiap hari. Tanggal reset langganan '
                        'mengikuti data paket akunmu.',
                  ),
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: _muted,
                    size: 24,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => _showInfo(
                    'Reset penuh (bulanan)',
                    'Berakhir ${_formatFullDate(_limits?.billingResetAt)}. '
                        'Tanggal ini dihitung dari awal bulan berikutnya sebagai '
                        'siklus reset bulanan.',
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 18, 22),
                    decoration: _cardDecoration(),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Reset penuh (bulanan)',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Berakhir ${_formatFullDate(_limits?.billingResetAt)}',
                          style: const TextStyle(color: _muted, fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded,
                            color: _muted, size: 26),
                      ],
                    ),
                  ),
                ),
              ),

              _sectionTitle('Kredit'),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _toggleAutomaticRecharge,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 18, 22),
                    decoration: _cardDecoration(),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Isi ulang otomatis',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        Text(
                          (_account?.automaticRecharge ?? false)
                              ? 'Aktif'
                              : 'Nonaktif',
                          style: const TextStyle(color: _muted, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded,
                            color: _muted, size: 26),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: Text(
                  'Kredit dapat memperpanjang penggunaan setelah melewati batas paket.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAutomaticRecharge() async {
    if (_account == null) return;

    final next = !_account!.automaticRecharge;

    // Optimistis: ubah tampilan dulu, lalu simpan ke backend.
    setState(() {
      _account = AccountUsageSettings(
        automaticRecharge: next,
        plan: _account!.plan,
      );
    });

    try {
      final saved = await _service.setAutomaticRecharge(next);
      if (!mounted) return;
      setState(() {
        _account = AccountUsageSettings(
          automaticRecharge: saved,
          plan: _account!.plan,
        );
      });
    } catch (e) {
      if (!mounted) return;
      // Kembalikan bila gagal.
      setState(() {
        _account = AccountUsageSettings(
          automaticRecharge: !next,
          plan: _account!.plan,
        );
      });
      _showInfo(
        'Gagal menyimpan',
        e.toString().replaceFirst('Exception: ', '').trim(),
      );
    }
  }
}
