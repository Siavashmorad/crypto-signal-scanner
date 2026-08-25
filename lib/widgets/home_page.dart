import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import '../services/account_balance.dart';
import '../services/ai_analyst.dart';
import '../services/futures_execution_service.dart';
import '../services/live_trading_gate.dart';
import '../services/local_trade_store.dart';
import '../services/order_sizing.dart';
import '../services/position_tracker.dart';
import '../services/realtime_futures_scanner_service.dart';
import '../services/android_notification_service.dart';
import '../services/fcm_opportunity_payload.dart';
import '../services/firebase_push_service.dart';
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
import 'connection_diagnose_page.dart';
import 'market_chart_page.dart';
import 'trade_settings_page.dart';
import 'wallet_page.dart';

part 'home_page_body.dart';

const ownerUsername = 'Siavashmorad';

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  final FcmOpportunityPayload? pendingPush;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
    this.aiUsername,
    this.aiPassword,
    this.pendingPush,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Implementation in part file home_page_body.dart
}
