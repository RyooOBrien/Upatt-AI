/// Hasil yang dibawa kembali dari layar Proyek ke layar utama (chat).
///
/// Berisi proyek yang dipilih. [chatId] diisi bila pengguna membuka chat
/// tertentu; bila null, layar utama akan mulai chat baru di proyek itu.
class ProjectResult {
  ProjectResult({
    required this.projectId,
    required this.projectName,
    this.chatId,
  });

  final String projectId;
  final String projectName;
  final String? chatId;
}
