import 'dart:async';

import 'package:flutter/material.dart';

/// Notifikasi bergaya Upatt: pop-up, progress ungu, lalu hilang dalam 3 detik.
class UpattNotification {
  UpattNotification._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    // Ganti notifikasi sebelumnya jika masih tampil.
    _currentEntry?.remove();
    _currentEntry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _UpattNotificationOverlay(
        message: message,
        isError: isError,
        onClosed: () {
          if (entry.mounted) {
            entry.remove();
          }
          if (identical(_currentEntry, entry)) {
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _UpattNotificationOverlay extends StatefulWidget {
  const _UpattNotificationOverlay({
    required this.message,
    required this.isError,
    required this.onClosed,
  });

  final String message;
  final bool isError;
  final VoidCallback onClosed;

  @override
  State<_UpattNotificationOverlay> createState() =>
      _UpattNotificationOverlayState();
}

class _UpattNotificationOverlayState extends State<_UpattNotificationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _durationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _durationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _entranceController.forward();
    _durationController.forward();

    // Mulai mengecil pada 2,82 detik agar hilang sekitar detik ke-3.
    _dismissTimer = Timer(const Duration(milliseconds: 2820), () async {
      if (!mounted) return;
      await _entranceController.reverse();
      if (mounted) widget.onClosed();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _entranceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isError
        ? const Color(0xFFFF5D70)
        : const Color(0xFF8B6BFF);
    final icon = widget.isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Positioned.fill(
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 12,
                  left: 16,
                  right: 16,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF151419),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF383143),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.32),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: accent.withOpacity(0.10),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                15,
                                14,
                                16,
                                14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.13),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      icon,
                                      color: accent,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.message,
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5FC),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 3,
                              width: double.infinity,
                              child: AnimatedBuilder(
                                animation: _durationController,
                                builder: (context, _) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: (1 - _durationController.value)
                                          .clamp(0.0, 1.0),
                                      child: Container(color: accent),
                                    ),
                                  );
                                },
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
          ),
        ),
      ),
    );
  }
}
