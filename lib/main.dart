import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const ownerUsername = 'Siavashmorad';
const apiBase = 'https://api1.tabdeal.org';

void main() => runApp(const SignalApp());

class SignalApp extends StatefulWidget {
  const SignalApp({super.key});
  @override
  State<SignalApp> createState() => _SignalAppState();
}

class _SignalAppState extends State<SignalApp> {
  bool dark = false;
  bool english = false;
  bool logged = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => logged = prefs.getBool('logged') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: logged
          ? HomePage(
              english: english,
              dark: dark,
              onLang: () => setState(() => english = !english),
              onTheme: () => setState(() => dark = !dark),
              onLogout: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('logged', false);
                if (mounted) setState(() => logged = false);
              },
            )
          : LoginPage(english: english, onLogin: () => setState(() => logged = true)),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF5B4BDB),
      );
}

class LoginPage extends StatefulWidget {
  final bool english;
  final VoidCallback onLogin;
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
    widget.onLogin();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  children: [
                    const CircleAvatar(radius: 38, child: Icon(Icons.candlestick_chart, size: 38)),
                    const SizedBox(height: 18),
                    Text('Signal Scanner', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(en ? 'Private access' : 'ورود خصوصی و اختصاصی'),
                    const SizedBox(height: 26),
                    TextField(controller: username, decoration: InputDecoration(labelText: en ? 'Username' : 'نام کاربری', prefixIcon: const Icon(Icons.person))),
                    const SizedBox(height: 14),
                    TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: en ? 'Password' : 'رمز عبور', prefixIcon: const Icon(Icons.lock))),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(onPressed: login, icon: const Icon(Icons.login), label: Text(en ? 'Sign in' : 'ورود'))),
                    const SizedBox(height: 12),
                    Text(en ? 'Only the owner account is accepted.' : 'فقط حساب مالک برنامه پذیرفته می‌شود.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Signal {
  final String symbol, side, timeframe;
  final double score, entry, stop, takeProfit;
  Signal({required this.symbol, required this.side, required this.timeframe, required this.score, required this.entry, required this.stop, required this.takeProfit});
}

class HomePage extends StatefulWidget {
  final bool english, dark;
  final VoidCallback onLang, onTheme, onLogout;
  const HomePage({super.key, required this.english, required this.dark, required this.onLang, required this.onTheme, required this.onLogout});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool loading = false;
  String timeframe = '15m';
  double capital = 10000000;
  Signal? signal;
  String? status;
  final symbols = <String>['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT', 'ADAUSDT', 'SUIUSDT', 'PEPEUSDT'];

  Future<List<dynamic>> trades(String symbol) async {
    final uri = Uri.parse('$apiBase/r/api/v1/trades').replace(queryParameters: {'symbol': symbol, 'limit': '300'});
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> depth(String symbol) async {
    final uri = Uri.parse('$apiBase/r/api/v1/depth').replace(queryParameters: {'symbol': symbol, 'limit': '30'});
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> scan() async {
    setState(() { loading = true; signal = null; status = null; });
    final candidates = <Signal>[];
    for (final symbol in symbols) {
      try {
        final rows = await trades(symbol);
        if (rows.length < 30) continue;
        final prices = rows.map<double>((row) {
          final value = row is List ? row[0] : row['price'];
          return double.tryParse('$value') ?? 0;
        }).where((price) => price > 0).toList();
        if (prices.length < 30) continue;
        final entry = prices.last;
        final old = prices[prices.length ~/ 3];
        if (old <= 0) continue;
        final change = (entry - old) / old * 100;
        final book = await depth(symbol);
        double bid = 0, ask = 0;
        for (final row in (book['bids'] ?? const [])) { bid += double.tryParse('${row[1]}') ?? 0; }
        for (final row in (book['asks'] ?? const [])) { ask += double.tryParse('${row[1]}') ?? 0; }
        final imbalance = bid + ask == 0 ? 0.0 : (bid - ask) / (bid + ask);
        final side = change >= 0 && imbalance >= -0.15 ? 'LONG' : 'SHORT';
        final score = (50 + change.abs().clamp(0, 20) * 2 + imbalance * 25).clamp(0, 100).toDouble();
        final risk = entry * 0.006;
        final stop = side == 'LONG' ? entry - risk : entry + risk;
        final target = side == 'LONG' ? entry + risk * 2.5 : entry - risk * 2.5;
        if (score >= 62) candidates.add(Signal(symbol: symbol, side: side, timeframe: timeframe, score: score, entry: entry, stop: stop, takeProfit: target));
      } catch (_) {}
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    if (!mounted) return;
    setState(() {
      loading = false;
      signal = candidates.isEmpty ? null : candidates.first;
      status = candidates.isEmpty ? (widget.english ? 'No valid setup found.' : 'سیگنال معتبر پیدا نشد.') : (widget.english ? 'Market scan completed.' : 'اسکن بازار انجام شد.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Scaffold(
      appBar: AppBar(title: Text(en ? 'Signal Scanner' : 'اسکنر سیگنال'), actions: [
        IconButton(onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode)),
        IconButton(onPressed: widget.onLang, icon: const Icon(Icons.language)),
        IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
      ]),
      body: RefreshIndicator(
        onRefresh: scan,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(en ? 'Market scanner' : 'اسکن بازار', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: timeframe, decoration: InputDecoration(labelText: en ? 'Timeframe' : 'تایم‌فریم'), items: ['1m', '5m', '15m', '1h'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => timeframe = value!))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(initialValue: '10000000', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: en ? 'Capital (Toman)' : 'سرمایه (تومان)'), onChanged: (value) => capital = double.tryParse(value.replaceAll(',', '')) ?? capital)),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(onPressed: loading ? null : scan, icon: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar), label: Text(loading ? (en ? 'Scanning...' : 'در حال اسکن...') : (en ? 'Find best opportunity' : 'پیدا کردن بهترین فرصت')))),
          ]))),
          const SizedBox(height: 14),
          if (status != null && !loading) Card(child: ListTile(leading: Icon(signal == null ? Icons.block : Icons.check_circle), title: Text(status!))),
          if (signal != null) SignalCard(signal: signal!, english: en),
          const SizedBox(height: 10),
          Card(child: ListTile(leading: const Icon(Icons.shield_outlined), title: Text(en ? 'Signal-only mode' : 'حالت فقط سیگنال'), subtitle: Text(en ? 'No orders are sent to the exchange.' : 'هیچ سفارشی به صرافی ارسال نمی‌شود.'))),
        ]),
      ),
    );
  }
}

class SignalCard extends StatelessWidget {
  final Signal signal;
  final bool english;
  const SignalCard({super.key, required this.signal, required this.english});
  String number(double value) => value.toStringAsFixed(6);
  @override
  Widget build(BuildContext context) {
    final en = english;
    return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(signal.symbol, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Chip(label: Text(signal.side))]),
      Text('${en ? 'Timeframe' : 'تایم‌فریم'}: ${signal.timeframe}'),
      const Divider(height: 28),
      row(context, en ? 'Signal score' : 'امتیاز سیگنال', '${signal.score.toStringAsFixed(0)}/100'),
      row(context, en ? 'Entry' : 'نقطه ورود', number(signal.entry)),
      row(context, en ? 'Stop Loss' : 'حد ضرر', number(signal.stop)),
      row(context, en ? 'Take Profit' : 'حد سود', number(signal.takeProfit)),
      row(context, en ? 'Risk/Reward' : 'ریسک به سود', '1 : 2.5'),
    ])));
  }
  Widget row(BuildContext context, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]));
}
