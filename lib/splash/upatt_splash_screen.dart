import 'package:flutter/material.dart';

class UPattSplashScreen extends StatefulWidget {
  const UPattSplashScreen({super.key, required this.nextPage});

  final Widget nextPage;

  @override
  State<UPattSplashScreen> createState() => _UPattSplashScreenState();
}

class _UPattSplashScreenState extends State<UPattSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5400),
  );
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Jalankan animasi splash secara konsisten, termasuk saat preview.
      // Sebelumnya disableAnimations bisa membuat controller langsung ke akhir,
      // sehingga logo langsung tampil utuh dan loading dots tidak bergerak.
      _controller.forward();
    });
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _didNavigate || !mounted) {
      return;
    }
    _didNavigate = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.nextPage,
        transitionDuration: const Duration(milliseconds: 420),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  double _segmentProgress(double start, double end, double value) {
    return Curves.easeOutCubic.transform(
      ((value - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  Widget _logoLayer({
    required String name,
    required double x,
    required double y,
    required double progress,
    required double opacity,
  }) {
    // Tiap bagian masuk pada waktu berbeda supaya proses penyatuan logo terlihat.
    final start = name == 'left' ? 0.04 : name == 'right' ? 0.16 : 0.28;
    final entrance = _segmentProgress(start, start + 0.28, progress);
    final settle = _segmentProgress(0.48, 0.66, progress);
    final directionX = name == 'left' ? -1.0 : name == 'right' ? 1.0 : 0.0;
    final directionY = name == 'center' ? 1.0 : 0.0;
    final rotation = name == 'left'
        ? -0.18 * (1 - entrance)
        : name == 'right'
            ? 0.18 * (1 - entrance)
            : 0.10 * (1 - entrance);
    final settleScale = 1 + 0.025 * (1 - settle);

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(
          x + directionX * 0.24 * 300 * (1 - entrance),
          y + directionY * 0.24 * 300 * (1 - entrance),
        ),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: settleScale,
            child: Image.asset(
              'assets/upatt/UPatt-$name.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A12),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final logoSize = (constraints.maxWidth * 0.72).clamp(220.0, 360.0);
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final value = _controller.value;
                final layersOpacity = _segmentProgress(0.02, 0.18, value);
                final assembledOpacity = _segmentProgress(0.55, 0.72, value);
                final wordmarkOpacity = _segmentProgress(0.68, 0.80, value);
                final taglineOpacity = _segmentProgress(0.74, 0.86, value);
                final glowProgress = _segmentProgress(0.20, 0.68, value);
                final logoScale = 0.94 + 0.06 * assembledOpacity;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _AmbientGlowPainter(progress: glowProgress),
                    ),
                    Align(
                      alignment: const Alignment(0, -0.16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: logoScale,
                            child: SizedBox(
                              width: logoSize,
                              height: logoSize,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _logoLayer(
                                    name: 'left',
                                    x: -225 * logoSize / 2048,
                                    y: -58 * logoSize / 2048,
                                    progress: value,
                                    opacity:
                                        layersOpacity * (1 - assembledOpacity),
                                  ),
                                  _logoLayer(
                                    name: 'center',
                                    x: -102 * logoSize / 2048,
                                    y: 184 * logoSize / 2048,
                                    progress: value,
                                    opacity:
                                        layersOpacity * (1 - assembledOpacity),
                                  ),
                                  _logoLayer(
                                    name: 'right',
                                    x: 242 * logoSize / 2048,
                                    y: -7 * logoSize / 2048,
                                    progress: value,
                                    opacity:
                                        layersOpacity * (1 - assembledOpacity),
                                  ),
                                  Opacity(
                                    opacity: assembledOpacity,
                                    child: Image.asset(
                                      'assets/upatt/UPatt-full.png',
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Opacity(
                            opacity: wordmarkOpacity,
                            child: Transform.translate(
                              offset: Offset(0, 14 * (1 - wordmarkOpacity)),
                              child: const Text(
                                'UPatt',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.1,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: taglineOpacity,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - taglineOpacity)),
                              child: const Text(
                                'Think beyond the prompt.',
                                style: TextStyle(
                                  color: Color(0xFFB8ADD4),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  const _AmbientGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);
    final radius = size.shortestSide * (0.28 + progress * 0.16);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF5F3FC4).withValues(alpha: 0.18 * progress),
          const Color(0xFF24164D).withValues(alpha: 0.07 * progress),
          Colors.transparent,
        ],
        stops: const [0, 0.48, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
