import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/market_data.dart';
import 'services/ai_analyst.dart';
import 'services/scanner_service.dart';
import 'services/tabdeal_api.dart';

const ownerUsername = 'Siavashmorad';

void main() => runApp(const SignalApp());

class SignalApp extends StatefulWidget {
  const SignalApp({super.key});
  @override
  State<SignalApp> createState() => _SignalAppState();
}

class _SignalAppState extends State<SignalApp> {
  bool dark = true, english = false, logged = false, ready = false;
  String? sessionUsername;
  String? sessionPassword;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      logged = prefs.getBool('logged') ?? false;
      dark = prefs.getBool('dark') ?? true;
      english = prefs.getBool('english') ?? false;
      ready = true;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', false);
    if (mounted) setState(() { logged = false; sessionUsername = null; sessionPassword = null; });
  }

  void _login(String username, String password) {
    setState(() { sessionUsername = username; sessionPassword = password; logged = true; });
  }

  Future<void> _toggleTheme() async {
    setState(() => dark = !dark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark', dark);
  }

  Future<void> _toggleLanguage() async {
    setState(() => english = !english);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('english', english);
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF18C8A0),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF07110F) : const Color(0xFFF4F8F7),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF07110F) : const Color(0xFFF4F8F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: isDark ? 0 : 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        color: isDark ? const Color(0xFF101D1A) : Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0D1916) : const Color(0xFFF8FBFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return MaterialApp(theme: _theme(Brightness.dark), home: const Scaffold(body: Center(child: CircularProgressIndicator())));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: english ? 'Crypto Signal Scanner' : 'اسکنر سیگنال کریپتو',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: logged
          ? HomePage(english: english, dark: dark, aiUsername: sessionUsername, aiPassword: sessionPassword, onLang: _toggleLanguage, onTheme: _toggleTheme, onLogout: _logout)
          : LoginPage(english: english, dark: dark, onLogin: _login, onTheme: _toggleTheme),
    );
  }
}

