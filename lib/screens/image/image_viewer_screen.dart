import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Penampil gambar layar penuh untuk lampiran foto.
///
/// Gambar bisa di-zoom (cubit/putar dua jari) lewat [InteractiveViewer].
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.bytes,
    this.title,
  });

  final Uint8List bytes;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final name = title?.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          name.isEmpty ? 'Foto' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
