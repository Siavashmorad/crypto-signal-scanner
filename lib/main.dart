import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/market_data.dart';
import 'services/ai_analyst.dart';
import 'services/local_trade_store.dart';
import 'services/order_sizing.dart';
import 'services/scanner_service.dart';
import 'services/symbol_rules_service.dart';
import 'services/tabdeal_api.dart';
import 'services/tabdeal_trade.dart';
import 'widgets/connection_diagnose_page.dart';
import 'widgets/market_chart_page.dart';
import 'widgets/trade_settings_page.dart';

const ownerUsername = 'Siavashmorad';

void main() => runApp(const SignalApp());

class SignalApp extends StatefulWidget {
  const SignalApp({super.key});
  @override
  State<SignalApp> createState() => _SignalAppState();
}

class _SignalAppState extends State<SignalApp> {
  bool dark = false, english = false, logged = false, ready = false;
  String? sessionUsername;
  String? sessionPassword;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      logged = prefs.getBool('logged') ?? false;
      ready = true;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', false);
    if (mounted) {
      setState(() {
        logged = false;
        sessionUsername = null;
        sessionPassword = null;
      });
    }
  }

  void _login(String username, String password) {
    setState(() {
      sessionUsername = username;
      sessionPassword = password;
      logged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: logged
          ? HomePage(
              english: english,
              dark: dark,
              aiUsername: sessionUsername,
              aiPassword: sessionPassword,
              onLang: () => setState(() => english = !english),
              onTheme: () => setState(() => dark = !dark),
              onLogout: _logout,
            )
          : LoginPage(english: english, onLogin: _login),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF5B4BDB),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardTheme(margin: EdgeInsets.symmetric(vertical: 6)),
      );
}

