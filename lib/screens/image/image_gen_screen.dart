import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../services/ai_service.dart';
import 'image_viewer_screen.dart';

/// Halaman khusus untuk membuat gambar dari prompt teks (text-to-image).
///
/// Prompt dikirim ke backend (`POST /api/image`) yang memanggil model gambar
/// (mis. Qwen-Image). Hasilnya ditampilkan sebagai galeri di halaman ini dan
/// bisa dibuka layar penuh.
class ImageGenScreen extends StatefulWidget {
  const ImageGenScreen({super.key});

  @override
  State<ImageGenScreen> createState() => _ImageGenScreenState();
}

/// Pilihan rasio gambar beserta ukuran yang dikirim ke backend.
/// Format ukuran DashScope memakai tanda bintang, mis. "1024*1024".
class _AspectOption {
  const _AspectOption(this.label, this.size);

  final String label;
  final String size;
}

/// Satu gambar hasil. Bytes disimpan di memori (hanya untuk sesi ini).
class _GeneratedImage {
  _GeneratedImage({required this.prompt, required this.bytes});

  final String prompt;
  final Uint8List bytes;
}

class _ImageGenScreenState extends State<ImageGenScreen> {
  static const List<_AspectOption> _aspects = [
    _AspectOption('1:1', '1024*1024'),
    _AspectOption('16:9', '1280*720'),
    _AspectOption('3:4', '768*1024'),
    _AspectOption('9:16', '720*1280'),
  ];

  static const String _promptHint =
      'Contoh: poster healing bergaya gambar tangan, langit senja, '
      'kucing oranye duduk di rumput hijau.';

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _negativeController = TextEditingController();

  final List<_GeneratedImage> _results = [];

  int _aspectIndex = 0;
  bool _isGenerating = false;
  bool _showAdvanced = false;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  // Ubah data URL base64 ("data:image/png;base64,...") menjadi bytes gambar.
  Uint8List? _decodeDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');

    if (commaIndex <= 0) return null;

    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _generate() async {
    if (_isGenerating) return;

    final prompt = _promptController.text.trim();

    if (prompt.isEmpty) {
      setState(() {
        _error = 'Tulis dulu prompt gambar yang kamu inginkan.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final dataUrl = await AiService.generateImage(
        prompt: prompt,
        negativePrompt: _negativeController.text.trim(),
        size: _aspects[_aspectIndex].size,
      );

      final bytes = _decodeDataUrl(dataUrl);

      if (bytes == null) {
        throw Exception('Format gambar dari server tidak dikenali.');
      }

      if (!mounted) return;

      setState(() {
        _results.insert(
          0,
          _GeneratedImage(prompt: prompt, bytes: bytes),
        );
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _copyPrompt(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prompt disalin.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Buat Gambar',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildPromptCard(),
          const SizedBox(height: 20),
          if (_results.isEmpty && !_isGenerating)
            _buildEmptyState()
          else
            ..._results.map(_buildResultCard),
        ],
      ),
    );
  }

  // =========================================================
  // FORM
  // =========================================================

  Widget _buildPromptCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prompt gambar',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptController,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            enabled: !_isGenerating,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: _promptHint,
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBackground,
              counterStyle: const TextStyle(color: AppColors.textSecondary),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Pengaturan lanjutan: prompt negatif.
          InkWell(
            onTap: () {
              setState(() => _showAdvanced = !_showAdvanced);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Pengaturan lanjutan',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _negativeController,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              enabled: !_isGenerating,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Prompt negatif (opsional)',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: 'Hal yang tidak diinginkan, mis. teks blur, '
                    'tangan cacat.',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBackground,
                counterStyle: const TextStyle(color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Text(
            'Rasio',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(_aspects.length, (index) {
              final option = _aspects[index];
              final selected = index == _aspectIndex;

              return ChoiceChip(
                label: Text(option.label),
                selected: selected,
                onSelected: _isGenerating
                    ? null
                    : (_) => setState(() => _aspectIndex = index),
                backgroundColor: AppColors.inputBackground,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected
                      ? Colors.white
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                side: const BorderSide(color: AppColors.border),
                showCheckmark: false,
              );
            }),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1D1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6B2A2A)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFFB4AB),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _isGenerating ? 'Membuat gambar...' : 'Buat Gambar',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 10),
            const Text(
              'Proses ini bisa memakan waktu 10-30 detik.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.image_outlined,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          const Text(
            'Hasil gambar akan muncul di sini',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tulis prompt, pilih rasio, lalu tekan Buat Gambar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HASIL
  // =========================================================

  Widget _buildResultCard(_GeneratedImage image) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openImageViewer(image),
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: Image.memory(
                image.bytes,
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.prompt,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _openImageViewer(image),
                      icon: const Icon(Icons.zoom_in_rounded, size: 18),
                      label: const Text('Lihat penuh'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 18),
                    TextButton.icon(
                      onPressed: () => _copyPrompt(image.prompt),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Salin prompt'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Penampil layar penuh memakai layar yang sudah ada ([ImageViewerScreen]).
  void _openImageViewer(_GeneratedImage image) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          bytes: image.bytes,
          title: image.prompt,
        ),
      ),
    );
  }
}
