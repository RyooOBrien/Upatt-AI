import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/attachment_picker_service.dart';
import '../../services/project_repository.dart';
import 'project_result.dart';

/// Halaman detail sebuah **proyek**: kelola sumber materi dan lihat chat
/// yang termasuk di dalam proyek ini.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final ProjectRepository _repository = ProjectRepository();

  late String _name = widget.project.name;
  late String _description = widget.project.description;

  bool _uploading = false;
  String _uploadLabel = '';

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _cleanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();

    return text.isEmpty ? 'Terjadi kesalahan.' : text;
  }

  // =========================================================
  // SUMBER MATERI
  // =========================================================

  Future<void> _addSources() async {
    if (_uploading) return;

    List<Map<String, dynamic>> picked;

    try {
      picked = await AttachmentPickerService.pick('File');
    } catch (error) {
      _showMessage(_cleanError(error));
      return;
    }

    if (picked.isEmpty) return;

    final files = picked.where((item) => item['bytes'] is Uint8List).toList();

    if (files.isEmpty) {
      _showMessage('File tidak bisa dibaca.');
      return;
    }

    for (final file in files) {
      final name = file['name'] as String? ?? 'Sumber';
      final bytes = file['bytes'] as Uint8List;

      setState(() {
        _uploading = true;
        _uploadLabel = name;
      });

      try {
        await _repository.addSource(
          projectId: widget.project.id,
          name: name,
          bytes: bytes,
        );

        _showMessage('$name ditambahkan.');
      } catch (error) {
        _showMessage('Gagal menambahkan $name: ${_cleanError(error)}');
      }
    }

    if (mounted) {
      setState(() {
        _uploading = false;
        _uploadLabel = '';
      });
    }
  }

  Future<void> _deleteSource(ProjectSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Hapus sumber?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '"${source.name}" akan dihapus dari proyek.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteSource(widget.project.id, source);
      _showMessage('Sumber dihapus.');
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  void _showSourceDetail(ProjectSource source) {
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
                Text(
                  source.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _detailRow('Jenis', source.type.toUpperCase()),
                _detailRow('Ukuran', _formatBytes(source.size)),
                _detailRow(
                  'Teks terbaca',
                  source.hasText
                      ? '${_formatNumber(source.charCount)} karakter'
                      : 'Tidak bisa dibaca',
                ),
                if (source.extractError.isNotEmpty)
                  _detailRow('Catatan', source.extractError),
                const SizedBox(height: 14),
                if (source.hasText)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _SourceTextScreen(
                              title: source.name,
                              text: source.text,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.subject_rounded, size: 18),
                      label: const Text('Lihat teks'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  )
                else
                  Text(
                    source.type == 'image'
                        ? 'Gambar tidak bisa dibaca AI. Gunakan file teks atau '
                            'PDF agar isinya bisa jadi konteks.'
                        : 'Isi file tidak bisa dibaca. Coba file lain atau '
                            'tipe teks/PDF.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // PROYEK (ganti nama / hapus)
  // =========================================================

  Future<void> _renameProject() async {
    final nameController = TextEditingController(text: _name);
    final descriptionController = TextEditingController(text: _description);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Ganti Nama Proyek',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nama proyek',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descriptionController,
              style: const TextStyle(color: AppColors.textPrimary),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Deskripsi (opsional)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final name = nameController.text.trim();

    if (name.isEmpty) {
      _showMessage('Nama proyek tidak boleh kosong.');
      return;
    }

    try {
      await _repository.updateProject(
        widget.project.id,
        name: name,
        description: descriptionController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _name = name;
        _description = descriptionController.text.trim();
      });
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _deleteProject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Hapus proyek?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '"$_name" beserta semua sumber dan chat di dalamnya akan dihapus '
          'permanen.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteProject(widget.project.id);

      if (!mounted) return;

      Navigator.of(context).pop();
      _showMessage('Proyek dihapus.');
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  void _startNewChat() {
    Navigator.of(context).pop(
      ProjectResult(projectId: widget.project.id, projectName: _name),
    );
  }

  void _openChat(String chatId) {
    Navigator.of(context).pop(
      ProjectResult(
        projectId: widget.project.id,
        projectName: _name,
        chatId: chatId,
      ),
    );
  }

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
        title: Text(
          _name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: AppColors.surface,
            onSelected: (value) {
              if (value == 'rename') {
                _renameProject();
              } else if (value == 'delete') {
                _deleteProject();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
              PopupMenuItem(value: 'delete', child: Text('Hapus proyek')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_description.isNotEmpty) ...[
            Text(
              _description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
          ],
          _sectionHeader(
            title: 'SUMBER MATERI',
            actionLabel: 'Tambah',
            actionIcon: Icons.add_rounded,
            onAction: _uploading ? null : _addSources,
          ),
          if (_uploading) _buildUploadBanner(),
          const SizedBox(height: 8),
          _buildSources(),
          const SizedBox(height: 24),
          _sectionHeader(
            title: 'CHAT DI PROYEK INI',
            actionLabel: 'Chat Baru',
            actionIcon: Icons.add_comment_outlined,
            onAction: _startNewChat,
          ),
          const SizedBox(height: 8),
          _buildChats(),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onAction,
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildUploadBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Membaca isi "$_uploadLabel"...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSources() {
    return StreamBuilder<List<ProjectSource>>(
      stream: _repository.watchSources(widget.project.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final sources = snapshot.data ?? const <ProjectSource>[];

        if (sources.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Belum ada sumber. Tambahkan file materi (mis. PDF) supaya AI '
              'bisa membacanya saat menjawab di proyek ini.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          );
        }

        return Column(
          children: sources.map(_buildSourceTile).toList(),
        );
      },
    );
  }

  Widget _buildSourceTile(ProjectSource source) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showSourceDetail(source),
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
                    _sourceIcon(source),
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
                        source.name,
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
                        _sourceSubtitle(source),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: source.hasText
                              ? AppColors.textSecondary
                              : Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  onPressed: () => _deleteSource(source),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChats() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _repository.watchProjectChats(widget.project.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final chats = snapshot.data ?? const [];

        if (chats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Belum ada chat di proyek ini. Tekan "Chat Baru" untuk mulai.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          );
        }

        return Column(
          children: chats.map((chat) {
            final title = chat.data()['title'] as String? ?? 'New Chat';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openChat(chat.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
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
          }).toList(),
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
            width: 110,
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _sourceIcon(ProjectSource source) {
    switch (source.type) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'text':
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _sourceSubtitle(ProjectSource source) {
    final size = _formatBytes(source.size);

    if (source.hasText) {
      return '$size · teks ${_formatNumber(source.charCount)} karakter';
    }

    if (source.type == 'image') return '$size · gambar (tidak dibaca)';

    return '$size · tidak bisa dibaca';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatNumber(int value) {
    final text = value.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }

    return buffer.toString();
  }
}

/// Layar sederhana untuk membaca teks hasil ekstraksi sebuah sumber.
class _SourceTextScreen extends StatelessWidget {
  const _SourceTextScreen({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
