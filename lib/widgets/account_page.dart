import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_trade_store.dart';

/// SignalYab LOCAL ACCOUNT — not Tabdeal, not server authentication.
class AccountPage extends StatefulWidget {
  final bool english;
  final String currentUsername;
  final VoidCallback onLogout;

  const AccountPage({
    super.key,
    required this.english,
    required this.currentUsername,
    required this.onLogout,
  });

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool emergencyStop = false;
  bool autoTransfer = false;
  bool preferFutures = false;
  bool realtimeScanner = false;
  bool realtimeNotify = true;
  bool androidOsNotify = true;
  bool backgroundPolling = true;
  String notifyMinQuality = 'A';
  bool tradingViewEnabled = false;
  String tradingViewBackendUrl = '';
  bool hasKeys = false;
  String username = '';
  final store = LocalTradeStore();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    username = widget.currentUsername;
    _userCtrl.text = widget.currentUsername;
    _load();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    hasKeys = await store.hasKeys();
    setState(() {
      emergencyStop = p.getBool('emergency_stop') ?? false;
      autoTransfer = p.getBool('auto_transfer_futures') ?? false;
      preferFutures = p.getBool('prefer_futures_execution') ?? false;
      realtimeScanner = p.getBool('realtime_futures_scanner') ?? false;
      realtimeNotify = p.getBool('realtime_notify') ?? true;
      androidOsNotify = p.getBool('android_os_notify') ?? true;
      backgroundPolling = p.getBool('realtime_background_polling') ?? true;
      notifyMinQuality = p.getString('realtime_notify_min_quality') ?? 'A';
      tradingViewEnabled = p.getBool('tradingview_enabled') ?? false;
      tradingViewBackendUrl = p.getString('tradingview_backend_url') ?? '';
      username = p.getString('signalyab_username') ?? widget.currentUsername;
      _userCtrl.text = username;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
    await _load();
  }

  Future<void> _setString(String key, String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, v);
    await _load();
  }

