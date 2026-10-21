/// Model data untuk halaman "Penggunaan dan batasan".
///
/// Semua angka berasal dari backend (endpoint /usage/* dan /ai/status).
class UsageSummary {
  UsageSummary({
    required this.todayRequests,
    required this.todayTokens,
    required this.last7Requests,
    required this.last7Tokens,
    required this.last30Requests,
    required this.last30Tokens,
    required this.allTimeRequests,
    required this.allTimeTokens,
  });

  final int todayRequests;
  final int todayTokens;
  final int last7Requests;
  final int last7Tokens;
  final int last30Requests;
  final int last30Tokens;
  final int allTimeRequests;
  final int allTimeTokens;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is num ? v.toInt() : 0;
    final today = json['today'] as Map<String, dynamic>? ?? const {};
    final last7 = json['last7Days'] as Map<String, dynamic>? ?? const {};
    final last30 = json['last30Days'] as Map<String, dynamic>? ?? const {};
    final allTime = json['allTime'] as Map<String, dynamic>? ?? const {};
    return UsageSummary(
      todayRequests: toInt(today['requests']),
      todayTokens: toInt(today['tokens']),
      last7Requests: toInt(last7['requests']),
      last7Tokens: toInt(last7['tokens']),
      last30Requests: toInt(last30['requests']),
      last30Tokens: toInt(last30['tokens']),
      allTimeRequests: toInt(allTime['requests']),
      allTimeTokens: toInt(allTime['tokens']),
    );
  }
}

class DailyUsagePoint {
  DailyUsagePoint({
    required this.date,
    required this.requests,
    required this.tokens,
  });

  final String date;
  final int requests;
  final int tokens;

  factory DailyUsagePoint.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is num ? v.toInt() : 0;
    return DailyUsagePoint(
      date: json['date']?.toString() ?? '',
      requests: toInt(json['requests']),
      tokens: toInt(json['tokens']),
    );
  }
}

class UsageLimits {
  UsageLimits({
    required this.requestsPerMinute,
    required this.requestsPerDay,
    required this.windowMs,
    required this.usedToday,
    required this.remainingToday,
    required this.remainingFraction,
    required this.resetAt,
    required this.billingResetAt,
  });

  final int requestsPerMinute;
  final int requestsPerDay;
  final int windowMs;
  final int usedToday;
  final int remainingToday;
  final double remainingFraction;
  final DateTime? resetAt;
  final DateTime? billingResetAt;

  factory UsageLimits.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is num ? v.toInt() : 0;

    final limits = json['limits'] as Map<String, dynamic>? ?? const {};
    final used = json['used'] as Map<String, dynamic>? ?? const {};
    final remaining = json['remaining'] as Map<String, dynamic>? ?? const {};

    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v).toLocal();
        } catch (_) {}
      }
      return null;
    }

    final fraction = remaining['fraction'];

    return UsageLimits(
      requestsPerMinute: toInt(limits['requestsPerMinute']),
      requestsPerDay: toInt(limits['requestsPerDay']),
      windowMs: toInt(limits['windowMs']),
      usedToday: toInt(used['today']),
      remainingToday: toInt(remaining['today']),
      remainingFraction:
          fraction is num ? fraction.toDouble().clamp(0.0, 1.0) : 0.0,
      resetAt: parseDate(json['resetAt']),
      billingResetAt: parseDate(json['billingResetAt']),
    );
  }
}

class AiStatus {
  AiStatus({
    required this.provider,
    required this.model,
    required this.status,
    required this.latencyMs,
    required this.updatedAt,
  });

  final String provider;
  final String model;
  final String status;
  final int? latencyMs;
  final DateTime? updatedAt;

  factory AiStatus.fromJson(Map<String, dynamic> json) {
    int? toIntOrNull(dynamic v) => v is num ? v.toInt() : null;
    DateTime? upd;
    final u = json['updatedAt'];
    if (u is String && u.isNotEmpty) {
      try {
        upd = DateTime.parse(u).toLocal();
      } catch (_) {}
    }
    return AiStatus(
      provider: json['provider']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      latencyMs: toIntOrNull(json['latencyMs']),
      updatedAt: upd,
    );
  }
}

class AccountUsageSettings {
  AccountUsageSettings({
    required this.automaticRecharge,
    required this.plan,
  });

  final bool automaticRecharge;
  final String plan;

  factory AccountUsageSettings.fromJson(Map<String, dynamic> json) {
    return AccountUsageSettings(
      automaticRecharge: json['automaticRecharge'] == true,
      plan: json['plan']?.toString() ?? 'Gratis',
    );
  }
}
