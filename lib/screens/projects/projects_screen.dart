import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/project_repository.dart';
import 'project_detail_screen.dart';
import 'project_result.dart';

/// Halaman **Proyek**: daftar proyek untuk mengelompokkan percakapan dan
/// sumber materi. Membuat/mengubah/menghapus proyek dilakukan di sini.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final ProjectRepository _repository = ProjectRepository();

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

  Future<void> _createProject() async {
    final draft = await _promptProject();

    if (draft == null) return;

    try {
      await _repository.createProject(
        name: draft.name,
        description: draft.description,
      );

      _showMessage('Proyek "${draft.name}" dibuat.');
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _renameProject(Project project) async {
    final draft = await _promptProject(existing: project);

    if (draft == null) return;

    try {
      await _repository.updateProject(
        project.id,
        name: draft.name,
        description: draft.description,
      );

      _showMessage('Proyek diperbarui.');
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Hapus proyek?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Proyek "${project.name}" beserta semua sumber dan chat di dalamnya '
          'akan dihapus permanen.',
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
      await _repository.deleteProject(project.id);

      _showMessage('Proyek dihapus.');
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _openProject(Project project) async {
    final result = await Navigator.of(context).push<ProjectResult>(
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(project: project),
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

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
          'Proyek',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Proyek Baru'),
      ),
      body: StreamBuilder<List<Project>>(
        stream: _repository.watchProjects(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildMessage(
              icon: Icons.error_outline_rounded,
              title: 'Gagal memuat proyek',
              subtitle: snapshot.error.toString(),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final projects = snapshot.data ?? const <Project>[];

          if (projects.isEmpty) {
            return _buildMessage(
              icon: Icons.folder_copy_outlined,
              title: 'Belum ada proyek',
              subtitle: 'Buat proyek untuk mengelompokkan percakapan '
                  'berdasarkan topik dan menyimpan sumber materinya.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openProject(project),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.folder_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (project.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    project.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: AppColors.textSecondary,
                            ),
                            color: AppColors.surface,
                            onSelected: (value) {
                              if (value == 'rename') {
                                _renameProject(project);
                              } else if (value == 'delete') {
                                _deleteProject(project);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Ganti nama'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Hapus proyek'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
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
          ],
        ),
      ),
    );
  }

  Future<_ProjectDraft?> _promptProject({Project? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController =
        TextEditingController(text: existing?.description ?? '');

    return showDialog<_ProjectDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          existing == null ? 'Proyek Baru' : 'Ganti Nama Proyek',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final name = nameController.text.trim();

              if (name.isEmpty) return;

              Navigator.of(dialogContext).pop(
                _ProjectDraft(
                  name: name,
                  description: descriptionController.text.trim(),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

class _ProjectDraft {
  _ProjectDraft({required this.name, required this.description});

  final String name;
  final String description;
}