class LoginPage extends StatefulWidget {
  final bool english, dark;
  final void Function(String, String) onLogin;
  final VoidCallback onTheme;
  const LoginPage({super.key, required this.english, required this.dark, required this.onLogin, required this.onTheme});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: ownerUsername);
  final password = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> login() async {
    setState(() { error = null; loading = true; });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (username.text.trim() != ownerUsername || password.text.length < 6) {
      setState(() { loading = false; error = widget.english ? 'Username or password is invalid.' : 'نام کاربری یا رمز عبور صحیح نیست.'; });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', true);
    if (mounted) setState(() => loading = false);
    widget.onLogin(username.text.trim(), password.text);
  }

  @override
  void dispose() { username.dispose(); password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary.withOpacity(.14), Theme.of(context).scaffoldBackgroundColor, cs.secondary.withOpacity(.08)])),
        child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(children: [
          Align(alignment: Alignment.topRight, child: IconButton(onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded))),
          Container(width: 92, height: 92, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [cs.primary, cs.secondary]), boxShadow: [BoxShadow(color: cs.primary.withOpacity(.3), blurRadius: 28)]), child: const Icon(Icons.radar_rounded, size: 48, color: Colors.white)),
          const SizedBox(height: 20),
          Text(en ? 'Crypto Signal Scanner' : 'اسکنر سیگنال کریپتو', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(en ? 'Private • Signal only • Tabdeal market data' : 'خصوصی • فقط سیگنال • داده واقعی بازار تبدیل', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(.65))),
          const SizedBox(height: 24),
          Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
            TextField(controller: username, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: en ? 'Username' : 'نام کاربری', prefixIcon: const Icon(Icons.person_rounded))),
            const SizedBox(height: 14),
            TextField(controller: password, textDirection: TextDirection.ltr, obscureText: true, decoration: InputDecoration(labelText: en ? 'Password' : 'رمز عبور', prefixIcon: const Icon(Icons.lock_rounded))),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: loading ? null : login, icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login_rounded), label: Text(loading ? (en ? 'Signing in...' : 'در حال ورود...') : (en ? 'Sign in' : 'ورود')))),
            const SizedBox(height: 12),
            Text(en ? 'No exchange orders are ever sent from this app.' : 'این برنامه هیچ سفارش معاملاتی به صرافی ارسال نمی‌کند.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]))),
        ]))))),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  const HomePage({super.key, required this.english, required this.dark, required this.aiUsername, required this.aiPassword, required this.onLang, required this.onTheme, required this.onLogout});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final scanner = ScannerService(TabdealApi());
  final ai = AiAnalystService();
  final history = <MarketSignal>[];
  bool loading = false;
  String timeframe = '15m';
  String? status;
  List<MarketSignal> signals = [];
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

  Future<void> scan() async {
    if (loading) return;
    setState(() { loading = true; status = null; });
    try {
      final result = await scanner.scanAll(timeframe: duration, maxConcurrency: 4);
      if (!mounted) return;
      setState(() {
        signals = result;
        loading = false;
        status = result.isEmpty ? (widget.english ? 'No confirmed setup found.' : 'سیگنال تأییدشده‌ای پیدا نشد.') : (widget.english ? '${result.length} ranked opportunities found.' : '${result.length} فرصت رتبه‌بندی‌شده پیدا شد.');
        for (final item in result.take(20)) {
          if (!history.any((h) => h.symbol == item.symbol && h.timestamp.difference(item.timestamp).inMinutes.abs() < 2)) history.add(item);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { loading = false; status = widget.english ? 'Market data unavailable. Check internet and retry.' : 'داده بازار در دسترس نیست؛ اینترنت را بررسی و دوباره تلاش کنید.'; });
    }
  }

  Future<void> analyzeWithAi(MarketSignal signal) async {
    if (aiLoading) return;
    setState(() { selectedForAi = signal; aiAnalysis = null; aiError = null; aiLoading = true; });
    try {
      if (widget.aiUsername == null || widget.aiPassword == null) throw StateError(widget.english ? 'Please sign in again to use AI analysis.' : 'برای تحلیل هوش مصنوعی دوباره وارد شوید.');
      final result = await ai.analyze(signal: signal, username: widget.aiUsername!, password: widget.aiPassword!);
      if (!mounted) return;
      setState(() { aiAnalysis = result; aiLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { aiLoading = false; aiError = e.toString().replaceFirst('Bad state: ', ''); });
    }
  }

  String money(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(5);
    return value.toStringAsFixed(8);
  }

  @override
  void dispose() { ai.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.secondary]), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.radar_rounded, color: Colors.white, size: 22)), const SizedBox(width: 11), Expanded(child: Text(en ? 'Signal Scanner' : 'اسکنر سیگنال', style: const TextStyle(fontWeight: FontWeight.w900)))]),
          actions: [IconButton(onPressed: widget.onTheme, tooltip: en ? 'Theme' : 'پوسته', icon: Icon(widget.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded)), IconButton(onPressed: widget.onLang, tooltip: en ? 'فارسی' : 'English', icon: const Icon(Icons.translate_rounded)), IconButton(onPressed: widget.onLogout, tooltip: en ? 'Logout' : 'خروج', icon: const Icon(Icons.logout_rounded))],
        ),
        body: RefreshIndicator(onRefresh: scan, child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
          _HeroBanner(en: en, signalCount: signals.length, onScan: loading ? null : scan, loading: loading),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: DropdownButtonFormField<String>(value: timeframe, decoration: InputDecoration(labelText: en ? 'Timeframe' : 'تایم‌فریم', prefixIcon: const Icon(Icons.schedule_rounded)), items: ['1m', '5m', '15m', '1h'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: loading ? null : (v) => setState(() => timeframe = v ?? timeframe))), const SizedBox(width: 12), SizedBox(width: 118, child: FilledButton.icon(onPressed: loading ? null : scan, icon: const Icon(Icons.radar_rounded), label: Text(en ? 'Scan' : 'اسکن')))]))),
          if (status != null) Card(child: ListTile(leading: Icon(signals.isEmpty ? Icons.info_outline_rounded : Icons.check_circle_rounded, color: signals.isEmpty ? cs.secondary : cs.primary), title: Text(status!), subtitle: Text(en ? 'Only confirmed setups are shown.' : 'فقط فرصت‌های تأییدشده نمایش داده می‌شوند.'))),
          if (signals.isNotEmpty) ...[
            _SectionTitle(title: en ? 'Top ranked opportunities' : 'برترین فرصت‌های رتبه‌بندی‌شده', subtitle: en ? 'Ranking combines confidence, risk/reward and volatility quality.' : 'رتبه‌بندی بر اساس اطمینان، ریسک/سود و کیفیت نوسان انجام می‌شود.'),
            ...signals.take(3).toList().asMap().entries.map((e) => _RankedSignalCard(rank: e.key + 1, signal: e.value, en: en, money: money, featured: e.key == 0, onAi: ai.configured ? () => analyzeWithAi(e.value) : null)),
            if (signals.length > 3) ...[
              const SizedBox(height: 6),
              _SectionTitle(title: en ? 'Other confirmed signals' : 'سایر سیگنال‌های تأییدشده'),
              ...signals.skip(3).take(12).toList().asMap().entries.map((e) => _CompactSignalCard(rank: e.key + 4, signal: e.value, en: en, money: money, onAi: ai.configured ? () => analyzeWithAi(e.value) : null)),
            ],
          ],
          if (selectedForAi != null || aiLoading || aiError != null) _AiAnalysisCard(en: en, signal: selectedForAi, analysis: aiAnalysis, loading: aiLoading, error: aiError),
          if (!ai.configured) Card(child: ListTile(leading: const Icon(Icons.psychology_rounded), title: Text(en ? 'AI analyst is optional' : 'تحلیل‌گر هوش مصنوعی اختیاری است'), subtitle: Text(en ? 'Configure the private backend at build time. No AI key is stored in the APK.' : 'بک‌اند خصوصی هنگام Build معرفی می‌شود؛ هیچ کلید AI داخل APK ذخیره نمی‌شود.'))),
          if (history.isNotEmpty) Card(child: ExpansionTile(title: Text(en ? 'Recent signal history (${history.length})' : 'تاریخچه اخیر سیگنال‌ها (${history.length})'), children: history.take(20).map((s) => ListTile(leading: _SideBadge(side: s.side), title: Text('${s.symbol}  •  ${s.side}'), subtitle: Text('${en ? 'Confidence' : 'اطمینان'} ${s.confidence.toStringAsFixed(0)}%  •  ${s.timeframe}  •  RR ${s.riskReward.toStringAsFixed(1)}')).toList())),
          Card(child: ListTile(leading: Icon(Icons.shield_rounded, color: cs.primary), title: Text(en ? 'Manual execution only' : 'اجرای کاملاً دستی'), subtitle: Text(en ? 'The app only suggests. You decide and open every position manually.' : 'برنامه فقط پیشنهاد می‌دهد؛ تصمیم و باز کردن هر پوزیشن کاملاً دستی است.'))),
        ])),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final bool en, loading; final int signalCount; final VoidCallback? onScan;
  const _HeroBanner({required this.en, required this.signalCount, required this.onScan, required this.loading});
  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary.withOpacity(.95), cs.secondary.withOpacity(.82)]), boxShadow: [BoxShadow(color: cs.primary.withOpacity(.18), blurRadius: 28, offset: const Offset(0, 12))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.auto_awesome_rounded, color: Colors.white), const SizedBox(width: 8), Text(en ? 'LIVE MARKET RADAR' : 'رادار زنده بازار', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.1))]),
      const SizedBox(height: 10),
      Text(en ? 'Find the strongest confirmed setups.' : 'قوی‌ترین فرصت‌های تأییدشده را پیدا کن.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(en ? 'Real Tabdeal public market data • ranked automatically' : 'داده عمومی واقعی تبدیل • رتبه‌بندی خودکار', style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: Text('${en ? 'Confirmed signals' : 'سیگنال تأییدشده'}: $signalCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))), OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), onPressed: onScan, icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded), label: Text(loading ? (en ? 'Scanning' : 'اسکن') : (en ? 'Scan now' : 'اسکن')))]),
    ]));
  }
}

