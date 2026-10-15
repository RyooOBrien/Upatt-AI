import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ai_service.dart';

/// Sebuah **proyek**: wadah untuk mengelompokkan percakapan dan menyimpan
/// sumber materi (mis. PDF matkul) yang dipakai AI sebagai konteks.
class Project {
  Project({
    required this.id,
    required this.name,
    required this.description,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Project.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = (data['name'] as String?)?.trim();

    return Project(
      id: doc.id,
      name: (name == null || name.isEmpty) ? 'Proyek' : name,
      description: (data['description'] as String?)?.trim() ?? '',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }
}

/// Sumber materi di dalam sebuah proyek (mis. PDF, dokumen teks).
///
/// Yang disimpan hanya teks hasil ekstraksi (Firebase Storage tidak dipakai,
/// karena butuh paket berbayar). File aslinya tidak disimpan.
class ProjectSource {
  ProjectSource({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.text,
    this.textTruncated = false,
    this.charCount = 0,
    this.extractError = '',
    this.createdAt,
  });

  final String id;
  final String name;

  /// 'pdf', 'text', 'image', atau 'file'.
  final String type;

  final int size;

  /// Teks hasil ekstraksi (kosong bila file tidak bisa dibaca).
  final String text;

  final bool textTruncated;
  final int charCount;
  final String extractError;
  final DateTime? createdAt;

  bool get hasText => text.trim().isNotEmpty;

  factory ProjectSource.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = (data['name'] as String?)?.trim();

    return ProjectSource(
      id: doc.id,
      name: (name == null || name.isEmpty) ? 'Sumber' : name,
      type: (data['type'] as String?) ?? 'file',
      size: (data['size'] as num?)?.toInt() ?? 0,
      text: (data['text'] as String?) ?? '',
      textTruncated: data['textTruncated'] == true,
      charCount: (data['charCount'] as num?)?.toInt() ?? 0,
      extractError: (data['extractError'] as String?) ?? '',
      createdAt: _asDate(data['createdAt']),
    );
  }
}

/// Repository untuk pengelolaan proyek, sumber materi, dan chat per proyek.
class ProjectRepository {
  /// Batas total teks sumber yang dikirim ke backend (hemat token/payload).
  static const int _contextMaxChars = 60000;

  /// Batas ukuran file sumber yang diproses (agar request ekstraksi tetap
  /// ringan; backend juga membatasi ukuran yang sama).
  static const int sourceMaxBytes = 10 * 1024 * 1024;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Pengguna belum login.');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _projects {
    return _db.collection('users').doc(_uid).collection('projects');
  }

  CollectionReference<Map<String, dynamic>> get _chats {
    return _db.collection('users').doc(_uid).collection('chats');
  }

  // =========================================================
  // PROYEK
  // =========================================================

