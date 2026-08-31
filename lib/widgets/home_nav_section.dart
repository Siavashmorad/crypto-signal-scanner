import 'package:flutter/material.dart';

import 'coin_analysis_page.dart';
import 'focus_coin_page.dart';
import 'smart_market_radar_page.dart';

/// Compact navigation cards for Home — does not rewrite HomePage body.
/// MT5 / MetaAPI intentionally omitted (user cannot access MetaAPI login).
class HomeNavSection extends StatelessWidget {
  final bool english;
  const HomeNavSection({super.key, required this.english});

  @override
  Widget build(BuildContext context) {
    final en = english;
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.center_focus_strong),
            title: Text(en ? 'Focus Mode' : 'حالت فوکوس'),
            subtitle: Text(en
                ? 'One strong coin · candles · start now or switch'
                : 'یک ارز قوی · کندل‌ها · الان شروع کن یا تعویض'),
            trailing: Icon(en ? Icons.chevron_right : Icons.chevron_left),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FocusCoinPage(english: en),
              ));
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: Text(en ? 'Coin Analysis' : 'تحلیل ارز'),
            subtitle: Text(en
                ? 'Multi-TF score, radar, best opportunity'
                : 'تحلیل چندبازه، رادار، بهترین فرصت فعلی'),
            trailing: Icon(en ? Icons.chevron_right : Icons.chevron_left),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CoinAnalysisPage(english: en),
              ));
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.radar),
            title: Text(en ? 'Smart Market Radar' : 'رادار هوشمند بازار'),
            subtitle: Text(en
                ? 'Ranked opportunities, freshness, risk/reward, spot-safe action'
                : 'رتبه‌بندی فرصت‌ها، تازگی داده، ریسک/بازده و اقدام امن برای اسپات'),
            trailing: Icon(en ? Icons.chevron_right : Icons.chevron_left),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SmartMarketRadarPage(english: en),
              ));
            },
          ),
        ),
      ],
    );
  }
}
