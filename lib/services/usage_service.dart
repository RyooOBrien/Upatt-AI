import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/usage_models.dart';
import 'ai_service.dart';

/// Layanan untuk halaman "Penggunaan dan batasan".
///
/// Semua data diambil dari backend Upatt (endpoint /usage/* dan /ai/status),
/// memakai alamat backend yang sama dengan [AiService] (bisa diubah runtime).
class UsageService {
  UsageService._internal();
  static final UsageService instance = UsageService._internal();

  static String get baseUrl => AiService.baseUrl;

  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Kamu harus login terlebih dahulu.');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Gagal mendapatkan token login.');
    return token;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final token = await _getIdToken();
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    late http.Response response;
    if (method == 'POST') {
      response = await http
          .post(uri, headers: headers, body: jsonEncode(body ?? {}))
          .timeout(timeout);
    } else {
      response = await http.get(uri, headers: headers).timeout(timeout);
    }

    if (response.body.isEmpty) {
      throw Exception('Respons kosong dari server.');
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      throw Exception('Respons tidak valid dari server.');
    }

    if (data == null) {
      throw Exception('Respons tidak valid dari server.');
    }

    if (response.statusCode != 200) {
      throw Exception(
        data['error'] ?? 'Permintaan gagal (${response.statusCode}).',
      );
    }

    return data;
  }

  Future<UsageSummary> fetchSummary() async {
    final data = await _request('GET', '/usage/summary');
    return UsageSummary.fromJson(data);
  }

  Future<List<DailyUsagePoint>> fetchDaily({int days = 7}) async {
    final data = await _request('GET', '/usage/daily?days=$days');
    final list = data['days'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(DailyUsagePoint.fromJson)
          .toList();
    }
    return const [];
  }

  Future<UsageLimits> fetchLimits() async {
    final data = await _request('GET', '/usage/limits');
    return UsageLimits.fromJson(data);
  }

  Future<AiStatus> fetchAiStatus() async {
    final data = await _request('GET', '/ai/status');
    return AiStatus.fromJson(data);
  }

  Future<AccountUsageSettings> fetchAccountSettings() async {
    final data = await _request('GET', '/account/usage-settings');
    return AccountUsageSettings.fromJson(data);
  }

  Future<bool> setAutomaticRecharge(bool enabled) async {
    final data = await _request(
      'POST',
      '/account/usage-settings',
      body: {'automaticRecharge': enabled},
    );
    return data['automaticRecharge'] == true;
  }
}