class _SectionTitle extends StatelessWidget {
  final String title; final String? subtitle;
  const _SectionTitle({required this.title, this.subtitle});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 5), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall))]));
}

class _RankedSignalCard extends StatelessWidget {
  final int rank; final MarketSignal signal; final bool en, featured; final String Function(double) money; final VoidCallback? onAi;
  const _RankedSignalCard({required this.rank, required this.signal, required this.en, required this.money, required this.featured, required this.onAi});
  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLong = signal.side == 'LONG';
    final accent = isLong ? cs.primary : cs.error;
    return Card(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: accent.withOpacity(featured ? .5 : .18), width: featured ? 1.5 : 1)), child: Padding(padding: const EdgeInsets.all(17), child: Column(children: [
      Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withOpacity(.12), shape: BoxShape.circle), child: Center(child: Text('#$rank', style: TextStyle(color: accent, fontWeight: FontWeight.w900)))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(signal.symbol, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text(signal.timeframe, style: Theme.of(context).textTheme.bodySmall)])), _SideBadge(side: signal.side), const SizedBox(width: 8), _ConfidenceBadge(value: signal.confidence)]),
      const SizedBox(height: 14),
      Row(children: [_Metric(label: en ? 'Entry' : 'ورود', value: money(signal.entry)), _Metric(label: en ? 'Stop' : 'حد ضرر', value: money(signal.stopLoss)), _Metric(label: 'TP1', value: money(signal.tp1))]),
      const SizedBox(height: 8),
      Row(children: [_Metric(label: 'TP2', value: money(signal.tp2)), _Metric(label: 'TP3', value: money(signal.tp3)), _Metric(label: 'RR', value: '1:${signal.riskReward.toStringAsFixed(1)}')]),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (signal.confidence / 100).clamp(0, 1), minHeight: 7, backgroundColor: accent.withOpacity(.10), color: accent)),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: Text('${en ? 'ATR' : 'نوسان ATR'}: ${money(signal.atr)}', style: Theme.of(context).textTheme.bodySmall)), if (onAi != null) OutlinedButton.icon(onPressed: onAi, icon: const Icon(Icons.psychology_rounded, size: 18), label: Text(en ? 'AI' : 'AI'))]),
    ]))));
  }
}

