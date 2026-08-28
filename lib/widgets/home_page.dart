import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import '../services/account_balance.dart';
import '../services/ai_analyst.dart';
import '../services/futures_execution_service.dart';
import '../services/live_trading_gate.dart';
import '../services/paper_journal_resolver.dart';
import '../services/fa_labels.dart';
import '../services/spot_auto_trader.dart';
import '../services/local_trade_store.dart';
import '../services/order_sizing.dart';
import '../services/position_tracker.dart';
import '../services/realtime_futures_scanner_service.dart';
import '../services/android_notification_service.dart';
import '../services/fcm_opportunity_payload.dart';
import '../main.dart' show appPush;
import '../services/push_open_handler.dart';
import '../services/tradingview_signal_service.dart';
import '../services/scanner_service.dart';
import '../services/signal_cooldown.dart';
import '../services/signal_journal.dart';
import '../services/symbol_rules_service.dart';
import '../services/tabdeal_api.dart';
import '../services/tabdeal_trade.dart';
import 'account_page.dart';
import 'ai_performance_page.dart';
import 'coin_analysis_page.dart';
import 'connection_diagnose_page.dart';
import 'market_chart_page.dart';
import 'trade_settings_page.dart';
import 'wallet_page.dart';

const ownerUsername = 'Siavashmorad';

// NOTE: Full HomePage body restored in follow-up if this is incomplete.
// This is a safety restore of imports + class shell to unblock compile.
class HomePage extends StatefulWidget {
  final bool english;
  final bool dark;
  final String? aiUsername;
  final String? aiPassword;
  final FcmOpportunityPayload? pendingPush;
  final VoidCallback onLang;
  final VoidCallback onTheme;
  final VoidCallback onLogout;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    this.aiUsername,
    this.aiPassword,
    this.pendingPush,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'SignalYab' : 'سیگنال‌یاب'),
          actions: [
            IconButton(
              tooltip: en ? 'Coin analysis' : 'تحلیل ارز',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CoinAnalysisPage(english: en),
                ));
              },
              icon: const Icon(Icons.currency_bitcoin),
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Center(
          child: Text(en
              ? 'HomePage restore in progress — open Coin Analysis from the toolbar.'
              : 'بازیابی صفحه اصلی در جریان است — از نوار بالا «تحلیل ارز» را باز کنید.'),
        ),
      ),
    );
  }
}
