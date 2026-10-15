import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:url_launcher/url_launcher.dart';


import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/ai_service.dart';
import '../../services/app_settings.dart';
import '../../services/chat_repository.dart';
import '../../services/attachment_picker_service.dart';
import '../../services/project_repository.dart';
import '../camera/camera_capture_screen.dart';
import '../image/image_gen_screen.dart';
import '../image/image_viewer_screen.dart';
import '../library/library_screen.dart';
import '../projects/project_result.dart';
import '../projects/projects_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // =========================================================
  // CONTROLLERS
  // =========================================================

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  final ChatRepository _chatRepository = ChatRepository();
  final ProjectRepository _projectRepository = ProjectRepository();

  // Proyek yang sedang aktif. Bila null, pengguna berada di chat umum
  // (di luar proyek) sehingga riwayat tidak bercampur.
  String? _activeProjectId;
  String _activeProjectName = '';

  // Teks sumber proyek aktif, dipakai sebagai konteks jawaban AI.
  List<Map<String, String>> _projectSources = const [];
  bool _projectSourcesLoading = false;

  String? _currentChatId;
  Offset _lastChatPointerPosition = Offset.zero;

  // =========================================================
  // BATAS & MEMORI
  // =========================================================

  // Batas maksimal riwayat yang dikirim ke backend AI.
  // Backend menolak request dengan lebih dari 20 pesan riwayat.
  static const int _maxHistoryMessages = 20;

  // Ambang jumlah pesan baru sebelum memori diringkas.
  static const int _memoryTriggerMessages = 12;

  // Jumlah pesan terbaru yang tetap dikirim mentah (tidak diringkas).
  static const int _memoryKeepRecentMessages = 6;

  // =========================================================
  // STATE
  // =========================================================

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _selectedAttachments = [];

  String _memorySummary = '';
  int _summarizedCount = 0;

  bool _hasText = false;

  // Speech-to-text: hasil ucapan langsung masuk ke kolom pesan.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;
  bool _isListening = false;
  String _voiceBaseText = '';
  bool _showAttachmentMenu = false;
  bool _isTyping = false;
  bool _showHistorySidebar = false;
  String _historySearchQuery = '';

  // True saat sebuah sesi baru dibuat dan belum punya judul topik.
  bool _chatTitlePending = false;

  // Mode pesan sementara: percakapan tidak disimpan ke riwayat.
  bool _isTemporaryChat = false;

  // Snapshot chat normal agar bisa dipulihkan saat keluar dari mode sementara.
  List<Map<String, dynamic>>? _temporaryPreviousMessages;
  String? _temporaryPreviousChatId;
  String _temporaryPreviousMemorySummary = '';
  int _temporaryPreviousSummarizedCount = 0;

  void _clearTemporarySnapshot() {
    _temporaryPreviousMessages = null;
    _temporaryPreviousChatId = null;
    _temporaryPreviousMemorySummary = '';
    _temporaryPreviousSummarizedCount = 0;
  }

  // Menandai request AI yang sedang aktif. Nilai ini berubah saat pengguna
  // membuka chat lain / memulai chat baru sehingga respons lama dibatalkan.
  int _activeRequestId = 0;

  // Apakah daftar pesan sedang menempel (auto-scroll) di bagian bawah.
  bool _stickToBottom = true;

  // =========================================================
  // COLORS
  // =========================================================

  static const Color _background = Color(0xFF050505);
  static const Color _surface = Color(0xFF151518);
  static const Color _surfaceLight = Color(0xFF1D1D21);
  static const Color _border = Color(0xFF2A2A2F);

  // =========================================================
  // INIT & DISPOSE
  // =========================================================

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _stickToBottom =
        position.maxScrollExtent - position.pixels < 80;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (_isListening) {
      _speech.stop();
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

      Future<void> _sendMessage() async {
        final message = _messageController.text.trim();
        final attachments =
            List<Map<String, dynamic>>.from(_selectedAttachments);

        if ((message.isEmpty && attachments.isEmpty) || _isTyping) return;

        FocusScope.of(context).unfocus();

        final requestId = ++_activeRequestId;
        final isTemporary = _isTemporaryChat;

        setState(() {
          _messages.add({
            'sender': 'user',
            'message': message,
            if (attachments.isNotEmpty) 'attachments': attachments,
          });

          _selectedAttachments.clear();
          _messageController.clear();
          _hasText = false;
          _showAttachmentMenu = false;
          _isTyping = true;
        });

        _scrollToBottom();

        try {
          // Chat biasa disimpan; chat sementara tidak.
          String? chatId;

          if (!isTemporary) {
            await _ensureChatExists();

            if (!mounted || requestId != _activeRequestId) return;

            chatId = _currentChatId!;

            await _chatRepository.saveMessage(
              chatId: chatId,
              role: 'user',
              content: message,
              attachments: attachments,
            );

            if (!mounted || requestId != _activeRequestId) return;
          }

          // Siapkan riwayat percakapan untuk konteks AI.
          final start = _summarizedCount.clamp(
            0,
            _messages.length - 1,
          );

          final pendingHistory = _messages.sublist(
            start,
            _messages.length - 1,
          );

          final history = pendingHistory.length > _maxHistoryMessages
              ? pendingHistory.sublist(
                  pendingHistory.length - _maxHistoryMessages,
                )
              : pendingHistory;

          final historyPayload = history
              .map((item) => <String, String>{
                    'role': item['sender'] == 'upatt'
                        ? 'assistant'
                        : 'user',
                    'content': item['message'] ?? '',
                  })
              .toList();

          // Kirim pesan ke AI dengan streaming. Gambar dikirim sebagai
          // data URL (base64) agar AI bisa benar-benar "melihat" lampiran.
          final reply = await _requestAiReply(
            message: _composeMessageForAi(message, attachments),
            history: historyPayload,
            images: _buildImageDataUrls(attachments),
            sources: _projectSources,
            requestId: requestId,
          );

          if (!mounted || requestId != _activeRequestId) return;

          // Simpan jawaban AI hanya untuk chat biasa.
          if (!isTemporary && chatId != null) {
            await _chatRepository.saveMessage(
              chatId: chatId,
              role: 'assistant',
              content: reply,
            );

            if (!mounted || requestId != _activeRequestId) return;

            // Beri judul sesi yang merangkum topik utama percakapan
            // (bukan sekadar menyalin pesan pertama pengguna).
            if (_chatTitlePending) {
              await _applyChatTitle(chatId);
            }

            if (!mounted || requestId != _activeRequestId) return;

            // Perbarui memori hanya untuk chat yang tersimpan.
            await _updateMemory(chatId);
          }
        } catch (error, stackTrace) {
          debugPrint('Upatt chat error: $error');
          debugPrintStack(stackTrace: stackTrace);

          if (!mounted || requestId != _activeRequestId) return;

          final errorText = error
              .toString()
              .replaceFirst('Exception: ', '');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorText.isEmpty
                    ? 'Gagal mengirim pesan.'
                    : errorText,
              ),
            ),
          );
        } finally {
          if (mounted && requestId == _activeRequestId) {
            setState(() {
              _isTyping = false;
            });

            _scrollToBottom();
          }
        }
      }


  // =========================================================
  // STREAMING REPLY
  // =========================================================

  // Menjalankan permintaan ke AI dan menampilkan jawaban secara bertahap.
  // Mengembalikan teks jawaban lengkap.
  Future<String> _requestAiReply({
    required String message,
    required List<Map<String, String>> history,
    required int requestId,
    List<String> images = const [],
    List<Map<String, String>> sources = const [],
  }) async {
    final buffer = StringBuffer();

    var added = false;
    var lastPaint = 0;

    void flush({bool force = false}) {
      if (!mounted || requestId != _activeRequestId) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      // Batasi frekuensi rebuild agar tetap mulus saat teks mengalir.
      if (!force && added && now - lastPaint < 80) return;

      lastPaint = now;

      setState(() {
        if (!added) {
          added = true;
          _isTyping = false;

          _messages.add({
            'sender': 'upatt',
            'message': buffer.toString(),
          });
        } else {
          _messages[_messages.length - 1] = {
            'sender': 'upatt',
            'message': buffer.toString(),
          };
        }
      });

      _autoScroll();
    }

    try {
      await for (final delta in AiService.sendMessageStream(
        message: message,
        memorySummary: _memorySummary,
        history: history,
        images: images,
        sources: sources,
      )) {
        if (!mounted || requestId != _activeRequestId) break;

        buffer.write(delta);
        flush();
      }
    } catch (error) {
      // Bila streaming gagal sebelum ada isi, coba jalur non-streaming.
      if (buffer.isEmpty) {
        final reply = await AiService.sendMessage(
          message: message,
          memorySummary: _memorySummary,
          history: history,
          images: images,
          sources: sources,
        );

        buffer.write(reply);
        flush(force: true);

        return buffer.toString();
      }

      rethrow;
    }

    if (buffer.toString().trim().isEmpty) {
      throw Exception('AI tidak memberikan respons.');
    }

    flush(force: true);

    return buffer.toString();
  }


  // =========================================================
  // AUTO SCROLL
  // =========================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // Auto-scroll ringan saat streaming: hanya bila pengguna ada di bawah,
  // sehingga tidak mengganggu saat pengguna sedang membaca ke atas.
  void _autoScroll() {
    if (!_stickToBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  // =========================================================
  // NEW CHAT
  // =========================================================

  void _newChat() {
    _activeRequestId++;
    _clearTemporarySnapshot();

    setState(() {
      _messages.clear();
      _currentChatId = null;
      _memorySummary = '';
      _summarizedCount = 0;
      _isTyping = false;
      _showAttachmentMenu = false;
      _stickToBottom = true;
      _isTemporaryChat = false;
      _chatTitlePending = false;
      _hasText = false;
      _selectedAttachments.clear();
      _messageController.clear();
    });
  }

  // =========================================================
  // PROYEK
  // =========================================================

  Future<void> _openProjects() async {
    setState(() => _showHistorySidebar = false);

    final result = await Navigator.of(context).push<ProjectResult>(
      MaterialPageRoute(builder: (_) => const ProjectsScreen()),
    );

    if (result == null || !mounted) return;

    await _enterProject(result.projectId, result.projectName);

    if (result.chatId != null && mounted) {
      await _openChat(result.chatId!);
    }

    if (mounted) {
      setState(() => _showHistorySidebar = false);
    }
  }

  Future<void> _enterProject(String projectId, String name) async {
    setState(() {
      _activeProjectId = projectId;
      _activeProjectName = name;
      _messageController.clear();
      _hasText = false;
    });

    _newChat();

    await _loadProjectSources(projectId);
  }

  Future<void> _loadProjectSources(String projectId) async {
    if (mounted) {
      setState(() => _projectSourcesLoading = true);
    }

    try {
      final sources = await _projectRepository.loadSourceTexts(projectId);

      if (!mounted || _activeProjectId != projectId) return;

      setState(() {
        _projectSources = sources;
        _projectSourcesLoading = false;
      });
    } catch (error) {
      debugPrint('Gagal memuat sumber proyek: $error');

      if (!mounted || _activeProjectId != projectId) return;

      setState(() {
        _projectSources = const [];
        _projectSourcesLoading = false;
      });
    }
  }

  void _exitProject() {
    setState(() {
      _activeProjectId = null;
      _activeProjectName = '';
      _projectSources = const [];
      _projectSourcesLoading = false;
      _showHistorySidebar = false;
    });

    _newChat();
  }

  // Tombol header berfungsi sebagai toggle masuk/keluar dari pesan sementara.
  void _startTemporaryChat() {
    _activeRequestId++;

    if (_isTemporaryChat) {
      final previousMessages = _temporaryPreviousMessages;
      final previousChatId = _temporaryPreviousChatId;
      final previousMemorySummary = _temporaryPreviousMemorySummary;
      final previousSummarizedCount = _temporaryPreviousSummarizedCount;

      setState(() {
        _isTemporaryChat = false;
        _messages
          ..clear()
          ..addAll(previousMessages ?? const <Map<String, dynamic>>[]);
        _currentChatId = previousChatId;
        _memorySummary = previousMemorySummary;
        _summarizedCount = previousSummarizedCount;
        _isTyping = false;
        _chatTitlePending = false;
        _hasText = false;
        _showAttachmentMenu = false;
        _showHistorySidebar = false;
        _stickToBottom = true;
        _selectedAttachments.clear();
        _messageController.clear();
        _clearTemporarySnapshot();
      });

      _scrollToBottom();
      return;
    }

    // Simpan chat normal sebelum beralih ke sesi sementara.
    _temporaryPreviousMessages = _messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    _temporaryPreviousChatId = _currentChatId;
    _temporaryPreviousMemorySummary = _memorySummary;
    _temporaryPreviousSummarizedCount = _summarizedCount;

    setState(() {
      _isTemporaryChat = true;
      _messages.clear();
      _currentChatId = null;
      _memorySummary = '';
      _summarizedCount = 0;
      _isTyping = false;
      _chatTitlePending = false;
      _hasText = false;
      _showAttachmentMenu = false;
      _showHistorySidebar = false;
      _stickToBottom = true;
      _selectedAttachments.clear();
      _messageController.clear();
    });

    _scrollToBottom();

  }

  // =========================================================
  // OPEN CHAT
  // =========================================================

  
  Future<void> _openChat(String chatId) async {
    _activeRequestId++;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt')
          .get();

      final memory = await _chatRepository.getChatMemory(chatId);
      final currentTitle = await _chatRepository.getChatTitle(chatId);

      if (!mounted) return;

      _clearTemporarySnapshot();

      setState(() {
        _currentChatId = chatId;
        _isTemporaryChat = false;
        _chatTitlePending = false;
        _messages
          ..clear()
          ..addAll(
            snapshot.docs.map((doc) {
              final data = doc.data();

              return <String, dynamic>{
                'sender': data['role'] == 'assistant'
                    ? 'upatt'
                    : 'user',
                'message': data['content'] as String? ?? '',
                if (data['attachments'] is List)
                  'attachments': _restoreAttachments(data['attachments']),
              };
            }),
          );

        _memorySummary = memory['summary'] as String? ?? '';

        final summarized =
            (memory['summarizedCount'] as num?)?.toInt() ?? 0;

        _summarizedCount = summarized.clamp(
          0,
          _messages.length,
        );

        _isTyping = false;
        _showAttachmentMenu = false;
        _stickToBottom = true;
        _selectedAttachments.clear();
      });

      _scrollToBottom();

      // Perbaiki judul lama yang masih bawaan ("New Chat") agar menjadi
      // ringkasan topik percakapan.
      if (_chatRepository.isDefaultTitle(currentTitle) &&
          _messages.isNotEmpty) {
        await _applyChatTitle(chatId);
      }
    } catch (error) {
      debugPrint('Gagal membuka chat: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal memuat riwayat chat.'),
        ),
      );
    }
  }


  // =========================================================
  // Riwayat Chat ?
  // =========================================================

  Future<void> _ensureChatExists() async {
    if (_currentChatId != null) return;

    final chatId = await _chatRepository.createChat(
      projectId: _activeProjectId,
    );

    if (!mounted) return;

    setState(() {
      _currentChatId = chatId;
      // Sesi baru: judul topik diisi setelah ada balasan AI.
      _chatTitlePending = true;
    });
  }

  // =========================================================
  // UPDATE MEMORY
  // =========================================================

  Future<void> _updateMemory(String chatId) async {
    final pending = _messages.length - _summarizedCount;

    if (pending <= _memoryTriggerMessages) return;

    var end = _messages.length - _memoryKeepRecentMessages;

    // Backend membatasi maksimal 100 pesan per ringkasan.
    if (end - _summarizedCount > 100) {
      end = _summarizedCount + 100;
    }

    if (end <= _summarizedCount) return;

    final messagesToSummarize = _messages
        .sublist(_summarizedCount, end)
        .map((item) => <String, String>{
              'role': item['sender'] == 'upatt'
                  ? 'assistant'
                  : 'user',
              'content': item['message'] ?? '',
            })
        .toList();

    if (messagesToSummarize.isEmpty) return;

    try {
      final summary = await AiService.summarizeMessages(
        previousSummary: _memorySummary,
        messages: messagesToSummarize,
      );

      await _chatRepository.saveChatMemory(
        chatId: chatId,
        summary: summary,
        summarizedCount: end,
      );

      if (!mounted) return;

      setState(() {
        _memorySummary = summary;
        _summarizedCount = end;
      });
    } catch (error) {
      debugPrint('Upatt memory error: $error');
    }
  }

  // =========================================================
  // JUDUL SESI
  // =========================================================

  // Isi judul sesi dari topik utama percakapan.
  //
  // Judul lokal (dari pesan pertama) disimpan lebih dulu sebagai cadangan,
  // lalu diperbarui dengan judul hasil AI yang merangkum topik sesi.
  Future<void> _applyChatTitle(String chatId) async {
    _chatTitlePending = false;

    final conversation = _messages
        .map((item) => <String, String>{
              'role': item['sender'] == 'upatt' ? 'assistant' : 'user',
              'content': (item['message'] as String? ?? '').trim(),
            })
        .where((item) => item['content']!.isNotEmpty)
        .take(6)
        .toList();

    if (conversation.isEmpty) return;

    final fallback = _fallbackTitle(conversation.first['content'] ?? '');

    if (fallback.isNotEmpty) {
      try {
        await _chatRepository.updateChatTitle(chatId, fallback);
      } catch (error) {
        debugPrint('Upatt title fallback error: $error');
      }
    }

    try {
      final title = await AiService.generateTitle(messages: conversation);

      if (title.isEmpty || title == fallback) return;

      await _chatRepository.updateChatTitle(chatId, title);
    } catch (error) {
      debugPrint('Upatt title error: $error');
    }
  }

  // Judul cadangan sederhana dari pesan pengguna bila AI tidak tersedia.
  String _fallbackTitle(String text) {
    var title = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[#*`_>\[\]()~]'), '')
        .trim();

    if (title.isEmpty) return '';

    const maxLength = 48;

    if (title.length > maxLength) {
      title = '${title.substring(0, maxLength).trim()}...';
    }

    return title;
  }

  // =========================================================
  // toggle sidebaer
  // =========================================================  

  void _toggleHistorySidebar() {
    setState(() {
      _showHistorySidebar = !_showHistorySidebar;
    });
  }

  // =========================================================
  // PANEL CHAT 2
  // =========================================================  

  
Future<void> _showBackendUrlDialog() async {
  final controller = TextEditingController(text: AiService.baseUrl);

  final saved = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF171719),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Alamat server AI',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saat debugging di HP fisik, 10.0.2.2 tidak berlaku. '
                'Isi alamat LAN komputer yang menjalankan backend, '
                'misal http://192.168.1.20:3000. Kosongkan untuk '
                'kembali ke default.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.20:3000',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF101012),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Batal',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  );

  if (saved != true) {
    controller.dispose();
    return;
  }

  await AppSettings.saveApiBaseUrl(controller.text);

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Server aktif: ${AiService.baseUrl}'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

