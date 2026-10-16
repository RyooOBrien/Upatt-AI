import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/chat_repository.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  static const Color _background = Color(0xFF000000);
  static const Color _surface = Color(0xFF1C1C20);
  static const Color _card = Color(0xFF222225);
  static const Color _muted = Color(0xFFB8B8C0);
  static const Color _accent = Color(0xFF6B46FF);

  late Future<List<Map<String, String>>> _memoryFuture;

  @override
  void initState() {
    super.initState();
    _memoryFuture = _loadMemories();
  }

  Future<List<Map<String, String>>> _loadMemories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final repository = ChatRepository();
    final chats = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chats')
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();

    final memories = <Map<String, String>>[];

    for (final chat in chats.docs) {
      final memory = await repository.getChatMemory(chat.id);
      final summary = (memory['summary'] as String? ?? '').trim();

      if (summary.isNotEmpty) {
        memories.add({
          'chatId': chat.id,
          'title': (chat.data()['title'] as String? ?? '').trim().isEmpty
              ? 'Percakapan tanpa judul'
              : (chat.data()['title'] as String).trim(),
          'summary': summary,
        });
      }
    }

    return memories;
  }

  Future<void> _refresh() async {
    setState(() => _memoryFuture = _loadMemories());
    await _memoryFuture;
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
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Memori percakapan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, String>>>(
          future: _memoryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _accent),
              );
            }

            if (snapshot.hasError) {
              return _StateMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Memori gagal dimuat',
                message: 'Periksa koneksi internet, lalu coba muat ulang.',
                actionLabel: 'Coba lagi',
                onAction: _refresh,
              );
            }

            final memories = snapshot.data ?? [];
            if (memories.isEmpty) {
              return _StateMessage(
                icon: Icons.psychology_outlined,
                title: 'Belum ada memori',
                message:
                    'Upatt akan membuat ringkasan otomatis saat percakapan cukup panjang. Riwayat chat tetap tersimpan seperti biasa.',
                actionLabel: 'Muat ulang',
                onAction: _refresh,
              );
            }

            return RefreshIndicator(
              color: _accent,
              backgroundColor: _card,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF303036)),
                    ),
                    child: const Text(
                      'Ringkasan dari percakapan panjang yang membantu Upatt menjaga konteks. Halaman ini hanya menampilkan memori yang sudah dibuat; riwayat chat tidak dihapus.',
                      style: TextStyle(
                        color: _muted,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Memori tersimpan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${memories.length} ringkasan',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < memories.length; i++) ...[
                    _MemoryCard(
                      title: memories[i]['title']!,
                      summary: memories[i]['summary']!,
                    ),
                    if (i != memories.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.title,
    required this.summary,
  });

  final String title;
  final String summary;

  static const Color _card = Color(0xFF1C1C20);
  static const Color _muted = Color(0xFFB8B8C0);
  static const Color _accent = Color(0xFF6B46FF);

  @override
  Widget build(BuildContext context) {
    final lines = summary.replaceAll('\r\n', '\n').split('\n');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF303036)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF34343A), height: 1),
          const SizedBox(height: 12),
          for (final line in lines) ...[
            _buildLine(line),
          ],
        ],
      ),
    );
  }

  Widget _buildLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return const SizedBox(height: 7);

    final heading = line.startsWith('### ')
        ? line.substring(4).trim()
        : line.startsWith('## ')
            ? line.substring(3).trim()
            : line.startsWith('# ')
                ? line.substring(2).trim()
                : null;

    if (heading != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          heading,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      );
    }

    final isBullet = line.startsWith('- ') ||
        line.startsWith('• ') ||
        RegExp(r'^\d+[\.)]\s').hasMatch(line);
    final content = line.startsWith('- ') || line.startsWith('• ')
        ? line.substring(2).trim()
        : RegExp(r'^\d+[\.)]\s').hasMatch(line)
            ? line.replaceFirst(RegExp(r'^\d+[\.)]\s'), '')
            : line;

    return Padding(
      padding: EdgeInsets.only(
        left: isBullet ? 4 : 0,
        bottom: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBullet) ...[
            const Text('• ', style: TextStyle(color: _accent, height: 1.5)),
            const SizedBox(width: 3),
          ],
          Expanded(
            child: Text(
              content.replaceAll('**', '').replaceAll('`', ''),
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B46FF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: const Color(0xFF9B83FF), size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB8B8C0),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B46FF),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
