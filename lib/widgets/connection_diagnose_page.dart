import 'package:flutter/material.dart';
import '../services/binance_public.dart';
import '../services/tabdeal_api.dart';

class ConnectionDiagnosePage extends StatefulWidget {
  final bool english;
  final TabdealApi api;
  const ConnectionDiagnosePage({
    super.key,
    required this.english,
    required this.api,
  });

  @override
  State<ConnectionDiagnosePage> createState() => _ConnectionDiagnosePageState();
}

class _ConnectionDiagnosePageState extends State<ConnectionDiagnosePage> {
  bool running = false;
  List<HostProbeResult> results = [];
  bool? binanceOk;

  Future<void> run() async {
    setState(() {
      running = true;
      results = [];
      binanceOk = null;
    });
    final r = await widget.api.diagnose();
    final b = await BinancePublic().ping();
    if (!mounted) return;
    setState(() {
      results = r;
      binanceOk = b;
      running = false;
    });
  }

  @override
  void initState() {
    super.initState();
    run();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'Connection test' : 'تست اتصال'),
          actions: [
            IconButton(
              onPressed: running ? null : run,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              en
                  ? 'If Tabdeal fails, turn OFF foreign VPN. Iranian mobile data usually works best.'
                  : 'اگر تبدیل قطع است، VPN خارجی را خاموش کنید. معمولاً اینترنت موبایل ایران بهتر وصل می‌شود.',
            ),
            const SizedBox(height: 12),
            if (running)
              const Center(child: CircularProgressIndicator())
            else ...[
              ...results.map((r) => Card(
                    color: r.ok
                        ? Colors.green.withOpacity(0.12)
                        : Colors.red.withOpacity(0.08),
                    child: ListTile(
                      leading: Icon(
                        r.ok ? Icons.check_circle : Icons.error,
                        color: r.ok ? Colors.green : Colors.red,
                      ),
                      title: Text('${r.host}${r.path}'),
                      subtitle: Text('${r.detail}\n${r.ms} ms'),
                      isThreeLine: true,
                    ),
                  )),
              Card(
                color: (binanceOk == true)
                    ? Colors.green.withOpacity(0.12)
                    : Colors.orange.withOpacity(0.1),
                child: ListTile(
                  leading: Icon(
                    binanceOk == true ? Icons.check_circle : Icons.warning,
                    color: binanceOk == true ? Colors.green : Colors.orange,
                  ),
                  title: Text(en
                      ? 'Binance public (scan fallback)'
                      : 'بایننس عمومی (پشتیبان اسکن)'),
                  subtitle: Text(binanceOk == true
                      ? (en ? 'Reachable' : 'در دسترس')
                      : (en ? 'Not reachable' : 'در دسترس نیست')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                en
                    ? 'Trading always needs Tabdeal API. Scan can use Binance only as temporary fallback.'
                    : 'معامله همیشه به API تبدیل نیاز دارد. اسکن موقتاً می‌تواند از بایننس استفاده کند.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
