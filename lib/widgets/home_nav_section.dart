import 'package:flutter/material.dart';

import 'coin_analysis_page.dart';
import 'mt5_analysis_page.dart';

/// Compact navigation cards for Home — does not rewrite HomePage body.
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
            leading: const Icon(Icons.show_chart),
            title: Text(en ? 'MT5 Analysis' : 'تحلیل MT5'),
            subtitle: Text(en
                ? 'Analysis only — no order execution'
                : 'فقط تحلیل — بدون اجرای سفارش'),
            trailing: Icon(en ? Icons.chevron_right : Icons.chevron_left),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Mt5AnalysisPage(english: en),
              ));
            },
          ),
        ),
      ],
    );
  }
}
