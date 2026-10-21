// Unit test untuk parsing model usage (halaman Penggunaan dan batasan).
import 'package:flutter_test/flutter_test.dart';
import 'package:aichatbot/models/usage_models.dart';

void main() {
  group('UsageSummary', () {
    test('parses numbers', () {
      final s = UsageSummary.fromJson({
        'today': {'requests': 2, 'tokens': 500},
        'last7Days': {'requests': 10, 'tokens': 2500},
        'last30Days': {'requests': 40, 'tokens': 9000},
        'allTime': {'requests': 100, 'tokens': 20000},
      });
      expect(s.todayRequests, 2);
      expect(s.todayTokens, 500);
      expect(s.last7Requests, 10);
      expect(s.last30Requests, 40);
      expect(s.allTimeRequests, 100);
    });

    test('handles missing fields', () {
      final s = UsageSummary.fromJson({});
      expect(s.todayRequests, 0);
      expect(s.allTimeTokens, 0);
    });
  });

  group('UsageLimits', () {
    test('parses limits and fraction', () {
      final l = UsageLimits.fromJson({
        'limits': {
          'requestsPerMinute': 30,
          'requestsPerDay': 100,
          'windowMs': 60000,
        },
        'used': {'today': 40},
        'remaining': {'today': 60, 'fraction': 0.6},
        'resetAt': '2099-01-01T00:00:00.000Z',
        'billingResetAt': '2099-02-01T00:00:00.000Z',
      });
      expect(l.requestsPerDay, 100);
      expect(l.usedToday, 40);
      expect(l.remainingToday, 60);
      expect(l.remainingFraction, 0.6);
      expect(l.resetAt, isNotNull);
      expect(l.billingResetAt, isNotNull);
    });

    test('clamps fraction 0..1 and defaults to 0', () {
      final over = UsageLimits.fromJson({
        'remaining': {'fraction': 1.8},
      });
      expect(over.remainingFraction, 1.0);
      final none = UsageLimits.fromJson({});
      expect(none.remainingFraction, 0.0);
      expect(none.resetAt, isNull);
    });
  });

  group('AiStatus', () {
    test('parses', () {
      final st = AiStatus.fromJson({
        'provider': 'dashscope',
        'model': 'qwen3.8-max',
        'status': 'online',
        'latencyMs': 120,
        'updatedAt': '2099-01-01T00:00:00.000Z',
      });
      expect(st.provider, 'dashscope');
      expect(st.status, 'online');
      expect(st.latencyMs, 120);
      expect(st.updatedAt, isNotNull);
    });
  });

  group('AccountUsageSettings', () {
    test('parses', () {
      final a = AccountUsageSettings.fromJson({
        'automaticRecharge': true,
        'plan': 'Gratis',
      });
      expect(a.automaticRecharge, true);
      expect(a.plan, 'Gratis');
    });

    test('defaults', () {
      final a = AccountUsageSettings.fromJson({});
      expect(a.automaticRecharge, false);
      expect(a.plan, 'Gratis');
    });
  });
}
