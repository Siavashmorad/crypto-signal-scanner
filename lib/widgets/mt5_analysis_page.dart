import 'package:flutter/material.dart';

import '../services/mt5_analysis_provider.dart';

/// MT5 analysis-only screen. Never places Tabdeal or MT5 orders.
class Mt5AnalysisPage extends StatelessWidget {
  final bool english;
  const Mt5AnalysisPage({super.key, this.english = false});

  @override
  Widget build(BuildContext context) {
    final en = english;
    final provider = Mt5AnalysisProvider();
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'MT5 Analysis' : 'تحلیل MT5'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.blue.withOpacity(0.08),
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(en ? 'Analysis only' : 'فقط تحلیل'),
                subtitle: Text(en
                    ? 'MT5 does not place orders. Tabdeal remains the only execution path.'
                    : 'MT5 سفارش ثبت نمی‌کند. مسیر اجرا فقط تبدیل است.'),
              ),
            ),
            Card(
              child: ListTile(
                title: Text(en ? 'Provider' : 'ارائه‌دهنده'),
                subtitle: Text(provider.name),
              ),
            ),
            Card(
              child: ListTile(
                title: Text(en ? 'Status' : 'وضعیت'),
                subtitle: Text(provider.isAvailable
                    ? (en ? 'Bridge configured' : 'پل ارتباطی پیکربندی شده')
                    : (en
                        ? 'No bridge configured — analysis continues on Tabdeal'
                        : 'پل MT5 تنظیم نشده — تحلیل روی تبدیل ادامه دارد')),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  en
                      ? 'To enable external MT5 market data, configure a bridge URL in a future settings release. Until then this page is informational only.'
                      : 'برای داده خارجی MT5 باید پل ارتباطی در نسخه بعدی تنظیم شود. فعلاً این صفحه فقط اطلاع‌رسانی است و سفارش نمی‌سازد.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              en
                  ? 'No MT5 auto-execution. No guaranteed profit.'
                  : 'بدون اجرای خودکار MT5. سود تضمینی نیست.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
