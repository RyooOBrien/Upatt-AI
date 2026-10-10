import 'package:device_preview/device_preview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    DevicePreview(
      // Hanya aktif saat development, tidak ikut ke build rilis.
      enabled: !kReleaseMode,
      builder: (context) => const AIChatbotApp(),
    ),
  );
}

class AIChatbotApp extends StatelessWidget {
  const AIChatbotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Upatt',
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}
