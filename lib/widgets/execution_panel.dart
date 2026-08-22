import 'package:flutter/material.dart';
import '../services/execution_service.dart';

/// Pending approvals: user must explicitly approve before any open/close runs.
class ExecutionPanel extends StatefulWidget {
  final bool english;
  final String? username;
  final String? password;
  final ExecutionService execution;

  const ExecutionPanel({
    super.key,
    required this.english,
    required this.username,
    required this.password,
    required this.execution,
  });

  @override
  State<ExecutionPanel> createState() => _ExecutionPanelState();
}

class _ExecutionPanelState extends State<ExecutionPanel> {
  String? modeNote;
  String? mode;
  List<Map<String, dynamic>> pending = [];
  List<Map<String, dynamic>> positions = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (widget.username == null ||
        widget.password == null ||
        !widget.execution.configured) {
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final status = await widget.execution.status(
        username: widget.username!,
        password: widget.password!,
      );
      final p = await widget.execution.pending(
        username: widget.username!,
        password: widget.password!,
      );
      // positions via same base path — reuse status client pattern through pending only if needed
      if (!mounted) return;
      setState(() {
        mode = status['mode']?.toString();
        modeNote = status['note']?.toString();
        pending = p;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _confirmApprove(Map<String, dynamic> action) async {
    final en = widget.english;
    final id = action['id']?.toString() ?? '';
    final symbol = action['symbol']?.toString() ?? '';
    final act = action['action']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(en ? 'Confirm execution' : 'تأیید اجرا'),
        content: Text(
          en
              ? 'Approve $act on $symbol?\nOnly after OK will the order run (paper or live depending on server mode).'
              : 'تأیید $act برای $symbol؟\nفقط بعد از تأیید، اجرا انجام می‌شود (paper یا live بسته به تنظیم سرور).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(en ? 'Cancel' : 'انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(en ? 'Approve' : 'تأیید و اجرا'),
          ),
        ],
      ),
    );
    if (ok != true || widget.username == null || widget.password == null) return;
    try {
      await widget.execution.approve(
        username: widget.username!,
        password: widget.password!,
        actionId: id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(en ? 'Approved and executed' : 'تأیید و اجرا شد'),
          ),
        );
      }
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> action) async {
    final id = action['id']?.toString() ?? '';
    if (widget.username == null || widget.password == null) return;
    try {
      await widget.execution.reject(
        username: widget.username!,
        password: widget.password!,
        actionId: id,
      );
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    if (!widget.execution.configured) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(en
              ? 'Execution backend not configured in this APK'
              : 'بک‌اند اجرا در این APK تنظیم نشده'),
          subtitle: Text(en
              ? 'Set AI_BACKEND_URL at build time to enable approve-gated trading.'
              : 'برای فعال‌سازی معامله با تأیید، AI_BACKEND_URL را هنگام Build تنظیم کنید.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    en ? 'Approval-gated execution' : 'اجرا با تأیید شما',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (mode != null)
              Text(
                en ? 'Mode: $mode' : 'حالت: $mode',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (modeNote != null && modeNote!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(modeNote!),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!loading && pending.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(en
                    ? 'No pending actions. Propose open/close from a signal card.'
                    : 'درخواست معلقی نیست. از کارت سیگنال درخواست باز/بستن بدهید.'),
              ),
            ...pending.map((a) {
              final symbol = a['symbol']?.toString() ?? '';
              final act = a['action']?.toString() ?? '';
              final side = a['side']?.toString() ?? '';
              final qty = a['quantity'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('$act • $symbol • $side'),
                subtitle: Text('qty: $qty'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _reject(a),
                      child: Text(en ? 'Reject' : 'رد'),
                    ),
                    FilledButton(
                      onPressed: () => _confirmApprove(a),
                      child: Text(en ? 'Approve' : 'تأیید'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