class _CompactSignalCard extends StatelessWidget {
  final int rank; final MarketSignal signal; final bool en; final String Function(double) money; final VoidCallback? onAi;
  const _CompactSignalCard({required this.rank, required this.signal, required this.en, required this.money, required this.onAi});
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13), child: Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, shape: BoxShape.circle), child: Center(child: Text('#$rank', style: const TextStyle(fontWeight: FontWeight.w800)))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${signal.symbol} • ${signal.side}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${money(signal.entry)}  •  RR 1:${signal.riskReward.toStringAsFixed(1)}', style: Theme.of(context).textTheme.bodySmall)])), _ConfidenceBadge(value: signal.confidence), if (onAi != null) IconButton(onPressed: onAi, icon: const Icon(Icons.psychology_rounded))]));
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric({required this.label, required this.value});
  @override Widget build(BuildContext context) => Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 3), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))]));
}

class _ConfidenceBadge extends StatelessWidget {
  final double value; const _ConfidenceBadge({required this.value});
  @override Widget build(BuildContext context) { final cs = Theme.of(context).colorScheme; final color = value >= 85 ? cs.primary : value >= 75 ? cs.secondary : cs.tertiary; return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)), child: Text('${value.toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
}

class _SideBadge extends StatelessWidget {
  final String side; const _SideBadge({required this.side});
  @override Widget build(BuildContext context) { final cs = Theme.of(context).colorScheme; final long = side == 'LONG'; final color = long ? cs.primary : cs.error; return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)), child: Text(side, style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
}

class _AiAnalysisCard extends StatelessWidget {
  final bool en; final MarketSignal? signal; final AiAnalysis? analysis; final bool loading; final String? error;
  const _AiAnalysisCard({required this.en, required this.signal, required this.analysis, required this.loading, required this.error});
  @override Widget build(BuildContext context) {
    if (loading) return Card(child: const ListTile(leading: CircularProgressIndicator(), title: Text('AI'), subtitle: Text('در حال تحلیل داده‌های سیگنال...')));
    if (error != null) return Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(en ? 'AI analysis unavailable' : 'تحلیل AI در دسترس نیست'), subtitle: Text(error!)));
    final a = analysis; if (a == null) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.psychology_rounded), const SizedBox(width: 8), Expanded(child: Text(en ? 'AI Market Analyst' : 'تحلیل‌گر هوش مصنوعی بازار', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))), _ConfidenceBadge(value: a.confidence.toDouble())]), if (signal != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text('${signal!.symbol} • ${signal!.side}')), const SizedBox(height: 12), Text(a.summary), const Divider(height: 24), _AiLine(label: en ? 'Recommendation' : 'پیشنهاد', value: a.recommendation), _AiLine(label: en ? 'Trend' : 'روند', value: a.trend), _AiLine(label: en ? 'Momentum' : 'مومنتوم', value: a.momentum), _AiLine(label: en ? 'Risk' : 'ریسک', value: a.riskLevel), _AiLine(label: en ? 'Quality' : 'کیفیت سیگنال', value: a.signalQuality), if (a.reasons.isNotEmpty) ...[const SizedBox(height: 8), Text(en ? 'Reasons' : 'دلایل', style: const TextStyle(fontWeight: FontWeight.w800)), ...a.reasons.map((r) => Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $r')))], const SizedBox(height: 10), Text(en ? 'AI is advisory only. You execute manually.' : 'AI فقط پیشنهاد تحلیلی می‌دهد و اجرای معامله کاملاً دستی است.', style: Theme.of(context).textTheme.bodySmall)])));
  }
}

class _AiLine extends StatelessWidget { final String label, value; const _AiLine({required this.label, required this.value}); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 105, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))), Expanded(child: Text(value))])); }
