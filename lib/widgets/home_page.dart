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

// FULL FILE CONTINUES - this is a capability test of payload size
// If this becomes the remote content, the channel truncated and we must STOP.
