import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/chat_repository.dart';
import '../image/image_viewer_screen.dart';

/// Halaman **Pustaka**: riwayat gambar & file yang pernah dikirim ke chatbot.
///
/// Data dibaca dari metadata lampiran setiap pesan. Gambar bisa dilihat lagi
/// (lewat thumbnail yang tersimpan), dan tiap item bisa ditautkan kembali ke
/// percakapan asalnya.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibraryFilter { all, image, file }

class _LibraryScreenState extends State<LibraryScreen> {
  final ChatRepository _repository = ChatRepository();
  final TextEditingController _searchController = TextEditingController();

  List<LibraryAttachment> _items = const [];
  bool _loading = true;
  String? _error;
  _LibraryFilter _filter = _LibraryFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await _repository.fetchLibrary();

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '').trim();
        _loading = false;
      });
    }
  }

  List<LibraryAttachment> get _visibleItems {
    final query = _query.trim().toLowerCase();

    return _items.where((item) {
      if (_filter == _LibraryFilter.image && !item.isImage) return false;
      if (_filter == _LibraryFilter.file && item.isImage) return false;
      if (query.isEmpty) return true;

      return item.name.toLowerCase().contains(query) ||
          item.chatTitle.toLowerCase().contains(query);
    }).toList();
  }

  int get _imageCount => _items.where((item) => item.isImage).length;

  int get _fileCount => _items.length - _imageCount;

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pustaka',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Cari nama file atau percakapan...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: AppColors.inputBackground,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFilterChip(
                label: 'Semua',
                count: _items.length,
                value: _LibraryFilter.all,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Gambar',
                count: _imageCount,
                value: _LibraryFilter.image,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'File',
                count: _fileCount,
                value: _LibraryFilter.file,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required _LibraryFilter value,
  }) {
    final selected = _filter == value;

    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      backgroundColor: AppColors.inputBackground,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: AppColors.border),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return _buildMessage(
        icon: Icons.error_outline_rounded,
        title: 'Gagal memuat pustaka',
        subtitle: _error!,
        action: TextButton(
          onPressed: _load,
          child: const Text('Coba lagi'),
        ),
      );
    }

    if (_items.isEmpty) {
      return _buildMessage(
        icon: Icons.photo_library_outlined,
        title: 'Pustaka masih kosong',
        subtitle: 'Gambar dan file yang kamu kirim ke chatbot akan muncul '
            'di sini.',
      );
    }

    final items = _visibleItems;

    if (items.isEmpty) {
      return _buildMessage(
        icon: Icons.search_off_rounded,
        title: 'Tidak ada hasil',
        subtitle: 'Tidak ada lampiran yang cocok dengan pencarian/filter.',
      );
    }

    final images = items.where((item) => item.isImage).toList();
    final files = items.where((item) => !item.isImage).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (images.isNotEmpty) ...[
            _buildSectionHeader('Gambar', images.length),
            const SizedBox(height: 10),
            _buildImageGrid(images),
            const SizedBox(height: 22),
          ],
          if (files.isNotEmpty) ...[
            _buildSectionHeader('File', files.length),
            const SizedBox(height: 8),
            ...files.map(_buildFileTile),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Text(
      '$title · $count',
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 54,
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================
  // GAMBAR (GRID)
  // =========================================================

  Widget _buildImageGrid(List<LibraryAttachment> images) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) => _buildImageTile(images[index]),
    );
  }

  Widget _buildImageTile(LibraryAttachment item) {
    final bytes = _decodeThumb(item.thumb);

    return GestureDetector(
      onTap: bytes == null
          ? () => _showDetail(item)
          : () => _openViewer(bytes, item.name),
      onLongPress: () => _showDetail(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: AppColors.inputBackground,
          child: bytes == null
              ? const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.textSecondary,
                  ),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }

  // =========================================================
  // FILE
  // =========================================================

  Widget _buildFileTile(LibraryAttachment item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDetail(item),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _fileIcon(item.name),
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatBytes(item.size)} · ${item.chatTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // DETAIL
  // =========================================================

  void _showDetail(LibraryAttachment item) {
    final bytes = _decodeThumb(item.thumb);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (item.isImage && bytes != null) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openViewer(bytes, item.name);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        bytes,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  item.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _detailRow('Jenis', item.isImage ? 'Gambar' : 'File'),
                _detailRow('Ukuran', _formatBytes(item.size)),
                _detailRow('Percakapan', item.chatTitle),
                _detailRow('Dikirim', _formatDate(item.createdAt)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.isImage && bytes != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _openViewer(bytes, item.name);
                          },
                          icon: const Icon(Icons.zoom_in_rounded, size: 18),
                          label: const Text('Lihat penuh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    if (item.isImage && bytes != null)
                      const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          // Kembalikan ID percakapan ke halaman utama.
                          Navigator.of(context).pop(item.chatId);
                        },
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('Buka chat'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================

  void _openViewer(Uint8List bytes, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(bytes: bytes, title: name),
      ),
    );
  }

  Uint8List? _decodeThumb(String? thumb) {
    if (thumb == null || thumb.isEmpty) return null;

    try {
      return base64Decode(thumb);
    } catch (_) {
      return null;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Ukuran tidak diketahui';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  IconData _fileIcon(String name) {
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'md':
        return Icons.article_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
        return Icons.audiotrack_rounded;
      case 'mp4':
      case 'mov':
      case 'mkv':
        return Icons.movie_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
