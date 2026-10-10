
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
      'title': 'New Chat',
      'createdAt': now,
      'updatedAt': now,
    });

    return doc.id;
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
  }) async {
    if (role != 'user' && role != 'assistant') {
      throw ArgumentError('Role pesan tidak valid.');
    }

    final chatRef = _chats.doc(chatId);

    await _db.runTransaction((transaction) async {
      final chatSnapshot = await transaction.get(chatRef);

      if (!chatSnapshot.exists) {
        throw Exception('Sesi chat tidak ditemukan.');
      }

      final messageRef = chatRef.collection('messages').doc();

      transaction.set(messageRef, {
        'role': role,
        'content': content,
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
