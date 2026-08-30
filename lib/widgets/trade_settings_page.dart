import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_monitor_service.dart';
import '../services/local_trade_store.dart';
import '../services/tabdeal_trade.dart';
import 'mt5_analysis_page.dart';

class TradeSettingsPage extends StatefulWidget {
  final bool english;
  const TradeSettingsPage({super.key, required this.english});

  @override
  State<TradeSettingsPage> createState() => _TradeSettingsPageState();
}

class _TradeSettingsPageState extends State<TradeSettingsPage> {
  final store = LocalTradeStore();
  final keyCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '0.001');
  bool live = false;
  bool backgroundMonitor = true;
  bool loading = true;
  bool testing = false;
  String? message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    keyCtrl.text = await store.apiKey();
    secretCtrl.text = await store.apiSecret();
    qtyCtrl.text = (await store.defaultQty()).toString();
    live = await store.liveEnabled();
    final prefs = await SharedPreferences.getInstance();
    backgroundMonitor = prefs.getBool(kBackgroundMonitorEnabled) ?? true;
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.001;
    await store.save(
      apiKey: keyCtrl.text,
      apiSecret: secretCtrl.text,
      defaultQty: qty > 0 ? qty : 0.001,
      liveEnabled: live,
    );
    try {
      await BackgroundMonitorService.setEnabled(backgroundMonitor);
    } catch (_) {}
    if (!mounted) return;
    setState(() => message = widget.english
        ? 'Saved on this phone'
        : 'تنظیمات روی این گوشی ذخیره شد');
  }

  Future<void> _test() async {
    setState(() {
      testing = true;
      message = null;
    });
    try {
      final client = TabdealTradeClient(
        apiKey: keyCtrl.text.trim(),
        apiSecret: secretCtrl.text.trim(),
      );
      final acc = await client.account();
      client.dispose();
      if (!mounted) return;
      setState(() {
        testing = false;
        message = widget.english
            ? 'Keys OK — account reachable'
            : 'کلیدها درست است — حساب در دسترس';
      });
      acc;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        testing = false;
        message = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    secretCtrl.dispose();
    qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(en ? 'Trading on phone' : 'تنظیمات معامله')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    en ? 'Tabdeal (execution)' : 'تبدیل (اجرای سفارش)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        en
                            ? 'No server needed. API key stays on this phone. You must Approve every order.'
                            : 'بدون سرور. کلید API فقط روی همین گوشی می‌ماند. قبل از هر سفارش باید تأیید کنید.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                    decoration: InputDecoration(
                      labelText: en ? 'Tabdeal API Key' : 'کلید API تبدیل',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: en ? 'Tabdeal API Secret' : 'رمز Secret تبدیل',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: en
                          ? 'Default order size (coin amount)'
                          : 'حجم پیش‌فرض سفارش (مقدار کوین)',
                      border: const OutlineInputBorder(),
                      helperText: en
                          ? 'Example: 0.001 BTC — start small'
                          : 'مثال: ۰.۰۰۱ بیت‌کوین — با حجم کم شروع کنید',
                    ),
                  ),
                  SwitchListTile(
                    title:
                        Text(en ? 'Enable LIVE orders' : 'فعال‌سازی سفارش واقعی'),
                    subtitle: Text(en
                        ? 'Off = only signals. On = real money after Approve.'
                        : 'خاموش = فقط سیگنال. روشن = پول واقعی بعد از تأیید.'),
                    value: live,
                    onChanged: (v) => setState(() => live = v),
                  ),
                  SwitchListTile(
                    title: Text(en
                        ? 'Background opportunity monitoring'
                        : 'پایش فرصت‌ها در پس‌زمینه'),
                    subtitle: Text(en
                        ? 'While the app process is alive: slower polls + alerts. Never places orders. Stops if OS force-stops the app.'
                        : 'تا وقتی برنامه در حافظه زنده است: پایش کندتر + اعلان. هیچ سفارشی ثبت نمی‌کند. با Force-stop قطع می‌شود.'),
                    value: backgroundMonitor,
                    onChanged: (v) => setState(() => backgroundMonitor = v),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(message!),
                    ),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(en ? 'Save Tabdeal settings' : 'ذخیره تنظیمات تبدیل'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: testing ? null : _test,
                    icon: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user),
                    label: Text(en ? 'Test Tabdeal connection' : 'تست اتصال تبدیل'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    en ? 'MT5 (read-only analysis)' : 'MT5 (فقط تحلیل)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.show_chart),
                      title: Text(en
                          ? 'MetaAPI / MT5 connection'
                          : 'اتصال MetaAPI / MT5'),
                      subtitle: Text(en
                          ? 'Enter token + Account ID later. Read-only — no MT5 orders.'
                          : 'توکن و شناسه حساب را بعداً وارد کنید. فقط‌خواندنی — بدون سفارش MT5.'),
                      trailing:
                          Icon(en ? Icons.chevron_right : Icons.chevron_left),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Mt5AnalysisPage(english: en),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    en
                        ? 'Get Tabdeal key from Tabdeal → Settings → API. Restrict IP if possible. Never share keys.'
                        : 'کلید تبدیل را از تبدیل → تنظیمات → API بگیرید. در صورت امکان IP محدود کنید. کلید را به کسی ندهید.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }
}
