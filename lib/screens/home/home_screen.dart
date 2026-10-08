import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../auth/login_screen.dart';

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

  // =========================================================
  // STATE
  // =========================================================

  final List<Map<String, String>> _messages = [];

  bool _hasText = false;
  bool _showAttachmentMenu = false;
  bool _isTyping = false;

  // =========================================================
  // COLORS
  // =========================================================

  static const Color _background = Color(0xFF050505);
  static const Color _surface = Color(0xFF151518);
  static const Color _surfaceLight = Color(0xFF1D1D21);
  static const Color _border = Color(0xFF2A2A2F);

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty || _isTyping) {
      return;
    }

    FocusScope.of(context).unfocus();

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

    // =======================================================
    // DEMO RESPONSE
    // NANTI DIGANTI DENGAN BACKEND AI
    // =======================================================

    await Future.delayed(
      const Duration(milliseconds: 1500),
    );

    if (!mounted) return;

    setState(() {
      _isTyping = false;

      _messages.add({
        'sender': 'upatt',
        'message':
            'Ini adalah response sementara dari Upatt. '
            'Nanti bagian ini akan diganti dengan response '
            'dari backend AI.',
      });
    });

    _scrollToBottom();
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

  // =========================================================
  // NEW CHAT
  // =========================================================

  void _newChat() {
    setState(() {
      _messages.clear();
      _isTyping = false;
      _showAttachmentMenu = false;
    });
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Chat history will be added later.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: _surfaceLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
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

      body: Stack(
        children: [
          Column(
            children: [
              // =================================================
              // CHAT AREA
              // =================================================

              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState(userName)
                    : _buildMessageList(),
              ),

              // =================================================
              // MESSAGE INPUT
              // =================================================

              _buildMessageInput(),
            ],
          ),

          // ===================================================
          // ATTACHMENT MENU
          // ===================================================

          if (_showAttachmentMenu)
            Positioned(
              left: 16,
              right: 16,
              bottom: 82,
              child: _buildAttachmentMenu(),
            ),
        ],
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
    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(
          bottom: 12,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary
              : _surfaceLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(
              isUser ? 18 : 4,
            ),
            bottomRight: Radius.circular(
              isUser ? 4 : 18,
            ),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: _border,
                ),
          boxShadow: isUser
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.16,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          message,
          style: AppTextStyles.body.copyWith(
            color: isUser
                ? Colors.white
                : const Color(0xFFE5E5EA),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // TYPING INDICATOR
  // =========================================================

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(
          bottom: 12,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: _surfaceLight,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: _border,
          ),
        ),
        child: const Row(
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