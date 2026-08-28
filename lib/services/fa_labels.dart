/// Persian UI labels for SignalYab — user-facing strings only.
class FaLabels {
  static String side(String s) {
    switch (s.toUpperCase()) {
      case 'LONG':
      case 'BUY':
        return 'خرید';
      case 'SHORT':
      case 'SELL':
        return 'فروش';
      case 'WAIT':
        return 'صبر';
      case 'AVOID':
        return 'عدم ورود';
      default:
        return s;
    }
  }

  static String scoreTier(double score) {
    if (score >= 90) return 'فرصت بسیار قوی';
    if (score >= 80) return 'فرصت قوی';
    if (score >= 70) return 'قابل بررسی';
    if (score >= 60) return 'ضعیف';
    return 'عدم ورود';
  }

  static String quality(String q) {
    switch (q.toUpperCase()) {
      case 'A+':
        return 'عالی';
      case 'A':
        return 'قوی';
      case 'B':
        return 'قابل بررسی';
      case 'C':
        return 'ضعیف';
      case 'NO TRADE':
        return 'بدون معامله';
      default:
        return q;
    }
  }

  static String reason(String r) {
    final s = r.trim();
    final lower = s.toLowerCase();
    if (lower.contains('ema alignment bullish')) return 'هم‌راستایی میانگین متحرک صعودی';
    if (lower.contains('ema alignment bearish')) return 'هم‌راستایی میانگین متحرک نزولی';
    if (lower.contains('structure aligned')) return 'ساختار بازار هم‌جهت';
    if (lower.contains('volume confirmation')) {
      final m = RegExp(r'([\d.]+)x').firstMatch(s);
      final x = m?.group(1) ?? '';
      return 'تأیید حجم${x.isEmpty ? '' : ' ($x برابر)'}';
    }
    if (lower.contains('weak relative volume')) return 'حجم نسبی ضعیف';
    if (lower.contains('near support')) return 'نزدیک حمایت';
    if (lower.contains('near resistance')) return 'نزدیک مقاومت';
    if (lower.startsWith('regime ')) return 'وضعیت بازار: ${s.substring(7)}';
    if (lower.contains('risk/reward') || lower.contains('r/r')) {
      return 'نسبت سود به زیان مناسب';
    }
    if (lower.contains('macd')) return 'مکدی هم‌جهت';
    if (lower.contains('rsi')) return 'شاخص قدرت نسبی مناسب';
    if (lower.contains('trend')) return 'روند هم‌جهت';
    if (lower.contains('momentum')) return 'شتاب مناسب';
    if (s.contains('ساختار') || s.contains('داده')) return s;
    return s;
  }

  static List<String> reasons(Iterable<String> list) =>
      list.map(reason).toList();

  static String exitReason(String code) {
    switch (code.toUpperCase()) {
      case 'TP':
      case 'TAKE_PROFIT':
        return 'حد سود';
      case 'SL':
      case 'STOP_LOSS':
        return 'حد ضرر';
      case 'SIGNAL_INVALID':
        return 'ابطال سیگنال';
      case 'EMERGENCY':
        return 'شرایط اضطراری';
      case 'MANUAL':
        return 'خروج دستی';
      default:
        return code;
    }
  }

  static String pnlLabel(double pnl) => pnl >= 0 ? 'سود' : 'زیان';
}
