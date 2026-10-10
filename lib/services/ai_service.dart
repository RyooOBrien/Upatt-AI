
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AiService {
  // Alamat backend AI.
  //
  // Saat build/rilis, tentukan alamatnya, contoh:
  //   flutter build apk --dart-define=API_BASE_URL=https://<url-cloud-function>
  // (URL tanpa akhiran /api; path /api/chat ditambahkan otomatis).
  //
  // Bila tidak diatur, dipakai alamat default untuk development lokal.
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

    // 10.0.2.2 adalah alias localhost milik Android Emulator.
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }

    return 'http://localhost:3000';
  }

  static Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('Kamu harus login terlebih dahulu.');
    }

    final token = await user.getIdToken();

    if (token == null) {
      throw Exception('Gagal mendapatkan token login.');
    }

    return token;
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _getIdToken();

    final response = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));

    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic>) {
      throw Exception('Respons backend tidak valid.');
    }

    if (response.statusCode != 200) {
      throw Exception(
        data['error'] ?? 'Permintaan ke AI gagal.',
      );
    }

    return data;
  }

  static Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const [],
    String memorySummary = '',
  }) async {
    final data = await _post('/api/chat', {
      'message': message,
      'history': history,
      'memorySummary': memorySummary,
    });

    return data['reply'] as String;
  }

  // Mengirim pesan dan menerima jawaban secara bertahap (streaming SSE).
  // Tiap potongan teks (delta) di-yield begitu diterima dari backend.
  static Stream<String> sendMessageStream({
    required String message,
    List<Map<String, String>> history = const [],
    String memorySummary = '',
  }) async* {
    final token = await _getIdToken();
    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'Authorization': 'Bearer $token',
        })
        ..body = jsonEncode({
          'message': message,
          'history': history,
          'memorySummary': memorySummary,
          'stream': true,
        });

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();

        throw Exception(_extractError(body));
      }

      var buffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;

        while (true) {
          final newlineIndex = buffer.indexOf('\n');

          if (newlineIndex == -1) break;

          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty || !line.startsWith('data:')) continue;

          final payload = line.substring(5).trim();

          if (payload == '[DONE]') return;

          Map<String, dynamic>? data;

          try {
            final decoded = jsonDecode(payload);

            if (decoded is Map<String, dynamic>) {
              data = decoded;
            }
          } on FormatException {
            continue;
          }

          if (data == null) continue;

          final error = data['error'];

          if (error is String && error.isNotEmpty) {
            throw Exception(error);
          }

          final delta = data['delta'];

          if (delta is String && delta.isNotEmpty) {
            yield delta;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  static String _extractError(String body) {
    const fallback = 'Permintaan ke AI gagal.';

    try {
      final data = jsonDecode(body);

      if (data is Map && data['error'] is String) {
        final message = (data['error'] as String).trim();

        return message.isEmpty ? fallback : message;
      }
    } on FormatException {
      return fallback;
    }

    return fallback;
  }

  static Future<String> summarizeMessages({
    required String previousSummary,
    required List<Map<String, String>> messages,
  }) async {
    final data = await _post('/api/summarize', {
      'previousSummary': previousSummary,
      'messages': messages,
    });

    return data['summary'] as String;
  }
}
