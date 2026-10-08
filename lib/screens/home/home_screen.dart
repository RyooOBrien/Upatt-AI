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

class _HomeScreenState extends State<HomeScreen> {
  // =========================
  // CONTROLLERS
  // =========================

  final _messageController = TextEditingController();

  // =========================
  // STATE
  // =========================

  final List<Map<String, String>> _messages = [];

  bool _isComposerExpanded = false;
  bool _hasText = false;

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // =========================
  // SEND MESSAGE
  // =========================

  void _sendMessage() {
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      return;
    }

    setState(() {
      _messages.add({
        'sender': 'user',
        'message': message,
      });

      _messageController.clear();
      _hasText = false;
      _isComposerExpanded = false;
    });

    // TODO:
    // Response dari API Upatt akan ditambahkan
    // oleh teman kamu di bagian ini.
  }

  // =========================
  // LOGOUT
  // =========================

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

  // =========================
  // NEW CHAT
  // =========================

  void _newChat() {
    if (_messages.isEmpty) {
      return;
    }

    setState(() {
      _messages.clear();
      _messageController.clear();
      _hasText = false;
      _isComposerExpanded = false;
    });
  }

  // =========================
  // ATTACHMENT ACTION
  // =========================

  void _handleAttachment(String type) {
    setState(() {
      _isComposerExpanded = false;
    });

    String message;

    switch (type) {
      case 'camera':
        message = 'Camera feature coming soon.';
        break;

      case 'photo':
        message = 'Photo picker coming soon.';
        break;

      case 'file':
        message = 'File picker coming soon.';
        break;

      default:
        message = 'Feature coming soon.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // =========================
  // BUILD
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // =========================
      // APP BAR
      // =========================

      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () {
            // Chat history akan dibuat nanti.
          },
          icon: const Icon(
            Icons.menu_rounded,
          ),
          tooltip: 'Chat history',
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),

            const SizedBox(width: 10),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upatt',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // NEW CHAT
          IconButton(
            onPressed: _newChat,
            icon: const Icon(
              Icons.edit_square,
            ),
            tooltip: 'New chat',
          ),

          // MORE
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout_rounded,
                      ),
                      SizedBox(width: 10),
                      Text('Logout'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),

      // =========================
      // BODY
      // =========================

      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : _buildMessageList(),
          ),

          _buildMessageInput(),
        ],
      ),
    );
  }

  // =========================
  // EMPTY STATE
  // =========================

  Widget _buildEmptyState() {
    return const SizedBox.expand();
  }

  // =========================
  // MESSAGE LIST
  // =========================

  Widget _buildMessageList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        16,
        20,
        16,
        20,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        final isUser = message['sender'] == 'user';

        return Padding(
          padding: const EdgeInsets.only(
            bottom: 24,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              // =========================
              // UPATT AVATAR
              // =========================

              if (!isUser)
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(
                    right: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),

              // =========================
              // MESSAGE CONTENT
              // =========================

              Flexible(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isUser)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 5,
                          left: 2,
                        ),
                        child: Text(
                          'Upatt',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),

                    Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width *
                                0.78,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? AppColors.primary
                            : AppColors.surface,
                        borderRadius: BorderRadius.only(
                          topLeft:
                              const Radius.circular(18),
                          topRight:
                              const Radius.circular(18),
                          bottomLeft: Radius.circular(
                            isUser ? 18 : 4,
                          ),
                          bottomRight: Radius.circular(
                            isUser ? 4 : 18,
                          ),
                        ),
                      ),
                      child: Text(
                        message['message'] ?? '',
                        style: AppTextStyles.body.copyWith(
                          color: isUser
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),

                    if (isUser)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 5,
                          right: 2,
                        ),
                        child: Text(
                          'You',
                          style:
                              AppTextStyles.bodySecondary.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================
  // COMPOSER ACTION
  // =========================

  Widget _buildComposerAction({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(width: 14),

            Text(
              title,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // MESSAGE INPUT
  // =========================

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12,
      ),
      color: AppColors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // =========================
          // ATTACHMENT MENU
          // =========================

          if (_isComposerExpanded)
            Padding(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: 12,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Column(
                  children: [
                    _buildComposerAction(
                      icon: Icons.camera_alt_outlined,
                      title: 'Camera',
                      onTap: () {
                        _handleAttachment('camera');
                      },
                    ),

                    _buildComposerAction(
                      icon: Icons.photo_outlined,
                      title: 'Photo',
                      onTap: () {
                        _handleAttachment('photo');
                      },
                    ),

                    _buildComposerAction(
                      icon: Icons.attach_file_rounded,
                      title: 'File',
                      onTap: () {
                        _handleAttachment('file');
                      },
                    ),
                  ],
                ),
              ),
            ),

          // =========================
          // MESSAGE COMPOSER
          // =========================

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      // PLUS BUTTON
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isComposerExpanded =
                                !_isComposerExpanded;
                          });
                        },
                        icon: Icon(
                          _isComposerExpanded
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                        ),
                        color: AppColors.textSecondary,
                        tooltip: 'Add',
                      ),

                      // TEXT FIELD
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          textInputAction:
                              TextInputAction.newline,
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (value) {
                            setState(() {
                              _hasText =
                                  value.trim().isNotEmpty;
                            });
                          },
                          decoration:
                              const InputDecoration(
                            hintText:
                                'Message Upatt...',
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),

                      // MIC BUTTON
                      IconButton(
                        onPressed: () {
                          // Voice input akan dibuat nanti.
                        },
                        icon: const Icon(
                          Icons.mic_none_rounded,
                        ),
                        color: AppColors.textSecondary,
                        tooltip: 'Voice input',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // =========================
              // SEND / VOICE BUTTON
              // =========================

              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _hasText
                      ? _sendMessage
                      : () {
                          // Voice chat akan dibuat nanti.
                        },
                  icon: Icon(
                    _hasText
                        ? Icons.arrow_upward_rounded
                        : Icons.graphic_eq_rounded,
                    color: Colors.white,
                  ),
                  tooltip: _hasText
                      ? 'Send'
                      : 'Voice chat',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}