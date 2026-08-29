import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_signal_scanner/services/coin_analysis_service.dart';
import 'package:crypto_signal_scanner/services/fa_labels.dart';
import 'package:crypto_signal_scanner/services/tabdeal_api.dart';

void main() {
  group('CoinAnalysisService.normalizeInput', () {
    late CoinAnalysisService svc;

    setUp(() {
      svc = CoinAnalysisService(api: TabdealApi());
    });

    test('BTC → BTCUSDT', () {
      expect(svc.normalizeInput('BTC'), 'BTCUSDT');
    });

    test('btc → BTCUSDT', () {
      expect(svc.normalizeInput('btc'), 'BTCUSDT');
    });

    test('BTCUSDT stays', () {
      expect(svc.normalizeInput('BTCUSDT'), 'BTCUSDT');
    });

    test('eth_usdt → ETHUSDT', () {
      expect(svc.normalizeInput('eth_usdt'), 'ETHUSDT');
    });

    test('empty → empty', () {
      expect(svc.normalizeInput('  '), '');
    });
  });

  group('CoinDecisionFa', () {
    test('labels are Persian and SPOT-safe', () {
      expect(CoinDecision.buy.label, contains('خرید'));
      expect(CoinDecision.sell.label, contains('عدم خرید'));
      expect(CoinDecision.sell.spotActionFa, contains('عدم خرید'));
      expect(CoinDecision.buy.spotActionFa, contains('ورود'));
      expect(CoinDecision.wait.label, 'انتظار');
      expect(CoinDecision.noTrade.label, 'بدون معامله');
    });
  });

  group('CoinAnalysisResult history roundtrip', () {
    test('toHistoryJson / fromHistoryJson', () {
      final r = CoinAnalysisResult(
        symbol: 'BTCUSDT',
        decision: CoinDecision.buy,
        score: 92,
        confidence: 90,
        tierFa: 'فرصت بسیار قوی',
        regimeFa: 'روند صعودی',
        trendShortFa: 'صعودی',
        trendMidFa: 'صعودی',
        trendMainFa: 'صعودی',
        lastPrice: 65000,
        analyzedAt: DateTime.utc(2026, 8, 28, 12),
        dataAgeSeconds: 5,
        dataStale: false,
        dataInsufficient: false,
        reasonsFa: const [],
        noTradeReasonsFa: const [],
        timeframes: const [],
        supports: const [],
        resistances: const [],
        conflictAcrossTf: false,
        dataSource: 'tabdeal',
      );
      final j = r.toHistoryJson();
      final back = CoinAnalysisResult.fromHistoryJson(j);
      expect(back, isNotNull);
      expect(back!.symbol, 'BTCUSDT');
      expect(back.score, 92);
      expect(back.decision, CoinDecision.buy);
      expect(back.lastPrice, 65000);
    });
  });

  group('FaLabels.spotSide', () {
    test('LONG is buy, SHORT is wait for SPOT', () {
      expect(FaLabels.spotSide('LONG'), 'خرید اسپات');
      expect(FaLabels.spotSide('SHORT'), 'عدم خرید / انتظار');
      expect(FaLabels.spotSide('BUY'), 'خرید اسپات');
    });
  });
}