  Stream<List<Project>> watchProjects() {
    return _projects
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Project.fromDoc).toList());
  }

  Future<String> createProject({
    required String name,
    String description = '',
  }) async {
    final now = FieldValue.serverTimestamp();

    final doc = await _projects.add({
      'name': name.trim(),
      'description': description.trim(),
      'createdAt': now,
      'updatedAt': now,
    });

    return doc.id;
  }

  Future<void> updateProject(
    String projectId, {
    required String name,
    String description = '',
  }) async {
    await _projects.doc(projectId).update({
      'name': name.trim(),
      'description': description.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Hapus proyek beserta semua sumber dan chat di dalamnya.
  Future<void> deleteProject(String projectId) async {
    final projectRef = _projects.doc(projectId);

    final sources = await projectRef.collection('sources').get();

    final chats = await _chats
        .where('projectId', isEqualTo: projectId)
        .get();

    for (final chat in chats.docs) {
      final messages = await chat.reference.collection('messages').get();
      final batch = _db.batch();

      for (final message in messages.docs) {
        batch.delete(message.reference);
      }

      batch.delete(chat.reference);
      await batch.commit();
    }

    final batch = _db.batch();

    for (final source in sources.docs) {
      batch.delete(source.reference);
    }

    batch.delete(projectRef);
    await batch.commit();
  }

  // =========================================================
  // CHAT DALAM PROYEK
  // =========================================================

  /// Chat milik sebuah proyek, terbaru lebih dulu. Diurutkan di sisi klien
  /// agar tidak memerlukan indeks komposit Firestore.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchProjectChats(
    String projectId,
  ) {
    return _chats
        .where('projectId', isEqualTo: projectId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.toList();

      docs.sort((a, b) {
        final at = _asDate(a.data()['updatedAt'])?.millisecondsSinceEpoch ?? 0;
        final bt = _asDate(b.data()['updatedAt'])?.millisecondsSinceEpoch ?? 0;

        return bt.compareTo(at);
      });

      return docs;
    });
  }

  // =========================================================
  // SUMBER MATERI
  // =========================================================

  Stream<List<ProjectSource>> watchSources(String projectId) {
    return _projects
        .doc(projectId)
        .collection('sources')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ProjectSource.fromDoc).toList());
  }

  /// Teks semua sumber proyek (untuk konteks AI). Sumber tanpa teks dilewati.
  /// Total dibatasi [_contextMaxChars] agar payload ke backend tetap ringan
  /// (backend juga memotong konteksnya).
  Future<List<Map<String, String>>> loadSourceTexts(String projectId) async {
    final snapshot = await _projects
        .doc(projectId)
        .collection('sources')
        .orderBy('createdAt')
        .get();

    final result = <Map<String, String>>[];
    int used = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final text = (data['text'] as String?)?.trim() ?? '';

      if (text.isEmpty) continue;

      final remaining = _contextMaxChars - used;

      if (remaining <= 200) break;

      final name = (data['name'] as String?)?.trim();
      final label = (name == null || name.isEmpty) ? 'Sumber' : name;

      final body = text.length > remaining
          ? '${text.substring(0, remaining)}\n…(dipotong)'
          : text;

      result.add({'name': label, 'text': body});
      used += body.length + label.length;
    }

    return result;
  }

  /// Ekstrak teks dari file sumber lalu simpan metadatanya di Firestore.
  /// File asli tidak disimpan (tanpa Firebase Storage).
  Future<ProjectSource> addSource({
    required String projectId,
    required String name,
    required Uint8List bytes,
    String mimeType = '',
  }) async {
    if (bytes.isEmpty) {
      throw Exception('File kosong atau tidak bisa dibaca.');
    }

    if (bytes.length > sourceMaxBytes) {
      throw Exception(
        'Ukuran file melebihi batas ${sourceMaxBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final sourcesRef = _projects.doc(projectId).collection('sources');
    final doc = sourcesRef.doc();

    final contentType =
        mimeType.trim().isNotEmpty ? mimeType.trim() : _mimeFromName(name);

    SourceExtract? extract;
    String extractError = '';

    try {
      extract = await AiService.extractSourceText(
        bytes: bytes,
        name: name,
        mimeType: contentType,
      );
    } catch (error) {
      extractError = error.toString().replaceFirst('Exception: ', '').trim();
    }

    final text = extract?.text ?? '';
    final type = _sourceType(name, contentType, extract?.kind ?? '');

    await doc.set({
      'name': name,
      'type': type,
      'size': bytes.length,
      'text': text,
      'textTruncated': extract?.truncated ?? false,
      'charCount': extract?.charCount ?? text.length,
      if (extractError.isNotEmpty) 'extractError': extractError,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await _projects.doc(projectId).update({
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Abaikan bila proyek sudah tidak ada.
    }

    return ProjectSource(
      id: doc.id,
      name: name,
      type: type,
      size: bytes.length,
      text: text,
      textTruncated: extract?.truncated ?? false,
      charCount: extract?.charCount ?? text.length,
      extractError: extractError,
      createdAt: DateTime.now(),
    );
  }

  Future<void> deleteSource(
    String projectId,
    ProjectSource source,
  ) async {
    await _projects.doc(projectId).collection('sources').doc(source.id).delete();

    try {
      await _projects.doc(projectId).update({
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Abaikan.
    }
  }
}

// =========================================================
// Helper
// =========================================================

DateTime? _asDate(dynamic value) {
  return value is Timestamp ? value.toDate() : null;
}

String _extensionOf(String name) {
  if (!name.contains('.')) return '';

  final extension = name.split('.').last.trim().toLowerCase();

  if (extension.isEmpty || extension.length > 8 || extension.contains(' ')) {
    return '';
  }

  return extension;
}

const Map<String, String> _mimeByExtension = {
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'text': 'text/plain',
  'md': 'text/markdown',
  'markdown': 'text/markdown',
  'csv': 'text/csv',
  'tsv': 'text/tab-separated-values',
  'json': 'application/json',
  'xml': 'application/xml',
  'html': 'text/html',
  'htm': 'text/html',
  'log': 'text/plain',
  'yaml': 'text/yaml',
  'yml': 'text/yaml',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx':
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

String _mimeFromName(String name) => _mimeByExtension[_extensionOf(name)] ?? '';

const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
};

String _sourceType(String name, String mimeType, String kind) {
  if (kind == 'pdf') return 'pdf';
  if (kind == 'text') return 'text';

  final extension = _extensionOf(name);

  if (mimeType.startsWith('image/') || _imageExtensions.contains(extension)) {
    return 'image';
  }

  if (extension == 'pdf') return 'pdf';

  if (kind == 'binary' && extension.isEmpty) return 'file';

  return 'file';
}
