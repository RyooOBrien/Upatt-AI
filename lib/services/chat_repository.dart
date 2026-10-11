
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Judul bawaan sebelum sesi punya topik nyata.
  static const String defaultTitle = 'New Chat';

  String get _uid {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Pengguna belum login.');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _chats {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('chats');
  }

  Future<String> createChat() async {
    final now = FieldValue.serverTimestamp();

    final doc = await _chats.add({
      'title': defaultTitle,
      'createdAt': now,
      'updatedAt': now,
    });

    return doc.id;
  }

  /// True bila judul masih bawaan (belum punya topik).
  bool isDefaultTitle(String? title) {
    final value = (title ?? '').trim().toLowerCase();

    return value.isEmpty ||
        value == 'new chat' ||
        value == 'chat baru';
  }

  Future<String?> getChatTitle(String chatId) async {
    final snapshot = await _chats.doc(chatId).get();

    return snapshot.data()?['title'] as String?;
  }

  Future<void> updateChatTitle(
    String chatId,
    String title,
  ) async {
    await _chats.doc(chatId).update({
      'title': title,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveMessage({
    required String chatId,
    required String role,
    required String content,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    if (role != 'user' && role != 'assistant') {
      throw ArgumentError('Role pesan tidak valid.');
    }

    final chatRef = _chats.doc(chatId);

    // Hanya metadata lampiran yang disimpan (isi file tidak ikut).
    // Untuk gambar, thumbnail kecil (base64) ikut disimpan agar lampiran
    // tetap tampil setelah chat dimuat ulang. Bila total thumbnail terlalu
    // besar, thumbnail dibuang supaya dokumen tidak melewati batas Firestore.
    final attachmentMeta = attachments
        .map(
          (attachment) => <String, dynamic>{
            'name': attachment['name'] ?? 'Lampiran',
            'type': attachment['type'] ?? 'file',
            'size': attachment['size'] ?? 0,
            if (attachment['thumb'] is String)
              'thumb': attachment['thumb'],
          },
        )
        .toList();

    const int maxThumbTotalLength = 700000; // ~0.7 MB total base64

    final thumbTotal = attachmentMeta.fold<int>(
      0,
      (total, item) => total + ((item['thumb'] as String?)?.length ?? 0),
    );

    if (thumbTotal > maxThumbTotalLength) {
      for (final item in attachmentMeta) {
        item.remove('thumb');
      }
    }

    await _db.runTransaction((transaction) async {
      final chatSnapshot = await transaction.get(chatRef);

      if (!chatSnapshot.exists) {
        throw Exception('Sesi chat tidak ditemukan.');
      }

      final messageRef = chatRef.collection('messages').doc();

      transaction.set(messageRef, {
        'role': role,
        'content': content,
        'attachments': attachmentMeta,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(chatRef, {
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchChats() {
    return _chats
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String chatId,
  ) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> deleteChat(String chatId) async {
    final chatRef = _chats.doc(chatId);

    final messages = await chatRef.collection('messages').get();

    final batch = _db.batch();

    for (final message in messages.docs) {
      batch.delete(message.reference);
    }

    batch.delete(chatRef);

    await batch.commit();
  }

  
  Future<Map<String, dynamic>> getChatMemory(String chatId) async {
    final snapshot = await _chats.doc(chatId).get();
    final data = snapshot.data();

    return {
      'summary': data?['memorySummary'] as String? ?? '',
      'summarizedCount': (data?['summarizedCount'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> saveChatMemory({
    required String chatId,
    required String summary,
    required int summarizedCount,
  }) async {
    await _chats.doc(chatId).update({
      'memorySummary': summary,
      'summarizedCount': summarizedCount,
      'memoryUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

}
