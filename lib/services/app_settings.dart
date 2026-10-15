import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';

/// Pengaturan sederhana yang disimpan di perangkat (SharedPreferences).
class AppSettings {
  AppSettings._();

  static const String _apiBaseUrlKey = 'api_base_url';

  /// Muat pengaturan tersimpan ke layanan yang membutuhkannya.
  ///
  /// Dipanggil sekali saat aplikasi mulai berjalan.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    AiService.setRuntimeBaseUrl(prefs.getString(_apiBaseUrlKey));
  }

  /// Simpan alamat backend. Kosong berarti kembali ke alamat default.
  static Future<void> saveApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = url.trim();

    if (trimmed.isEmpty) {
      await prefs.remove(_apiBaseUrlKey);
    } else {
      await prefs.setString(_apiBaseUrlKey, trimmed);
    }

    AiService.setRuntimeBaseUrl(trimmed);
  }
}
