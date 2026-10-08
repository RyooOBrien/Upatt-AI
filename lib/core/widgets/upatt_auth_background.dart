import 'package:flutter/material.dart';

class UpattAuthBackground extends StatelessWidget {
  final Widget child;

  const UpattAuthBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // =========================
          // BASE BLACK
          // =========================

          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF050505),
            ),
          ),

          // =========================
          // BOTTOM PURPLE GLOW
          // =========================

          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 1.15),
                  radius: 1.15,
                  colors: [
                    Color(0xFF382070),
                    Color(0xFF120D20),
                    Color(0x00050505),
                  ],
                  stops: [
                    0.0,
                    0.45,
                    1.0,
                  ],
                ),
              ),
            ),
          ),

          // =========================
          // SUBTLE GRAY TOP RIGHT
          // =========================

          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.15, -1.05),
                  radius: 0.9,
                  colors: [
                    Color(0xFF3A3A40),
                    Color(0x00050505),
                  ],
                  stops: [
                    0.0,
                    1.0,
                  ],
                ),
              ),
            ),
          ),

          // =========================
          // CONTENT
          // =========================

          child,
        ],
      ),
    );
  }
}