class LoginPage extends StatefulWidget {
  final bool english;
  final void Function(String username, String password) onLogin;
  const LoginPage({super.key, required this.english, required this.onLogin});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: ownerUsername);
  final password = TextEditingController();
  String? error;

  Future<void> login() async {
    if (username.text.trim() != ownerUsername || password.text.length < 6) {
      setState(() => error = widget.english
          ? 'Username or password is invalid.'
          : 'نام کاربری یا رمز عبور صحیح نیست.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', true);
    widget.onLogin(username.text.trim(), password.text);
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        child: Icon(Icons.candlestick_chart, size: 40),
                      ),
                      const SizedBox(height: 18),
                      Text('سیگنال‌یاب',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        widget.english
                            ? 'Scan + trade from phone'
                            : 'اسکن و معامله از گوشی',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: username,
                        decoration: InputDecoration(
                          labelText: widget.english ? 'Username' : 'نام کاربری',
                          prefixIcon: const Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: widget.english ? 'Password' : 'رمز عبور',
                          prefixIcon: const Icon(Icons.lock),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: login,
                          icon: const Icon(Icons.login),
                          label: Text(widget.english ? 'Sign in' : 'ورود'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    required this.aiUsername,
    required this.aiPassword,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final api = TabdealApi();
  late final scanner = ScannerService(api);
  late final rules = SymbolRulesService(api);
  final sizing = OrderSizingEngine();
  final ai = AiAnalystService();
  final tradeStore = LocalTradeStore();
  final history = <MarketSignal>[];
  final Map<String, Map<String, dynamic>> lastFills = {};
  bool loading = false;
  bool checkingLink = true;
  bool tabdealLinked = false;
  bool liveOn = false;
  String timeframe = '15m';
  String? status;
  List<MarketSignal> signals = [];
  int marketCount = 0;
  MarketSignal? selectedForAi;
  AiAnalysis? aiAnalysis;
  bool aiLoading = false;
  String? aiError;

  Duration get duration => switch (timeframe) {
        '1m' => const Duration(minutes: 1),
        '5m' => const Duration(minutes: 5),
        '1h' => const Duration(hours: 1),
        _ => const Duration(minutes: 15),
      };

  @override
  void initState() {
    super.initState();
    _checkTabdeal();
    _refreshTradeStatus();
  }

  Future<void> _refreshTradeStatus() async {
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!mounted) return;
    setState(() => liveOn = live && has);
  }

  Future<void> _openDiagnose() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ConnectionDiagnosePage(english: widget.english, api: api),
    ));
    await _checkTabdeal();
  }

  Future<void> _openChart(MarketSignal s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MarketChartPage(
        signal: s,
        api: api,
        english: widget.english,
        lastOrderFill: lastFills[s.symbol],
      ),
    ));
  }

  Future<void> _checkTabdeal() async {
    setState(() => checkingLink = true);
    final ok = await api.ping();
    if (!mounted) return;
    setState(() {
      tabdealLinked = ok;
      checkingLink = false;
      status = ok
          ? (widget.english
              ? 'Tabdeal OK (${api.activeHost})'
              : 'تبدیل وصل است (${api.activeHost})')
          : (widget.english
              ? 'Tabdeal offline — tap to diagnose'
              : 'تبدیل قطع — برای تست بزنید');
    });
  }

  Future<void> scan() async {
    if (loading) return;
    setState(() {
      loading = true;
      status = widget.english ? 'Scanning...' : 'در حال اسکن...';
    });
    final started = DateTime.now();
    try {
      final result = await scanner.scanAll(
        timeframe: duration,
        maxConcurrency: 8,
        maxSymbols: 20,
        maxSignals: 12,
      );
      final secs = DateTime.now().difference(started).inSeconds;
      final src = scanner.dataSource;
      if (!mounted) return;
      setState(() {
        signals = result;
        marketCount = result.map((e) => e.symbol).toSet().length;
        loading = false;
        tabdealLinked = src == 'tabdeal' || tabdealLinked;
        final srcLabel = src == 'tabdeal'
            ? (widget.english ? 'Tabdeal' : 'تبدیل')
            : src == 'binance'
                ? (widget.english ? 'Binance fallback' : 'پشتیبان بایننس')
                : '?';
        status = result.isEmpty
            ? (widget.english
                ? 'No setup (${secs}s) via $srcLabel'
                : 'سیگنال نبود ($secsث) از $srcLabel')
            : (widget.english
                ? '${result.length} setups in ${secs}s ($srcLabel)'
                : '${result.length} فرصت در $secsث ($srcLabel)');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        status = e.toString().replaceFirst('TabdealApiException: ', '');
      });
    }
  }

  Future<void> analyzeWithAi(MarketSignal signal) async {
    if (aiLoading) return;
    setState(() {
      selectedForAi = signal;
      aiAnalysis = null;
      aiError = null;
      aiLoading = true;
    });
    try {
      final result = await ai.analyze(
        signal: signal,
        username: widget.aiUsername ?? ownerUsername,
        password: widget.aiPassword ?? 'local',
      );
      if (!mounted) return;
      setState(() {
        aiAnalysis = result;
        aiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        aiLoading = false;
        aiError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> placeOnPhone(MarketSignal signal, {required bool isOpen}) async {
    final en = widget.english;
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!has || !live) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'Open wallet settings: API key + LIVE'
            : 'تنظیمات کیف پول: کلید API + سفارش واقعی'),
      ));
      return;
    }

    final configured = await tradeStore.defaultQty();
    final filters = await rules.filtersFor(signal.symbol);
    final size = sizing.compute(
      filters: filters,
      configuredQty: configured,
      currentPrice: signal.entry,
      // balance unknown without private call — skip unless user sets max risk via qty only
      availableQuote: 0,
      maxRiskQuote: 0,
    );

    if (!size.canSubmit) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'Cannot place order' : 'امکان ارسال سفارش نیست'),
          content: Text(size.message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(en ? 'OK' : 'باشه')),
          ],
        ),
      );
      return;
    }

    final isLong = signal.side.toUpperCase() == 'LONG';
    final side = isOpen
        ? (isLong ? 'BUY' : 'SELL')
        : (isLong ? 'SELL' : 'BUY');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(en ? 'Approve order' : 'تأیید سفارش'),
        content: Text(
          '${signal.symbol}  $side MARKET\n'
          '${en ? 'Requested' : 'درخواستی'}: ${size.requestedQty}\n'
          '${en ? 'Exchange min qty' : 'حداقل صرافی'}: ${size.minQty}\n'
          '${en ? 'Min notional' : 'حداقل ارزش'}: ${size.minNotional}\n'
          '${en ? 'Final qty' : 'حجم نهایی'}: ${size.finalQty}\n'
          '${en ? 'Approx value' : 'ارزش تقریبی'}: ${size.approxNotional.toStringAsFixed(2)}\n'
          '${size.message}\n\n'
          '${en ? 'Spot only — SHORT means SELL asset, not leveraged short.' : 'فقط اسپات — SHORT یعنی فروش دارایی، نه شورت اهرمی.'}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(en ? 'Cancel' : 'انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(en ? 'Send' : 'ارسال')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final client = TabdealTradeClient(
        apiKey: await tradeStore.apiKey(),
        apiSecret: await tradeStore.apiSecret(),
      );
      final res = await client.marketOrder(
        symbol: signal.symbol,
        side: side,
        quantity: size.finalQty,
      );
      client.dispose();
      lastFills[signal.symbol] = res;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${en ? 'Order' : 'سفارش'}: ${res['orderId'] ?? res['order_id'] ?? res['status'] ?? 'ok'}',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Bad state: ', '')),
      ));
    }
  }

  String money(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(5);
    return value.toStringAsFixed(8);
  }

  @override
  void dispose() {
    ai.dispose();
    super.dispose();
  }

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
              onPressed: _openDiagnose,
              icon: const Icon(Icons.network_check),
            ),
            IconButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TradeSettingsPage(english: en),
                ));
                await _refreshTradeStatus();
              },
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            IconButton(
              onPressed: widget.onTheme,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
                onPressed: widget.onLang, icon: const Icon(Icons.language)),
            IconButton(
                onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: scan,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: tabdealLinked
                    ? Colors.green.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.08),
                child: ListTile(
                  onTap: _openDiagnose,
                  leading: checkingLink
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          tabdealLinked ? Icons.link : Icons.link_off,
                          color: tabdealLinked ? Colors.green : Colors.orange,
                        ),
                  title: Text(checkingLink
                      ? (en ? 'Checking...' : 'در حال تست...')
                      : (tabdealLinked
                          ? (en ? 'Tabdeal connected' : 'تبدیل متصل')
                          : (en ? 'Tabdeal offline' : 'تبدیل قطع'))),
                  subtitle: Text(status ?? ''),
                ),
              ),
              Card(
                child: ListTile(
                  leading: Icon(liveOn ? Icons.bolt : Icons.bolt_outlined,
                      color: liveOn ? Colors.green : null),
                  title: Text(liveOn
                      ? (en ? 'LIVE ready' : 'معامله واقعی آماده')
                      : (en ? 'Trading off' : 'معامله خاموش')),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TradeSettingsPage(english: en),
                    ));
                    await _refreshTradeStatus();
                  },
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(en ? 'Scanner' : 'اسکنر',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: timeframe,
                              decoration: InputDecoration(
                                labelText: en ? 'TF' : 'تایم',
                              ),
                              items: ['1m', '5m', '15m', '1h']
                                  .map((x) => DropdownMenuItem(
                                      value: x, child: Text(x)))
                                  .toList(),
                              onChanged: loading
                                  ? null
                                  : (v) => setState(
                                      () => timeframe = v ?? timeframe),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: loading ? null : scan,
                              icon: const Icon(Icons.radar),
                              label: Text(
                                  loading ? '...' : (en ? 'Scan' : 'اسکن')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (signals.isNotEmpty) ...[
                Text(
                  en
                      ? 'Opportunities ($marketCount)'
                      : 'فرصت‌ها ($marketCount)',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                ...signals.take(10).map(
                      (s) => _SignalCard(
                        signal: s,
                        en: en,
                        money: money,
                        executed: lastFills.containsKey(s.symbol),
                        onChart: () => _openChart(s),
                        onAi: () => analyzeWithAi(s),
                        onOpen: () => placeOnPhone(s, isOpen: true),
                        onClose: () => placeOnPhone(s, isOpen: false),
                      ),
                    ),
              ],
              if (selectedForAi != null || aiLoading || aiError != null)
                _AiAnalysisCard(
                  en: en,
                  signal: selectedForAi,
                  analysis: aiAnalysis,
                  loading: aiLoading,
                  error: aiError,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final MarketSignal signal;
  final bool en;
  final bool executed;
  final String Function(double) money;
  final VoidCallback? onAi;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final VoidCallback? onChart;
  const _SignalCard({
    required this.signal,
    required this.en,
    required this.money,
    required this.onAi,
    required this.onOpen,
    required this.onClose,
    required this.onChart,
    this.executed = false,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(signal.symbol,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  Chip(
                    label: Text(executed
                        ? (en ? 'FILLED' : 'اجرا شده')
                        : signal.side),
                  ),
                ],
              ),
              Text('${en ? 'Conf' : 'اطمینان'}: ${signal.confidence.toStringAsFixed(0)}%'),
              Text('${en ? 'Entry' : 'ورود'}: ${money(signal.entry)}'),
              Text('SL: ${money(signal.stopLoss)}  TP1: ${money(signal.tp1)}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onChart,
                      icon: const Icon(Icons.show_chart),
                      label: Text(en ? 'Chart' : 'نمودار'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onAi,
                      icon: const Icon(Icons.psychology),
                      label: Text(en ? 'AI' : 'تحلیل'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onOpen,
                      child: Text(en ? 'OPEN' : 'باز'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      child: Text(en ? 'CLOSE' : 'بستن'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _AiAnalysisCard extends StatelessWidget {
  final bool en;
  final MarketSignal? signal;
  final AiAnalysis? analysis;
  final bool loading;
  final String? error;
  const _AiAnalysisCard({
    required this.en,
    required this.signal,
    required this.analysis,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Card(
          child: ListTile(
              leading: CircularProgressIndicator(), title: Text('...')));
    }
    if (error != null) {
      return Card(child: ListTile(title: Text(error!)));
    }
    final r = analysis;
    if (r == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.summary),
            Text('${r.recommendation} | ${r.trend} | ${r.riskLevel}'),
            Text('${en ? 'Source' : 'منبع'}: ${r.source}'),
          ],
        ),
      ),
    );
  }
}