  Future<void> _saveUsername() async {
    final name = _userCtrl.text.trim();
    if (name.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('signalyab_username', name);
    setState(() => username = name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.english
          ? 'Username updated (local)'
          : 'نام کاربری به‌روز شد (محلی)'),
    ));
  }

  Future<void> _savePassword() async {
    final raw = _passCtrl.text;
    if (raw.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(widget.english ? 'Min 4 characters' : 'حداقل ۴ کاراکتر'),
      ));
      return;
    }
    final hash = raw.codeUnits
        .fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff)
        .toRadixString(16);
    final p = await SharedPreferences.getInstance();
    await p.setString('signalyab_password_hash', hash);
    _passCtrl.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          widget.english ? 'Local password updated' : 'رمز محلی به‌روز شد'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(en ? 'My Account' : 'حساب من')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: emergencyStop ? Colors.red.shade50 : null,
              child: ListTile(
                title: Text(
                  en
                      ? (emergencyStop
                          ? 'EMERGENCY STOP ACTIVE'
                          : 'TRADING ENABLED')
                      : (emergencyStop
                          ? 'توقف اضطراری فعال'
                          : 'معاملات فعال'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: emergencyStop ? Colors.red.shade900 : null,
                  ),
                ),
                subtitle: Text(en
                    ? 'SignalYab LOCAL ACCOUNT — not Tabdeal, not server auth'
                    : 'حساب محلی سیگنال‌یاب — نه تبدیل، نه احراز هویت سرور'),
              ),
            ),
            const SizedBox(height: 8),
            Text(en ? 'Local username' : 'نام کاربری محلی',
                style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    decoration: InputDecoration(
                      hintText: en ? 'Username' : 'نام کاربری',
                    ),
                  ),
                ),
                TextButton(
                    onPressed: _saveUsername,
                    child: Text(en ? 'Save' : 'ذخیره')),
              ],
            ),
            const SizedBox(height: 8),
            Text(en ? 'Local password' : 'رمز محلی',
                style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: en ? 'New password' : 'رمز جدید',
                    ),
                  ),
                ),
                TextButton(
                    onPressed: _savePassword,
                    child: Text(en ? 'Save' : 'ذخیره')),
              ],
            ),
            const Divider(),
            ListTile(
              title: Text(en ? 'Tabdeal API' : 'API تبدیل'),
              subtitle: Text(hasKeys
                  ? (en
                      ? 'Configured (secure storage)'
                      : 'تنظیم شده (ذخیره امن)')
                  : (en ? 'Not connected' : 'متصل نیست')),
            ),
            SwitchListTile(
              title: Text(en ? 'Emergency Stop' : 'توقف معاملات'),
              subtitle: Text(en
                  ? 'Blocks all new Spot and Futures orders'
                  : 'همه سفارش‌های جدید Spot و Futures مسدود می‌شوند'),
              value: emergencyStop,
              onChanged: (v) => _setBool('emergency_stop', v),
            ),
            SwitchListTile(
              title: Text(en ? 'Prefer Futures execution' : 'اجرای فیوچرز'),
              subtitle: Text(en
                  ? 'When ON, live opens use Futures path'
                  : 'در صورت فعال بودن، مسیر فیوچرز برای باز کردن استفاده می‌شود'),
              value: preferFutures,
              onChanged: (v) => _setBool('prefer_futures_execution', v),
            ),
            SwitchListTile(
              title: Text(en
                  ? 'Auto transfer (default OFF)'
                  : 'انتقال خودکار (پیش‌فرض خاموش)'),
              subtitle: Text(en
                  ? 'Only exact required margin when enabled'
                  : 'فقط حاشیه مورد نیاز در صورت فعال بودن'),
              value: autoTransfer,
              onChanged: (v) => _setBool('auto_transfer_futures', v),
            ),
            const Divider(),
            Text(en ? 'Futures Market Watcher' : 'پایش بازار فیوچرز',
                style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              title: Text(en
                  ? 'Real-Time Scanner (default OFF)'
                  : 'اسکنر لحظه‌ای (پیش‌فرض خاموش)'),
              subtitle: Text(en
                  ? 'Auto-scan while app process is alive. No fake signals.'
                  : 'پایش خودکار وقتی فرآیند برنامه زنده است. سیگنال جعلی نمی‌سازد.'),
              value: realtimeScanner,
              onChanged: (v) => _setBool('realtime_futures_scanner', v),
            ),
            SwitchListTile(
              title: Text(en ? 'In-app alerts' : 'هشدار داخل برنامه'),
              subtitle: Text(en
                  ? 'SnackBar for high quality; fingerprint prevents spam'
                  : 'SnackBar برای کیفیت بالا؛ اثر انگشت جلوی تکرار را می‌گیرد'),
              value: realtimeNotify,
              onChanged: (v) => _setBool('realtime_notify', v),
            ),
            SwitchListTile(
              title: Text(en ? 'Android OS notification' : 'اعلان Android'),
              subtitle: Text(en
                  ? 'System tray for A/A+. Does not place orders.'
                  : 'اعلان سیستم برای A/A+. سفارش خودکار نمی‌فرستد.'),
              value: androidOsNotify,
              onChanged: (v) => _setBool('android_os_notify', v),
            ),
            SwitchListTile(
              title: Text(en
                  ? 'Background polling (process alive)'
                  : 'پایش پس‌زمینه (فرآیند زنده)'),
              subtitle: Text(en
                  ? 'Slower scan when app not visible. Stops if OS kills process. NOT 24/7.'
                  : 'اسکن کندتر وقتی برنامه دیده نمی‌شود. با کشته شدن فرآیند متوقف می‌شود. ۲۴/۷ نیست.'),
              value: backgroundPolling,
              onChanged: (v) => _setBool('realtime_background_polling', v),
            ),
            ListTile(
              title: Text(en ? 'Notify min quality' : 'حداقل کیفیت اعلان'),
              subtitle: Text(en
                  ? 'A+ only or A and A+'
                  : 'فقط A+ یا A و A+'),
              trailing: DropdownButton<String>(
                value: notifyMinQuality == 'A+' ? 'A+' : 'A',
                items: const [
                  DropdownMenuItem(value: 'A+', child: Text('A+')),
                  DropdownMenuItem(value: 'A', child: Text('A / A+')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _setString('realtime_notify_min_quality', v);
                  }
                },
              ),
            ),
            Text(
              en
                  ? 'When the Android process is killed, scanning stops. '
                      'No guaranteed 24/7. When no valid setup: NO VALID OPPORTUNITY.'
                  : 'وقتی فرآیند اندروید کشته شود، اسکن متوقف می‌شود. '
                      '۲۴/۷ تضمینی نیست. اگر فرصت معتبر نباشد: فرصت معتبری نیست.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              title: Text(en
                  ? 'TradingView alerts (backend)'
                  : 'هشدار TradingView (بک‌اند)'),
              subtitle: Text(en
                  ? 'Poll accepted TV webhooks. Never auto-trades.'
                  : 'دریافت هشدارهای TV تأییدشده. معامله خودکار نیست.'),
              value: tradingViewEnabled,
              onChanged: (v) => _setBool('tradingview_enabled', v),
            ),
            ListTile(
              title: Text(en ? 'Backend URL' : 'آدرس بک‌اند'),
              subtitle: Text(
                tradingViewBackendUrl.isEmpty
                    ? (en
                        ? 'Set after Render deploy (https://…onrender.com)'
                        : 'پس از Deploy روی Render تنظیم کنید')
                    : tradingViewBackendUrl,
              ),
              onTap: () async {
                final ctrl = TextEditingController(text: tradingViewBackendUrl);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(en ? 'Backend base URL' : 'آدرس پایه بک‌اند'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'https://your-service.onrender.com',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(en ? 'Cancel' : 'لغو')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(en ? 'Save' : 'ذخیره')),
                    ],
                  ),
                );
                if (ok == true) {
                  await _setString('tradingview_backend_url', ctrl.text.trim());
                }
                ctrl.dispose();
              },
            ),
            Text(
              en
                  ? 'TradingView webhook secret is only on the server (TRADINGVIEW_WEBHOOK_SECRET). '
                      'Alerts feed SignalYab validation — never direct orders.'
                  : 'رمز Webhook فقط روی سرور است. هشدارها فقط ورودی SignalYab هستند — سفارش مستقیم نمی‌زنند.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text(en ? 'Logout' : 'خروج',
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }
}
