/// Session-level capital protection — no exchange secrets.
class CapitalProtection {
  CapitalProtection({
    this.maxDailyLossR = 3.0,
    this.maxConsecutiveLosses = 3,
    this.cooldownAfterLosses = const Duration(hours: 2),
    this.maxOpenExposureQuote = 0,
  });

  final double maxDailyLossR;
  final int maxConsecutiveLosses;
  final Duration cooldownAfterLosses;
  final double maxOpenExposureQuote;

  double realizedRToday = 0;
  int consecutiveLosses = 0;
  DateTime? cooldownUntil;
  double openExposureQuote = 0;
  DateTime dayKey = DateTime.now();

  void _rollDay(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    final k = DateTime(dayKey.year, dayKey.month, dayKey.day);
    if (d != k) {
      dayKey = now;
      realizedRToday = 0;
      consecutiveLosses = 0;
    }
  }

  void recordOutcome({required bool win, required double rMultiple}) {
    final now = DateTime.now();
    _rollDay(now);
    realizedRToday += rMultiple;
    if (win) {
      consecutiveLosses = 0;
    } else {
      consecutiveLosses++;
      if (consecutiveLosses >= maxConsecutiveLosses) {
        cooldownUntil = now.add(cooldownAfterLosses);
      }
    }
  }

  void setOpenExposure(double quote) => openExposureQuote = quote;

  /// Returns null if OK, otherwise block reason.
  String? blockReason({DateTime? now}) {
    final t = now ?? DateTime.now();
    _rollDay(t);
    if (cooldownUntil != null && t.isBefore(cooldownUntil!)) {
      return 'COOLDOWN after consecutive losses until $cooldownUntil';
    }
    if (realizedRToday <= -maxDailyLossR) {
      return 'MAX DAILY LOSS reached (${realizedRToday.toStringAsFixed(2)}R)';
    }
    if (maxOpenExposureQuote > 0 && openExposureQuote > maxOpenExposureQuote) {
      return 'MAX OPEN EXPOSURE exceeded';
    }
    return null;
  }

  bool get allowsTrade => blockReason() == null;
}