Future<void> _showChatSearchDialog() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final chatsStream = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('chats')
              .orderBy('updatedAt', descending: true)
              .snapshots();

          return Dialog(
            backgroundColor: const Color(0xFF171719),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: SizedBox(
              width: 520,
              height: MediaQuery.of(context).size.height * 0.68,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cari percakapan',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value.trim().toLowerCase()),
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: 'Cari chat',
                        hintStyle: const TextStyle(color: Color(0xFF8F8F98)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9A9AA3)),
                        filled: true,
                        fillColor: const Color(0xFF242428),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF38383F))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('RIWAYAT CHAT', style: TextStyle(color: Color(0xFF85858F), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: chatsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return const Center(child: Text('Gagal memuat riwayat.', style: TextStyle(color: Colors.white70)));
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          final docs = (snapshot.data?.docs ?? []).where((doc) {
                            final projectId = doc.data()['projectId'] as String?;
                            final inProject =
                                projectId != null && projectId.isNotEmpty;

                            if (_activeProjectId == null) {
                              if (inProject) return false;
                            } else if (projectId != _activeProjectId) {
                              return false;
                            }

                            final title = (doc.data()['title'] as String? ?? 'New Chat').toLowerCase();
                            return query.isEmpty || title.contains(query);
                          }).toList();
                          if (docs.isEmpty) return Center(child: Text(query.isEmpty ? 'Belum ada percakapan.' : 'Tidak ada chat yang cocok.', style: const TextStyle(color: Colors.white54)));
                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final title = doc.data()['title'] as String? ?? 'New Chat';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                onTap: () async {
                                  Navigator.of(dialogContext).pop();
                                  await _openChat(doc.id);
                                  if (mounted) setState(() => _showHistorySidebar = false);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  controller.dispose();
}

Future<void> _showChatActions(String chatId, String currentTitle) async {
  final screenSize = MediaQuery.of(context).size;
  final position = _lastChatPointerPosition == Offset.zero
      ? Offset(screenSize.width * 0.55, screenSize.height * 0.5)
      : _lastChatPointerPosition;

  final action = await showMenu<String>(
    context: context,
    color: const Color(0xFF303033),
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    ),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
    position: RelativeRect.fromLTRB(
      position.dx.clamp(8.0, screenSize.width - 240),
      position.dy.clamp(8.0, screenSize.height - 180),
      (screenSize.width - position.dx).clamp(8.0, screenSize.width),
      (screenSize.height - position.dy).clamp(8.0, screenSize.height),
    ),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        height: 48,
        child: Text(
          currentTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'rename',
        height: 48,
        child: const Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded,
                color: Colors.white70, size: 21),
            SizedBox(width: 12),
            Text('Ganti nama', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        height: 48,
        child: const Row(
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Color(0xFFFF6B75), size: 21),
            SizedBox(width: 12),
            Text(
              'Hapus',
              style: TextStyle(
                color: Color(0xFFFF6B75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  if (!mounted || action == null) return;

  if (action == 'rename') {
    await _renameChat(chatId, currentTitle);
  } else if (action == 'delete') {
    await _confirmDeleteChat(chatId, currentTitle);
  }
}

Future<void> _renameChat(String chatId, String currentTitle) async {
  final controller = TextEditingController(text: currentTitle);
  final newTitle = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF202024),
      title: const Text('Ganti nama obrolan',
          style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Nama obrolan',
          hintStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary),
          ),
        ),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  controller.dispose();

  if (!mounted || newTitle == null) return;
  final trimmedTitle = newTitle.trim();
  if (trimmedTitle.isEmpty || trimmedTitle == currentTitle) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chats')
        .doc(chatId)
        .update({
      'title': trimmedTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nama obrolan berhasil diubah.')),
    );
  } catch (error) {
    debugPrint('Gagal mengganti nama chat: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gagal mengganti nama obrolan.')),
    );
  }
}

Future<void> _confirmDeleteChat(String chatId, String title) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF202024),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.white10),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      title: const Text(
        'Hapus riwayat?',
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        'Percakapan "$title" beserta semua pesannya akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.',
        style: const TextStyle(
          color: Color(0xFFB9B9C2),
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFD0D0D8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5485D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(
            'Hapus',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  if (shouldDelete != true || !mounted) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final chatRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('chats')
      .doc(chatId);

  try {
    // Firestore tidak menghapus subcollection otomatis saat dokumen induk
    // dihapus, jadi hapus pesan dalam batch sebelum menghapus sesi chat.
    while (true) {
      final messages = await chatRef
          .collection('messages')
          .limit(400)
          .get();
      if (messages.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final message in messages.docs) {
        batch.delete(message.reference);
      }
      await batch.commit();
    }

    await chatRef.delete();

    // Jika yang dihapus adalah sesi yang sedang terbuka, kosongkan tampilan
    // agar pesan lama tidak tersimpan di layar atau terkirim ke sesi baru.
    if (_currentChatId == chatId) {
      _activeRequestId++;
      setState(() {
        _messages.clear();
        _currentChatId = null;
        _memorySummary = '';
        _summarizedCount = 0;
        _isTyping = false;
        _chatTitlePending = false;
        _selectedAttachments.clear();
        _messageController.clear();
        _hasText = false;
        _showAttachmentMenu = false;
        _isTemporaryChat = false;
        _stickToBottom = true;
        _clearTemporarySnapshot();
      });
    }

    if (!mounted) return;
    _showHistoryNotice(
      'Obrolan berhasil dihapus',
      isError: false,
    );
  } catch (error) {
    debugPrint('Gagal menghapus riwayat chat: $error');
    if (!mounted) return;
    _showHistoryNotice(
      'Gagal menghapus riwayat. Coba lagi.',
      isError: true,
    );
  }
}

void _showHistoryNotice(String message, {required bool isError}) {
  if (!mounted) return;

  // Gunakan root Overlay agar notifikasi berada di lapisan paling atas,
  // termasuk ketika sidebar riwayat sedang terbuka.
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF25252B),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isError
                        ? const Color(0x66FF6475)
                        : const Color(0x665BDBA8),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: isError
                          ? const Color(0xFFFF6878)
                          : const Color(0xFF62D6A5),
                      size: 21,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

Widget _buildSidebarFeatureItem({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFE4E4E8), size: 22),
            const SizedBox(width: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE4E4E8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildHistorySidebar() {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return const SizedBox.shrink();
  }

  final chatsStream = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('chats')
      .orderBy('updatedAt', descending: true)
      .snapshots();

  return Container(
    width: 280,
    color: const Color(0xFF101012),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Upatt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Alamat server',
                  onPressed: _showBackendUrlDialog,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white70,
                  ),
                ),
                IconButton(
                  tooltip: 'Cari percakapan',
                  onPressed: _showChatSearchDialog,
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Menu utama sidebar. Tombol New Chat di bagian atas sengaja
          // dihilangkan karena aksi membuat obrolan sudah tersedia di bawah.
          const SizedBox(height: 4),
          _buildSidebarFeatureItem(
            icon: Icons.image_outlined,
            title: 'Buat Gambar',
            onTap: () {
              setState(() => _showHistorySidebar = false);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ImageGenScreen(),
                ),
              );
            },
          ),
          _buildSidebarFeatureItem(
            icon: Icons.auto_stories_outlined,
            title: 'Pustaka',
            onTap: () async {
              setState(() => _showHistorySidebar = false);

              // Pustaka bisa mengembalikan ID percakapan bila pengguna
              // memilih "Buka chat" pada sebuah lampiran.
              final chatId = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => const LibraryScreen(),
                ),
              );

              if (chatId != null && mounted) {
                await _openChat(chatId);
              }
            },
          ),
          _buildSidebarFeatureItem(
            icon: Icons.folder_outlined,
            title: 'Proyek',
            onTap: _openProjects,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _activeProjectId == null
                        ? 'RECENT CHATS'
                        : 'PROYEK: ${_activeProjectName.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF85858F),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (_activeProjectId != null)
                  TextButton(
                    onPressed: _exitProject,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Keluar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<
                QuerySnapshot<Map<String, dynamic>>>(
              stream: chatsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Gagal memuat riwayat.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final allChats = snapshot.data?.docs ?? [];
                final chats = allChats.where((chat) {
                  final projectId = chat.data()['projectId'] as String?;
                  final inProject =
                      projectId != null && projectId.isNotEmpty;

                  // Pisahkan chat umum dengan chat di dalam proyek agar
                  // riwayat tidak bercampur.
                  if (_activeProjectId == null) {
                    if (inProject) return false;
                  } else if (projectId != _activeProjectId) {
                    return false;
                  }

                  if (_historySearchQuery.isEmpty) return true;

                  final title = (chat.data()['title'] as String? ?? 'New Chat')
                      .toLowerCase();

                  return title.contains(_historySearchQuery);
                }).toList();

                if (chats.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _historySearchQuery.isEmpty
                          ? (_activeProjectId == null
                              ? 'Belum ada percakapan.'
                              : 'Belum ada chat di proyek ini.')
                          : 'Tidak ada chat yang cocok.',
                      style: const TextStyle(
                        color: Colors.white54,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final data = chat.data();
                    final title =
                        data['title'] as String? ?? 'New Chat';
                    final isActive = chat.id == _currentChatId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTapDown: (details) {
                          _lastChatPointerPosition = details.globalPosition;
                        },
                        onLongPress: () => _showChatActions(chat.id, title),
                        onTap: () async {
                          await _openChat(chat.id);

                          if (mounted) {
                            setState(() {
                              _showHistorySidebar = false;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF242428)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(color: Color(0xFF2A2A2F)),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _newChat();
                        setState(() => _showHistorySidebar = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text(
                        'Obrolan',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  tooltip: 'Akun',
                  color: _surfaceLight,
                  onSelected: (value) {
                    if (value == 'logout') _logout();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          const Icon(Icons.logout_rounded, color: Colors.white70, size: 19),
                          const SizedBox(width: 10),
                          Text(
                            'Logout',
                            style: AppTextStyles.body.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00A86B),
                      border: Border.all(color: const Color(0xFF414148), width: 3),
                    ),
                    child: Text(
                      ((user.displayName?.trim().isNotEmpty == true)
                              ? user.displayName!.trim()
                              : (user.email?.trim().isNotEmpty == true
                                  ? user.email!.trim()
                                  : 'U'))
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}



  // =========================================================
  // LOGOUT
  // =========================================================

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    // Navigasi ke LoginScreen ditangani otomatis oleh AuthGate.
  }

  // =========================================================
  // ATTACHMENT MENU
  // =========================================================

  void _toggleAttachmentMenu() {
      FocusScope.of(context).unfocus();

      setState(() {
        _showAttachmentMenu = !_showAttachmentMenu;
      });
    }

    Future<void> _selectAttachment(String type) async {
    setState(() {
      _showAttachmentMenu = false;
    });

    try {
      // Kamera memakai layar kamera in-app (paket `camera`) agar benar-benar
      // membuka kamera di Android, iOS, dan web.
      final picked = type == 'Camera'
          ? await _captureWithCamera()
          : await AttachmentPickerService.pick(type);

      if (!mounted || picked.isEmpty) return;

      setState(() {
        _selectedAttachments.addAll(picked);
      });
    } catch (error, stackTrace) {
      debugPrint('Attachment picker error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // Buka layar kamera in-app dan kembalikan lampirannya (bila ada).
  Future<List<Map<String, dynamic>>> _captureWithCamera() async {
    final captured = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const CameraCaptureScreen(),
      ),
    );

    if (captured == null) return const [];

    // Buat thumbnail agar lampiran tetap tampil setelah chat dimuat ulang.
    final bytes = captured['bytes'];

    if (bytes is Uint8List && bytes.isNotEmpty) {
      captured['thumb'] = await AttachmentPickerService.encodeThumbnail(bytes);
    }

    return [captured];
  }

  
  void _removeAttachment(int index) {
    setState(() {
      if (index >= 0 && index < _selectedAttachments.length) {
        _selectedAttachments.removeAt(index);
      }

      _hasText = _messageController.text.trim().isNotEmpty;
    });
  }

  // Beri tahu AI tentang lampiran yang disertakan pengguna.
  String _composeMessageForAi(
    String message,
    List<Map<String, dynamic>> attachments,
  ) {
    if (attachments.isEmpty) return message;

    final names = attachments
        .map((attachment) => attachment['name'] ?? 'lampiran')
        .join(', ');

    final note = 'Lampiran dari pengguna: $names';

    return message.isEmpty ? note : '$message\n\n[$note]';
  }

  // Ubah lampiran gambar menjadi data URL base64 untuk dikirim ke AI
  // (multimodal). Maksimal 4 gambar, sesuai batas backend.
  List<String> _buildImageDataUrls(
    List<Map<String, dynamic>> attachments,
  ) {
    const maxImages = 4;
    const maxBytes = 2 * 1024 * 1024;

    final images = <String>[];

    for (final attachment in attachments) {
      if (images.length >= maxImages) break;

      if (attachment['type'] != 'image') continue;

      final bytes = attachment['bytes'];

      if (bytes is! Uint8List || bytes.isEmpty) continue;

      var payload = bytes;
      var mime = _mimeTypeForName(attachment['name'] as String? ?? '');

      // Gambar terlalu besar: pakai thumbnail (PNG) agar request ringan.
      if (payload.length > maxBytes) {
        final thumb = attachment['thumb'];

        if (thumb is! String || thumb.isEmpty) continue;

        try {
          payload = base64Decode(thumb);
        } catch (_) {
          continue;
        }

        mime = 'image/png';
      }

      images.add('data:$mime;base64,${base64Encode(payload)}');
    }

    return images;
  }

  String _mimeTypeForName(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';

    switch (extension) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  
  Widget _buildSelectedAttachments() {
    if (_selectedAttachments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_selectedAttachments.length, (index) {
          final attachment = _selectedAttachments[index];
          final name = attachment['name'] as String? ?? 'Lampiran';
          final isImage = attachment['type'] == 'image';
          final bytes = attachment['bytes'];

          return Container(
            width: 180,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                if (isImage && bytes is Uint8List)
                  GestureDetector(
                    onTap: () => _openImageViewer(bytes, name),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        bytes,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    color: Color(0xFF9A9AA3),
                    size: 30,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _removeAttachment(index),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }


  // =========================================================
  // VOICE: SPEECH TO TEXT
  // =========================================================

  Future<void> _startVoiceInput() async {
    // Ketuk mikrofon lagi untuk menghentikan perekaman.
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    try {
      if (!_speechInitialized) {
        final available = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            final listening = status == 'listening';
            if (_isListening != listening) {
              setState(() => _isListening = listening);
            }
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    'Voice input gagal: ${error.errorMsg}',
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
          },
        );

        if (!mounted) return;
        _speechInitialized = available;

        if (!available) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Speech recognition tidak tersedia. Periksa izin mikrofon dan dukungan perangkat.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      // Pertahankan teks yang sudah diketik; ucapan akan ditambahkan setelahnya.
      _voiceBaseText = _messageController.text.trim();
      if (_voiceBaseText.isNotEmpty) {
        _voiceBaseText = '$_voiceBaseText ';
      }

      setState(() {
        _isListening = true;
        _showAttachmentMenu = false;
      });

      await _speech.listen(
        localeId: 'id_ID',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
        onResult: (result) {
          if (!mounted) return;

          final recognizedText = result.recognizedWords.trim();
          final fullText = '$_voiceBaseText$recognizedText';

          _messageController.value = TextEditingValue(
            text: fullText,
            selection: TextSelection.collapsed(offset: fullText.length),
          );

          setState(() {
            _hasText = fullText.trim().isNotEmpty;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tidak bisa memulai voice input: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
    Widget _buildHeaderButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF292929),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF444444),
            width: 1,
          ),
        ),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            color: Colors.white,
            size: 23,
          ),
        ),
      );
    }


  // =========================================================
  // BUILD
  // =========================================================

  // Bar tipis di atas area chat saat berada di dalam sebuah proyek.
  Widget _buildProjectBanner() {
    final count = _projectSources.length;

    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1626),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _activeProjectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_projectSourcesLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            )
          else
            Text(
              count == 0 ? 'Tanpa sumber' : '$count sumber',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          IconButton(
            tooltip: 'Keluar dari proyek',
            onPressed: _exitProject,
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final userName =
        user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : 'User';

    return LayoutBuilder(
      builder: (context, rootConstraints) {
        final isNarrow = rootConstraints.maxWidth < 600;
        final sidebarOpen = _showHistorySidebar;

        final scaffold = Scaffold(
      backgroundColor: _background,

      // =====================================================
      // APP BAR
      // =====================================================

      appBar: AppBar(
      backgroundColor: _background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,

      title: Row(
        children: [
          // Tombol sidebar / riwayat chat. Disembunyikan saat sidebar terbuka
          // di layar kecil supaya tidak menutupi panel riwayat.
          if (!(isNarrow && sidebarOpen))
            _buildHeaderButton(
              icon: Icons.menu_rounded,
              tooltip: 'Riwayat chat',
              onPressed: _toggleHistorySidebar,
            ),
        ],
      ),

        actions: [
          // Tombol pesan sementara
          _buildHeaderButton(
            icon: _isTemporaryChat
                ? Icons.chat_bubble_outline_rounded
                : Icons.forum_outlined,
            tooltip: _isTemporaryChat
                ? 'Kembali ke chat sebelumnya'
                : 'Pesan sementara',
            onPressed: _startTemporaryChat,
          ),
          const SizedBox(width: 12),
        ],
      ),

      // =====================================================
      // BODY
      // =====================================================

      
    body: Builder(
      builder: (context) {
        final chatContent = Stack(
          children: [
            Column(
              children: [
                if (_activeProjectId != null) _buildProjectBanner(),
                Expanded(
                  child: _messages.isEmpty
                      ? (_isTemporaryChat
                          ? _buildTemporaryEmptyState()
                          : _buildEmptyState(userName))
                      : _buildMessageList(),
                ),
                _buildMessageInput(),
              ],
            ),

            if (_showAttachmentMenu)
              Positioned(
                left: 16,
                right: 16,
                bottom: 82,
                child: _buildAttachmentMenu(),
              ),
          ],
        );

        if (isNarrow) {
          return chatContent;
        }

        return Row(
          children: [
            if (sidebarOpen) _buildHistorySidebar(),
            Expanded(child: chatContent),
          ],
        );
      },
    ),
        );

        // Di layar kecil, sidebar tampil penuh menutupi seluruh layar
        // (termasuk AppBar) dari sisi kiri.
        if (!isNarrow) {
          return scaffold;
        }

        return Stack(
          children: [
            scaffold,
            if (sidebarOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleHistorySidebar,
                  child: Container(color: Colors.black54),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                // Material diperlukan karena sidebar kini berada di luar
                // Scaffold (InkWell/ListTile butuh ancestor Material).
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildHistorySidebar(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildTemporaryEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.visibility_off_outlined,
              size: 34,
              color: Colors.white70,
            ),
            const SizedBox(height: 24),
            const Text(
              'Obrolan sementara',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Obrolan ini tidak akan muncul di riwayat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Pesan sementara tidak disimpan ke riwayat chat.',
                    ),
                  ),
                );
              },
              child: const Text(
                'Pelajari selengkapnya',
                style: TextStyle(
                  color: Colors.white70,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String userName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 28,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // LOGO UPATT
            Image.asset(
              'assets/images/upatt_logo.png',
              width: 144,
              height: 144,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 64,
              ),
            ),

            const SizedBox(height: 22),

            // TITLE
            Text(
              'How can I help you?',
              style: AppTextStyles.title.copyWith(
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // DESCRIPTION
            Text(
              'Ask anything, learn something new, '
              'or create with Upatt.',
              style: AppTextStyles.bodySecondary.copyWith(
                color: const Color(0xFF8F8F98),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // SUGGESTIONS
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestion(
                  'Explain a topic',
                  Icons.lightbulb_outline_rounded,
                ),
                _buildSuggestion(
                  'Help me write',
                  Icons.edit_outlined,
                ),
                _buildSuggestion(
                  'Help me study',
                  Icons.school_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SUGGESTION BUTTON
  // =========================================================

  Widget _buildSuggestion(
    String text,
    IconData icon,
  ) {
    return InkWell(
      onTap: () {
        _messageController.text = text;

        setState(() {
          _hasText = true;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: AppTextStyles.bodySecondary.copyWith(
                color: const Color(0xFFB5B5BD),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // MESSAGE LIST
  // =========================================================

  Widget _buildMessageList() {
    final totalItems =
        _messages.length + (_isTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // TYPING INDICATOR
        if (_isTyping &&
            index == _messages.length) {
          return _buildTypingIndicator();
        }

        // MESSAGE
        final message = _messages[index];

        final isUser =
            message['sender'] == 'user';

        return _buildMessageBubble(
          message,
          isUser,
        );
      },
    );
  }

  // =========================================================
  // MESSAGE BUBBLE
  // =========================================================

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isUser,
  ) {
    final text = message['message'] as String? ?? '';
    final attachments = _extractAttachments(message['attachments']);

    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    // Pesan bot: teks polos tanpa bubble, mendukung Markdown.
    if (!isUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.only(bottom: 14),
          child: MarkdownBody(
            data: text,
            selectable: true,
            styleSheet: _markdownStyleSheet,
            builders: _markdownBuilders,
            blockSyntaxes: _markdownBlockSyntaxes,
            inlineSyntaxes: _markdownInlineSyntaxes,
            imageBuilder: _buildMarkdownImage,
            onTapLink: (text, href, title) {
              _openLink(href);
            },
          ),
        ),
      );
    }

    // Gambar pengguna ditampilkan di luar bubble, seperti pola chat modern.
    // Lampiran non-gambar tetap berada di dalam bubble pesan.
    final imageAttachments = attachments
        .where((attachment) =>
            attachment['type'] == 'image' &&
            attachment['bytes'] is Uint8List)
        .toList();

    final otherAttachments = attachments
        .where((attachment) =>
            attachment['type'] != 'image' ||
            attachment['bytes'] is! Uint8List)
        .toList();

    final hasBubbleContent = text.isNotEmpty || otherAttachments.isNotEmpty;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageAttachments.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  bottom: hasBubbleContent ? 8 : 0,
                ),
                child: _buildMessageAttachments(imageAttachments),
              ),
            if (hasBubbleContent)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (otherAttachments.isNotEmpty)
                      _buildMessageAttachments(otherAttachments),
                    if (text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          top: otherAttachments.isNotEmpty ? 8 : 0,
                        ),
                        child: Text(
                          text,
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Ambil daftar lampiran dari sebuah pesan dengan aman.
  List<Map<String, dynamic>> _extractAttachments(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  // Ubah metadata lampiran dari Firestore menjadi struktur pesan.
  // Thumbnail base64 (bila ada) dikembalikan menjadi byte agar gambar
  // tetap tampil setelah chat dimuat ulang.
  List<Map<String, dynamic>> _restoreAttachments(dynamic value) {
    return _extractAttachments(value).map((attachment) {
      final thumb = attachment['thumb'];

      if (thumb is String && thumb.isNotEmpty) {
        try {
          attachment['bytes'] = base64Decode(thumb);
        } catch (_) {
          // Abaikan thumbnail yang rusak.
        }
      }

      return attachment;
    }).toList();
  }

  // Menampilkan lampiran di dalam bubble pesan pengguna.
  Widget _buildMessageAttachments(
    List<Map<String, dynamic>> attachments,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: attachments.map((attachment) {
        final type = attachment['type'] as String? ?? 'file';
        final name = attachment['name'] as String? ?? 'Lampiran';
        final bytes = attachment['bytes'];

        if (type == 'image' && bytes is Uint8List) {
          return GestureDetector(
            onTap: () => _openImageViewer(bytes, name),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes,
                width: 132,
                height: 132,
                fit: BoxFit.cover,
              ),
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Buka lampiran gambar dalam tampilan layar penuh (bisa di-zoom).
  void _openImageViewer(Uint8List bytes, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(bytes: bytes, title: name),
      ),
    );
  }

  // =========================================================
  // MARKDOWN STYLE (pesan bot)
  // =========================================================

  MarkdownStyleSheet get _markdownStyleSheet {
    final body = AppTextStyles.body.copyWith(
      color: const Color(0xFFE5E5EA),
      height: 1.45,
    );

    return MarkdownStyleSheet(
      p: body,
      a: body.copyWith(
        color: AppColors.primary,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.primary,
      ),
      em: body.copyWith(fontStyle: FontStyle.italic),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      del: body.copyWith(decoration: TextDecoration.lineThrough),
      h1: AppTextStyles.title.copyWith(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      h2: AppTextStyles.title.copyWith(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      h3: AppTextStyles.title.copyWith(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      h4: body.copyWith(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      h5: body.copyWith(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      h6: body.copyWith(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      listBullet: body,
      listBulletPadding: const EdgeInsets.only(right: 6),
      blockSpacing: 10,
      blockquote: body.copyWith(color: const Color(0xFFB5B5BD)),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      blockquoteDecoration: const BoxDecoration(
        color: Color(0xFF151518),
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: Color(0xFFE0CFFC),
        backgroundColor: Color(0xFF1D1D21),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A2F)),
        ),
      ),
      tableBorder: TableBorder.all(
        color: _border,
        width: 1,
      ),
      tableHead: body.copyWith(fontWeight: FontWeight.w700),
      tableBody: body,
      // Flex widths avoid a single long formula/image forcing other columns
      // to become extremely narrow on phone-sized screens.
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 6,
      ),
      tableColumnWidth: const FlexColumnWidth(1),
    );
  }

  Future<void> _openLink(String? href) async {
    if (href == null || href.isEmpty) return;

    final uri = Uri.tryParse(href);

    if (uri == null) return;

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa membuka tautan.'),
        ),
      );
    }
  }

  // Menampilkan gambar Markdown secara responsif.
  // Gambar dibatasi lebarnya agar tidak meluber atau berubah menjadi strip
  // sempit ketika jawaban AI berisi tabel atau layar HP berukuran kecil.
  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    final label = (alt == null || alt.trim().isEmpty) ? title : alt;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width * 0.78;
        final imageWidth = availableWidth.clamp(1.0, 420.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => _openLink(uri.toString()),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  uri.toString(),
                  width: imageWidth,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;

                    return Container(
                      width: imageWidth,
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      constraints: BoxConstraints(maxWidth: imageWidth),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.broken_image_outlined,
                            size: 18,
                            color: Color(0xFF8F8F98),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              (label == null || label.trim().isEmpty)
                                  ? 'Gagal memuat gambar'
                                  : label,
                              style: const TextStyle(
                                color: Color(0xFF8F8F98),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // TYPING INDICATOR
  // =========================================================

  Widget _buildTypingIndicator() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 14,
          top: 4,
          left: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TypingDot(),
            SizedBox(width: 5),
            _TypingDot(),
            SizedBox(width: 5),
            _TypingDot(),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ATTACHMENT MENU
  // =========================================================

  Widget _buildAttachmentMenu() {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.35,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAttachmentItem(
            icon: Icons.camera_alt_outlined,
            title: 'Camera',
            onTap: () {
              _selectAttachment('Camera');
            },
          ),
          _buildAttachmentItem(
            icon: Icons.image_outlined,
            title: 'Photo',
            onTap: () {
              _selectAttachment('Photo');
            },
          ),
          _buildAttachmentItem(
            icon: Icons.attach_file_rounded,
            title: 'File',
            onTap: () {
              _selectAttachment('File');
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ATTACHMENT ITEM
  // =========================================================

  Widget _buildAttachmentItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: const Color(0xFFCCCCD2),
              ),
            ),

            const SizedBox(width: 12),

            Text(
              title,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // MESSAGE INPUT
  // =========================================================

  

Widget _buildMessageInput() {
  return Container(
    padding: const EdgeInsets.fromLTRB(
      12,
      8,
      12,
      14,
    ),
    color: _background,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // =================================================
          // SELECTED ATTACHMENTS PREVIEW
          // =================================================
          _buildSelectedAttachments(),

          // =================================================
          // MESSAGE INPUT
          // =================================================
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // PLUS BUTTON
              IconButton(
                onPressed: _toggleAttachmentMenu,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: Icon(
                  _showAttachmentMenu
                      ? Icons.close_rounded
                      : Icons.add_rounded,
                  color: const Color(0xFF9A9AA3),
                  size: 24,
                ),
              ),

              const SizedBox(width: 2),

              // TEXT FIELD
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 46,
                  ),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _border,
                    ),
                  ),
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    cursorColor: AppColors.primary,
                    onChanged: (value) {
                      setState(() {
                        _hasText = value.trim().isNotEmpty;
                      });
                    },
                    onTap: () {
                      if (_showAttachmentMenu) {
                        setState(() {
                          _showAttachmentMenu = false;
                        });
                      }
                    },
                    onSubmitted: (_) {
                      if (_hasText && !_isTyping) {
                        _sendMessage();
                      }
                    },
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Message Upatt...',
                      hintStyle: AppTextStyles.bodySecondary.copyWith(
                        color: const Color(0xFF777780),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // MIC / SEND
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(
                        alpha: 0.22,
                      ),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _isTyping
                      ? null
                      : (_isListening
                          ? _startVoiceInput
                          : (_hasText ? _sendMessage : _startVoiceInput)),
                  tooltip: _isListening ? 'Berhenti merekam' : 'Voice input / kirim',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    _isListening
                        ? Icons.stop_rounded
                        : (_hasText
                            ? Icons.arrow_upward_rounded
                            : Icons.mic_none_rounded),
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
    }


// =============================================================
// TYPING DOT
// =============================================================

class _TypingDot extends StatefulWidget {
  const _TypingDot();

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 900,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase =
            (_controller.value * 3) % 1;

        final opacity =
            0.35 + (phase * 0.65);

        return Opacity(
          opacity: opacity.clamp(0.35, 1.0),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF8F8F98),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// =============================================================
// CODE BLOCK (syntax highlighting)
// =============================================================

// Menangani blok kode (```...```) agar tampil berwarna.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = element.textContent;

    // Buang satu newline di akhir yang ditambahkan parser.
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }

    if (code.trim().isEmpty) {
      return null;
    }

    String? language;

    for (final node in element.children ?? const <md.Node>[]) {
      if (node is md.Element && node.tag == 'code') {
        final className = node.attributes['class'];

        if (className != null && className.startsWith('language-')) {
          language = className.substring('language-'.length).trim();
        }

        break;
      }
    }

    return _CodeBlockView(
      code: code,
      language: language,
    );
  }
}

class _CodeBlockView extends StatelessWidget {
  const _CodeBlockView({
    required this.code,
    this.language,
  });

  final String code;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final label =
        (language == null || language!.isEmpty) ? 'code' : language!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HEADER: bahasa + tombol salin.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF2A2A2F)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8F8F98),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copy(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8F8F98),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.copy_rounded, size: 13),
                label: const Text(
                  'Copy',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        // ISI KODE (bisa digulir horizontal untuk baris panjang).
        Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text.rich(
              _CodeHighlighter.highlight(code, language),
              softWrap: false,
            ),
          ),
        ),
      ],
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kode disalin.'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _CodeHighlighter {
  _CodeHighlighter._();

  static final Highlight _highlight = Highlight()
    ..registerLanguages(builtinAllLanguages);

  // Bahasa yang dipakai untuk deteksi otomatis saat blok kode tanpa label.
  static const List<String> _autoLanguages = [
    'dart',
    'javascript',
    'typescript',
    'python',
    'java',
    'kotlin',
    'swift',
    'c',
    'cpp',
    'csharp',
    'go',
    'rust',
  ];

  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.45,
    color: Color(0xFFABB2BF),
  );

  static final Map<String, TextSpan> _cache = {};

  static TextSpan highlight(String code, String? language) {
    final key = '${language ?? ''}\u0000$code';

    final cached = _cache[key];

    if (cached != null) {
      return cached;
    }

    final span = _compute(code, language);

    if (_cache.length >= 100) {
      _cache.clear();
    }

    _cache[key] = span;

    return span;
  }

  static TextSpan _compute(String code, String? language) {
    final resolved = language?.trim().toLowerCase();

    try {
      final HighlightResult result;

      if (resolved != null &&
          resolved.isNotEmpty &&
          _highlight.getLanguage(resolved) != null) {
        result = _highlight.highlight(
          code: code,
          language: resolved,
        );
      } else {
        result = _highlight.highlightAuto(code, _autoLanguages);
      }

      final renderer = TextSpanRenderer(_baseStyle, atomOneDarkTheme);
      result.render(renderer);

      return renderer.span ?? TextSpan(text: code, style: _baseStyle);
    } catch (_) {
      return TextSpan(text: code, style: _baseStyle);
    }
  }
}

// =============================================================
// EQUATION / MATH (LaTeX)
// =============================================================

// Rumus inline: $...$
class _InlineDollarMathSyntax extends md.InlineSyntax {
  _InlineDollarMathSyntax()
      : super(
          r'\$([^\s\$](?:[^\$\n]*[^\s\$])?)\$',
          startCharacter: 0x24,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = match.group(1)?.trim() ?? '';

    if (tex.isEmpty) return false;

    parser.addNode(md.Element.text('math', tex));

    return true;
  }
}

// Rumus inline: \(...\)
class _InlineParenMathSyntax extends md.InlineSyntax {
  _InlineParenMathSyntax()
      : super(r'\\\((.+?)\\\)', startCharacter: 0x5C);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = match.group(1)?.trim() ?? '';

    if (tex.isEmpty) return false;

    parser.addNode(md.Element.text('math', tex));

    return true;
  }
}

// Rumus blok: ditutup dengan token tertentu ($$...$$ atau \[...\])
class _DisplayMathSyntax extends md.BlockSyntax {
  _DisplayMathSyntax(this._openPattern, this._closeToken);

  final RegExp _openPattern;
  final String _closeToken;

  @override
  RegExp get pattern => _openPattern;

  @override
  bool canParse(md.BlockParser parser) =>
      _openPattern.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    final first = _openPattern.firstMatch(parser.current.content)!;
    final rest = first.group(1) ?? '';

    // Penutup berada di baris yang sama.
    final sameLine = rest.indexOf(_closeToken);

    if (sameLine != -1) {
      parser.advance();

      return md.Element.text(
        'mathblock',
        rest.substring(0, sameLine).trim(),
      );
    }

    final buffer = StringBuffer(rest);
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      final index = line.indexOf(_closeToken);

      if (index != -1) {
        buffer.write('\n');
        buffer.write(line.substring(0, index));
        parser.advance();

        break;
      }

      buffer.write('\n');
      buffer.write(line);
      parser.advance();
    }

    return md.Element.text('mathblock', buffer.toString().trim());
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.block});

  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent.trim();

    if (tex.isEmpty) return null;

    return _MathView(tex: tex, block: block);
  }
}

class _MathView extends StatelessWidget {
  const _MathView({required this.tex, required this.block});

  final String tex;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final equation = Math.tex(
      tex,
      mathStyle: block ? MathStyle.display : MathStyle.text,
      textStyle: const TextStyle(
        fontSize: 15,
        color: Color(0xFFE5E5EA),
      ),
      onErrorFallback: (error) => Text(
        tex,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFE0CFFC),
          backgroundColor: Color(0xFF1D1D21),
        ),
      ),
    );

    if (!block) {
      // Rumus inline kadang lebih lebar daripada kolom Markdown (terutama
      // di tabel dan layar HP). FittedBox mengecilkan rumus seperlunya agar
      // RenderLine tidak overflow ke kanan.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.maxWidth.isFinite) {
              return equation;
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: equation,
              ),
            );
          },
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2F)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: equation,
      ),
    );
  }
}

// =============================================================
// MARKDOWN: builder & syntax tambahan
// =============================================================

final Map<String, MarkdownElementBuilder> _markdownBuilders =
    <String, MarkdownElementBuilder>{
  'pre': _CodeBlockBuilder(),
  'math': _MathBuilder(block: false),
  'mathblock': _MathBuilder(block: true),
};

final List<md.BlockSyntax> _markdownBlockSyntaxes = <md.BlockSyntax>[
  _DisplayMathSyntax(RegExp(r'^\s*\$\$(.*)$'), r'$$'),
  _DisplayMathSyntax(RegExp(r'^\s*\\\[(.*)$'), r'\]'),
];

final List<md.InlineSyntax> _markdownInlineSyntaxes = <md.InlineSyntax>[
  _InlineDollarMathSyntax(),
  _InlineParenMathSyntax(),
];