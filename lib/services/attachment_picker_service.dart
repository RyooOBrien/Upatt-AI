import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Layanan pemilih lampiran (kamera, galeri foto, file).
///
/// Mendukung Android, iOS, dan web:
/// - `Camera` -> kamera perangkat.
/// - `Photo`  -> galeri foto.
/// - `File`   -> pemilih file (semua jenis, boleh banyak).
///
/// Setiap lampiran dikembalikan sebagai:
/// ```
/// {
///   'name': String,           // nama file
///   'type': 'image' | 'file', // jenis lampiran
///   'size': int,              // ukuran byte
///   'bytes': Uint8List,       // isi file (hanya di memori)
/// }
/// ```
class AttachmentPickerService {
  AttachmentPickerService._();

  static final ImagePicker _imagePicker = ImagePicker();

  /// Batas ukuran file supaya memori tetap aman.
  static const int maxFileSizeBytes = 20 * 1024 * 1024; // 20 MB

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };

  static Future<List<Map<String, dynamic>>> pick(String type) async {
    switch (type) {
      case 'Camera':
        return _pickImage(ImageSource.camera);
      case 'Photo':
        return _pickImage(ImageSource.gallery);
      case 'File':
      default:
        return _pickFiles();
    }
  }

  static Future<List<Map<String, dynamic>>> _pickImage(
    ImageSource source,
  ) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (picked == null) return const [];

      final bytes = await picked.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Gagal membaca gambar.');
      }

      return [
        _buildAttachment(
          name: picked.name.isNotEmpty
              ? picked.name
              : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes: bytes,
          mimeType: picked.mimeType,
          forceImage: true,
          thumb: await encodeThumbnail(bytes),
        ),
      ];
    } on Exception catch (error) {
      // Sebagian platform (mis. desktop) tidak punya kamera/galeri.
      // Fallback: buka pemilih file biasa agar fitur tetap bisa dipakai.
      debugPrint('Image picker fallback ke file picker: $error');
      return _pickFiles();
    }
  }

  static Future<List<Map<String, dynamic>>> _pickFiles() async {
    final files = await FilePicker.pickFiles();

    if (files.isEmpty) return const [];

    final attachments = <Map<String, dynamic>>[];

    for (final file in files) {
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) continue;

      if (bytes.length > maxFileSizeBytes) {
        throw Exception(
          'Ukuran file "${file.name}" melebihi ${maxFileSizeBytes ~/ (1024 * 1024)} MB.',
        );
      }

      final attachment = _buildAttachment(
        name: file.name,
        bytes: bytes,
        mimeType: null,
        forceImage: false,
      );

      if (attachment['type'] == 'image') {
        attachment['thumb'] = await encodeThumbnail(bytes);
      }

      attachments.add(attachment);
    }

    return attachments;
  }

  static Map<String, dynamic> _buildAttachment({
    required String name,
    required Uint8List bytes,
    required String? mimeType,
    required bool forceImage,
    String? thumb,
  }) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';

    final isImage = forceImage ||
        (mimeType != null && mimeType.startsWith('image/')) ||
        _imageExtensions.contains(extension);

    return {
      'name': name,
      'type': isImage ? 'image' : 'file',
      'size': bytes.length,
      'bytes': bytes,
      'thumb': ?thumb,
    };
  }

  /// Membuat thumbnail kecil (PNG dalam base64) dari sebuah gambar.
  ///
  /// Dipakai agar lampiran gambar tetap tampil setelah chat dimuat ulang,
  /// tanpa menyimpan file aslinya ke Firestore.
  static Future<String?> encodeThumbnail(Uint8List bytes) async {
    const sizes = <int>[320, 200, 128];
    String? smallest;

    for (final size in sizes) {
      try {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: size,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);

        image.dispose();
        codec.dispose();

        if (data == null) continue;

        final encoded = base64Encode(data.buffer.asUint8List());
        smallest = encoded;

        // Simpan versi pertama yang cukup kecil untuk Firestore.
        if (encoded.length <= 90000) return encoded;
      } catch (error) {
        debugPrint('Gagal membuat thumbnail: $error');
        return null;
      }
    }

    return smallest;
  }
}
