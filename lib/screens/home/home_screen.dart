import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../services/chat_repository.dart';

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

  String? _currentChatId;

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

  final List<Map<String, String>> _messages = [];

  String _memorySummary = '';
  int _summarizedCount = 0;

  bool _hasText = false;
  bool _showAttachmentMenu = false;
  bool _isTyping = false;
  bool _showHistorySidebar = false;

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
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

  
  
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty || _isTyping) return;

    FocusScope.of(context).unfocus();

    final requestId = ++_activeRequestId;

    setState(() {
      _messages.add({
        'sender': 'user',
        'message': message,
      });

      _messageController.clear();
      _hasText = false;
      _showAttachmentMenu = false;
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      await _ensureChatExists();

      final chatId = _currentChatId!;

      // Simpan pesan pengguna.
      await _chatRepository.saveMessage(
        chatId: chatId,
        role: 'user',
        content: message,
      );

      // Kirim konteks percakapan sebelumnya ke backend AI.
      // Hanya kirim pesan yang belum diringkas sebagai memori,
      // lalu batasi jumlahnya agar tidak melewati batas backend.
      final start = _summarizedCount.clamp(
        0,
        _messages.length - 1,
      );

      // Pesan terakhir adalah pesan pengguna yang baru dikirim.
      // Jangan kirim dua kali.
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

      // Kirim pesan & tampilkan jawaban secara bertahap (streaming).
      final reply = await _requestAiReply(
        message: message,
        history: historyPayload,
        requestId: requestId,
      );

      // Simpan jawaban AI.
      await _chatRepository.saveMessage(
        chatId: chatId,
        role: 'assistant',
        content: reply,
      );

      if (!mounted || requestId != _activeRequestId) return;

      // Jadikan pesan pertama sebagai judul chat.
      if (_messages.length == 2) {
        final title = message.length > 35
            ? '${message.substring(0, 35)}...'
            : message;

        await _chatRepository.updateChatTitle(
          chatId,
          title,
        );
      }

      // Perbarui memori percakapan jika sudah cukup panjang.
      await _updateMemory(chatId);
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
                ? 'Gagal mengirim pesan atau menyimpan chat.'
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

    setState(() {
      _messages.clear();
      _currentChatId = null;
      _memorySummary = '';
      _summarizedCount = 0;
      _isTyping = false;
      _showAttachmentMenu = false;
      _stickToBottom = true;
    });
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

      if (!mounted) return;

      setState(() {
        _currentChatId = chatId;
        _messages
          ..clear()
          ..addAll(
            snapshot.docs.map((doc) {
              final data = doc.data();

              return <String, String>{
                'sender': data['role'] == 'assistant'
                    ? 'upatt'
                    : 'user',
                'message': data['content'] as String? ?? '',
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
      });

      _scrollToBottom();
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

    final chatId = await _chatRepository.createChat();

    if (!mounted) return;

    setState(() {
      _currentChatId = chatId;
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
                  tooltip: 'Close sidebar',
                  onPressed: _toggleHistorySidebar,
                  icon: const Icon(
                    Icons.menu_open_rounded,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: () {
                _newChat();
                _toggleHistorySidebar();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'New Chat',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
            child: Text(
              'RECENT CHATS',
              style: TextStyle(
                color: Color(0xFF85858F),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
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

                final chats = snapshot.data?.docs ?? [];

                if (chats.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Belum ada percakapan.',
                      style: TextStyle(color: Colors.white54),
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
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 17,
                                color: Color(0xFFAAAAB4),
                              ),
                              const SizedBox(width: 10),
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  color: Colors.white70,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user.displayName ??
                        user.email ??
                        'User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
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

  void _selectAttachment(String type) {
    setState(() {
      _showAttachmentMenu = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type feature will be added later.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // =========================================================
  // VOICE
  // =========================================================

  void _startVoiceInput() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Voice input will be added later.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final userName =
        user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : 'User';

    return Scaffold(
      backgroundColor: _background,

      // =====================================================
      // APP BAR
      // =====================================================

      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 8,

        title: Row(
          children: [
            // MENU
            IconButton(
              onPressed: _toggleHistorySidebar,
              icon: const Icon(
                Icons.menu_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),

            // UPATT ICON
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.25,
                    ),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),

            const SizedBox(width: 8),

            // UPATT NAME
            Text(
              'Upatt',
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        actions: [
          // NEW CHAT
          IconButton(
            onPressed: _newChat,
            tooltip: 'New chat',
            icon: const Icon(
              Icons.edit_square,
              size: 21,
              color: Colors.white,
            ),
          ),

          // MORE
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Colors.white,
            ),
            color: _surfaceLight,
            onSelected: (value) {
              if (value == 'new_chat') {
                _newChat();
              }

              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: 'new_chat',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_comment_outlined,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'New chat',
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Logout',
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),

          const SizedBox(width: 4),
        ],
      ),

      // =====================================================
      // BODY
      // =====================================================

      
    body: LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final chatContent = Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState(userName)
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
          return Stack(
            children: [
              chatContent,
              if (_showHistorySidebar) ...[
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
                  child: _buildHistorySidebar(),
                ),
              ],
            ],
          );
        }

        return Row(
          children: [
            if (_showHistorySidebar) _buildHistorySidebar(),
            Expanded(child: chatContent),
          ],
        );
      },
    ),

    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmptyState(String userName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 28,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ICON
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.primary.withValues(
                    alpha: 0.18,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.12,
                    ),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 36,
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
          message['message'] ?? '',
          isUser,
        );
      },
    );
  }

  // =========================================================
  // MESSAGE BUBBLE
  // =========================================================

  Widget _buildMessageBubble(
    String message,
    bool isUser,
  ) {
    final maxWidth =
        MediaQuery.of(context).size.width * 0.78;

    // Pesan bot: teks polos tanpa bubble, mendukung Markdown.
    if (!isUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
          ),
          margin: const EdgeInsets.only(
            bottom: 14,
          ),
          child: MarkdownBody(
            data: message,
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

    // Pesan user: memakai bubble.
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
        ),
        margin: const EdgeInsets.only(
          bottom: 12,
        ),
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
              color: AppColors.primary.withValues(
                alpha: 0.16,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          message,
          style: AppTextStyles.body.copyWith(
            color: Colors.white,
          ),
        ),
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
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
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

  // Menampilkan gambar Markdown lengkap dengan placeholder & fallback.
  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    final label = (alt == null || alt.trim().isEmpty) ? title : alt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _openLink(uri.toString()),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;

              return Container(
                height: 160,
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
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            // =================================================
            // PLUS BUTTON
            // =================================================

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

            // =================================================
            // TEXT FIELD
            // =================================================

            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 46,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius:
                      BorderRadius.circular(24),
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
                      _hasText =
                          value.trim().isNotEmpty;
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
                  textInputAction:
                      TextInputAction.send,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Message Upatt...',
                    hintStyle:
                        AppTextStyles.bodySecondary
                            .copyWith(
                      color: const Color(0xFF777780),
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // =================================================
            // MIC / SEND
            // =================================================

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
                    : (_hasText
                        ? _sendMessage
                        : _startVoiceInput),
                padding: EdgeInsets.zero,
                icon: Icon(
                  _hasText
                      ? Icons.arrow_upward_rounded
                      : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
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
        fontSize: 17,
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: equation,
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