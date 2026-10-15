import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// The popup containing the three attachment actions.
class ChatAttachmentMenu extends StatelessWidget {
  const ChatAttachmentMenu({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D21),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2F)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentMenuItem(
            icon: Icons.camera_alt_outlined,
            title: 'Camera',
            onTap: () => onSelect('Camera'),
          ),
          _AttachmentMenuItem(
            icon: Icons.image_outlined,
            title: 'Photo',
            onTap: () => onSelect('Photo'),
          ),
          _AttachmentMenuItem(
            icon: Icons.attach_file_rounded,
            title: 'File',
            onTap: () => onSelect('File'),
          ),
        ],
      ),
    );
  }
}

class _AttachmentMenuItem extends StatelessWidget {
  const _AttachmentMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF151518),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFFCCCCD2)),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal preview strip for the files selected before sending.
class ChatAttachmentPreview extends StatelessWidget {
  const ChatAttachmentPreview({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = attachments[index];
          final isImage = item['type'] == 'image';
          final bytes = item['bytes'] as Uint8List;

          return Container(
            width: isImage ? 76 : 190,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D21),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A2F)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      bytes,
                      width: 54,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                if (!isImage) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item['name'] as String? ?? 'File',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.topRight,
                  child: InkWell(
                    onTap: () => onRemove(index),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
