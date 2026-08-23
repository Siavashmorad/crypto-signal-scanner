import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/market_data.dart';
import 'services/ai_analyst.dart';
import 'services/local_trade_store.dart';
import 'services/scanner_service.dart';
import 'services/tabdeal_api.dart';
import 'services/tabdeal_trade.dart';
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
                      Text(
                        'سیگنال‌یاب',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.english
                            ? 'Scan + trade from your phone (no server)'
                            : 'اسکن و معامله از گوشی — بدون سرور',
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
                          child: Text(
                            error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
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
  final ai = AiAnalystService();
  final tradeStore = LocalTradeStore();
  final history = <MarketSignal>[];
  bool loading = false;
  bool checkingLink = true;
  bool tabdealLinked = false;
  bool tradeReady = false;
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
    setState(() {
      tradeReady = has;
      liveOn = live && has;
    });
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
              ? 'Connected to Tabdeal (${api.activeHost})'
              : 'متصل به تبدیل (${api.activeHost})')
          : (widget.english
              ? 'Cannot reach Tabdeal. Check internet.'
              : 'اتصال به تبدیل برقرار نشد. اینترنت را چک کنید.');
    });
  }

  Future<void> scan() async {
    if (loading) return;
    setState(() {
      loading = true;
      status = widget.english
          ? 'Scanning top USDT markets...'
          : 'در حال اسکن بازارهای USDT...';
    });
    final started = DateTime.now();
    try {
      final result = await scanner.scanAll(
        timeframe: duration,
        maxConcurrency: 10,
        maxSymbols: 30,
        maxSignals: 12,
      );
      final secs = DateTime.now().difference(started).inSeconds;
      if (!mounted) return;
      setState(() {
        signals = result;
        marketCount = result.map((e) => e.symbol).toSet().length;
        loading = false;
        tabdealLinked = true;
        status = result.isEmpty
            ? (widget.english
                ? 'No setup (${secs}s)'
                : 'سیگنال تأییدشده نبود ($secsث)')
            : (widget.english
                ? '${result.length} setups in ${secs}s'
                : '${result.length} فرصت در $secsث');
        for (final item in result.take(20)) {
          if (!history.any((h) =>
              h.symbol == item.symbol &&
              h.timestamp.difference(item.timestamp).inMinutes.abs() < 2)) {
            history.add(item);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        tabdealLinked = false;
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

  /// Phone → Tabdeal. Approve dialog first. No server.
  Future<void> placeOnPhone(MarketSignal signal, {required bool isOpen}) async {
    final en = widget.english;
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!has || !live) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'Trading not ready' : 'معامله آماده نیست'),
          content: Text(en
              ? 'Save Tabdeal API key and enable LIVE in settings.'
              : 'در تنظیمات، کلید API تبدیل را ذخیره و سفارش واقعی را روشن کنید.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(en ? 'Later' : 'بعداً')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(en ? 'Settings' : 'تنظیمات')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TradeSettingsPage(english: en),
        ));
        await _refreshTradeStatus();
      }
      return;
    }

    final qty = await tradeStore.defaultQty();
    final isLong = signal.side.toUpperCase() == 'LONG';
    // Spot: open long = BUY, close long = SELL; open short = SELL (needs inventory/margin)
    final side = isOpen
        ? (isLong ? 'BUY' : 'SELL')
        : (isLong ? 'SELL' : 'BUY');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(en
            ? (isOpen ? 'Approve OPEN (real money)' : 'Approve CLOSE (real money)')
            : (isOpen ? 'تأیید باز کردن (پول واقعی)' : 'تأیید بستن (پول واقعی)')),
        content: Text(en
            ? '${signal.symbol}\n$side MARKET qty $qty\nEntry ~ ${signal.entry}\nThis sends a real order to Tabdeal from your phone.'
            : '${signal.symbol}\n$side مارکت حجم $qty\nورود تقریبی ${signal.entry}\nسفارش واقعی از همین گوشی به تبدیل ارسال می‌شود.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(en ? 'Cancel' : 'انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(en ? 'Approve & send' : 'تأیید و ارسال')),
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
        quantity: qty,
      );
      client.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'Order sent: ${res['orderId'] ?? res['order_id'] ?? 'ok'}'
            : 'سفارش ارسال شد: ${res['orderId'] ?? res['order_id'] ?? 'موفق'}'),
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
              tooltip: en ? 'Trading settings' : 'تنظیمات معامله',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TradeSettingsPage(english: en),
                ));
                await _refreshTradeStatus();
              },
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            IconButton(
              onPressed: checkingLink ? null : _checkTabdeal,
              icon: Icon(
                tabdealLinked ? Icons.cloud_done : Icons.cloud_off,
                color: checkingLink
                    ? null
                    : (tabdealLinked ? Colors.green : Colors.red),
              ),
            ),
            IconButton(
              onPressed: widget.onTheme,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              onPressed: widget.onLang,
              icon: const Icon(Icons.language),
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
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
                      ? (en ? 'Checking...' : 'در حال اتصال...')
                      : (tabdealLinked
                          ? (en ? 'Live market data' : 'داده بازار زنده')
                          : (en ? 'Offline' : 'قطع'))),
                  subtitle: Text(status ?? ''),
                ),
              ),
              Card(
                color: liveOn
                    ? Colors.green.withOpacity(0.1)
                    : Colors.blueGrey.withOpacity(0.08),
                child: ListTile(
                  leading: Icon(
                    liveOn ? Icons.bolt : Icons.bolt_outlined,
                    color: liveOn ? Colors.green : null,
                  ),
                  title: Text(liveOn
                      ? (en
                          ? 'LIVE trading ready on this phone'
                          : 'معامله واقعی از این گوشی آماده است')
                      : (en
                          ? 'Trading off — open wallet settings'
                          : 'معامله خاموش — تنظیمات کیف پول')),
                  subtitle: Text(en
                      ? 'No server. Keys stay on phone. Approve every order.'
                      : 'بدون سرور. کلید روی گوشی. هر سفارش با تأیید شما.'),
                  trailing: const Icon(Icons.chevron_left),
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
                      Text(
                        en ? 'Fast USDT scanner' : 'اسکن سریع USDT',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: timeframe,
                              decoration: InputDecoration(
                                labelText: en ? 'Timeframe' : 'تایم‌فریم',
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
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    en
                        ? 'Best opportunities ($marketCount)'
                        : 'بهترین فرصت‌ها ($marketCount)',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...signals.take(10).map(
                      (signal) => _SignalCard(
                        signal: signal,
                        en: en,
                        money: money,
                        onAi: () => analyzeWithAi(signal),
                        onOpen: () => placeOnPhone(signal, isOpen: true),
                        onClose: () => placeOnPhone(signal, isOpen: false),
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(en
                      ? 'Profit is never guaranteed'
                      : 'سود تضمینی وجود ندارد'),
                  subtitle: Text(en
                      ? 'Start with tiny size. Crypto is high risk.'
                      : 'با حجم خیلی کم شروع کنید. کریپتو پرریسک است.'),
                ),
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
  final String Function(double) money;
  final VoidCallback? onAi;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  const _SignalCard({
    required this.signal,
    required this.en,
    required this.money,
    required this.onAi,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    signal.symbol,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Chip(label: Text(signal.side)),
                ],
              ),
              const Divider(),
              _row(en ? 'Confidence' : 'اطمینان',
                  '${signal.confidence.toStringAsFixed(0)}%'),
              _row(en ? 'Entry' : 'ورود', money(signal.entry)),
              _row(en ? 'Stop Loss' : 'حد ضرر', money(signal.stopLoss)),
              _row('TP1', money(signal.tp1)),
              _row('TP2', money(signal.tp2)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onAi,
                  icon: const Icon(Icons.psychology),
                  label: Text(en ? 'Analyst' : 'تحلیلگر'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.lock_open),
                      label: Text(en ? 'OPEN' : 'باز'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onClose,
                      icon: const Icon(Icons.lock),
                      label: Text(en ? 'CLOSE' : 'بستن'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
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
      return Card(
        child: ListTile(
          leading: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(en ? 'Analyzing...' : 'در حال تحلیل...'),
        ),
      );
    }
    if (error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(en ? 'Analysis failed' : 'تحلیل ناموفق'),
          subtitle: Text(error!),
        ),
      );
    }
    final result = analysis;
    if (result == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(en ? 'Analyst' : 'تحلیلگر',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (signal != null) Text('${signal!.symbol} • ${signal!.side}'),
            const SizedBox(height: 8),
            Text(result.summary),
            const Divider(),
            Text('${en ? 'Recommendation' : 'پیشنهاد'}: ${result.recommendation}'),
            Text('${en ? 'Trend' : 'روند'}: ${result.trend}'),
            Text('${en ? 'Risk' : 'ریسک'}: ${result.riskLevel}'),
            Text('${en ? 'Confidence' : 'اطمینان'}: ${result.confidence}%'),
          ],
        ),
      ),
    );
  }
}
