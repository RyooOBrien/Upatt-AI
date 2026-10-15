import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Layar kamera in-app untuk mengambil foto sebagai lampiran.
///
/// Berbeda dengan `image_picker` yang mengandalkan aplikasi kamera sistem
/// (hanya tersedia di Android/iOS), layar ini memakai paket `camera` sehingga
/// tombol Camera benar-benar membuka kamera di Android, iOS, dan web.
///
/// Mengembalikan satu lampiran berupa `Map` dengan struktur yang sama seperti
/// `AttachmentPickerService` (name, type, size, bytes) atau `null` bila
/// pengguna membatalkan.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isInitializing = true;
  bool _isTakingPicture = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Kamera tidak tersedia di perangkat ini.';
          _isInitializing = false;
        });
        return;
      }

      _cameras = cameras;
      await _setupController(cameras[_cameraIndex]);
    } catch (error) {
      debugPrint('Gagal membuka kamera: $error');

      if (!mounted) return;

      setState(() {
        _error = 'Gagal membuka kamera.\nPastikan izin kamera sudah diberikan.';
        _isInitializing = false;
      });
    }
  }

  Future<void> _setupController(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
    } catch (error) {
      debugPrint('Gagal inisialisasi kamera: $error');
      await controller.dispose();

      if (!mounted) return;

      setState(() {
        _error = 'Gagal membuka kamera.\nPastikan izin kamera sudah diberikan.';
        _isInitializing = false;
      });
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    await _controller?.dispose();

    setState(() {
      _controller = controller;
      _isInitializing = false;
      _error = null;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPicture) {
      return;
    }

    setState(() => _isTakingPicture = true);

    try {
      final picture = await controller.takePicture();
      final bytes = await picture.readAsBytes();

      if (!mounted) return;

      Navigator.of(context).pop(<String, dynamic>{
        'name': picture.name.isNotEmpty
            ? picture.name
            : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        'type': 'image',
        'size': bytes.length,
        'bytes': bytes,
      });
    } catch (error) {
      debugPrint('Gagal mengambil foto: $error');

      if (!mounted) return;

      setState(() => _isTakingPicture = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengambil foto. Coba lagi.')),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _isInitializing = true);

    await _setupController(_cameras[_cameraIndex]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Ambil Foto'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Tutup',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white54,
                size: 42,
              ),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;

    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            // CameraPreview sudah menangani aspect ratio (termasuk orientasi
            // portrait) sendiri. Jangan dibungkus AspectRatio lagi supaya
            // preview tidak tampak gepeng/terdistorsi.
            child: CameraPreview(controller),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48),
              GestureDetector(
                onTap: _isTakingPicture ? null : _capture,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTakingPicture ? Colors.white54 : Colors.white,
                    border: Border.all(color: Colors.white24, width: 4),
                  ),
                ),
              ),
              IconButton(
                onPressed: _cameras.length < 2 ? null : _switchCamera,
                tooltip: 'Ganti kamera',
                icon: const Icon(
                  Icons.cameraswitch_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
