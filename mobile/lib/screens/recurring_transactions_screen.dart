import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/recurring_transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import '../widgets/money_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sure_note.dart';
import 'cash_flow_screen.dart' show AccessTokenLoader;
import 'recurring_transaction_form_screen.dart';

/// Recurring bills, subscriptions and income: active ones by next date, the
/// rest below. Each can be switched active/inactive or deleted, and new
/// monthly ones added.
class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final RecurringTransactionsService? service;
  final AccessTokenLoader? accessTokenLoader;

  /// Defaults to [AuthProvider.logout], like the other screens.
  final Future<void> Function(BuildContext context)? onUnauthorized;

  @override
  State<RecurringTransactionsScreen> createState() => _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState extends State<RecurringTransactionsScreen> {
  late final RecurringTransactionsService _service =
      widget.service ?? RecurringTransactionsService();

  bool _loading = true;
  bool _failed = false;
  List<RecurringTransaction> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader(context);
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _handleUnauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler(context);
    await context.read<AuthProvider>().logout();
  }

  Future<void> _load() async {
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) return _handleUnauthorized();

    final result = await _service.getAll(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _handleUnauthorized();

    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      if (!_failed) _items = result['recurring_transactions'] as List<RecurringTransaction>;
    });
  }

  /// Runs a write, then reloads on success or shows [failureText].
  Future<void> _write(
    Future<Map<String, dynamic>> Function(String token) action,
    String Function(String error) failureText,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) return _handleUnauthorized();

    final result = await action(token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _handleUnauthorized();
    if (result['success'] == true) return _load();
    messenger.showSnackBar(SnackBar(content: Text(failureText(result['error'].toString()))));
  }

  Future<void> _showActions(RecurringTransaction item) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.displayName, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: Icon(item.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
              title: Text(item.isActive ? l.recurringMarkInactive : l.recurringMarkActive),
              onTap: () => Navigator.pop(context, 'toggle'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: palette.destructive),
              title: Text(l.commonDelete, style: TextStyle(color: palette.destructive)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    if (choice == 'toggle') {
      await _write(
        (token) => _service.setActive(accessToken: token, id: item.id, active: !item.isActive),
        l.recurringUpdateFailed,
      );
    } else if (choice == 'delete' && await _confirmDelete(item)) {
      await _write(
        (token) => _service.delete(accessToken: token, id: item.id),
        l.recurringDeleteFailed,
      );
    }
  }

  Future<bool> _confirmDelete(RecurringTransaction item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.recurringDeleteTitle),
          content: Text(dl.recurringDeleteContent(item.displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: SureColors.of(context).palette.destructive,
              ),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _showCreateForm() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecurringTransactionFormScreen(service: _service),
    );
    if (created == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = _items.where((r) => r.isActive).toList()
      ..sort((a, b) {
        final ad = a.nextExpectedDate, bd = b.nextExpectedDate;
        if (ad == null || bd == null) return ad == null ? (bd == null ? 0 : 1) : -1;
        return ad.compareTo(bd);
      });
    final others = _items.where((r) => !r.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.recurringTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateForm,
        tooltip: l.recurringAdd,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            SureSpacing.xl,
            SureSpacing.md,
            SureSpacing.xl,
            SureSpacing.huge * 2,
          ),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SureSpacing.huge * 2),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed && _items.isEmpty)
              SureNote(
                text: l.recurringLoadFailed,
                action: SureButton(
                  label: l.commonTryAgain,
                  onPressed: _load,
                  leading: const SureIcon(SureIcons.refresh, size: SureIconSize.sm),
                ),
              )
            else if (_items.isEmpty)
              SureNote(text: l.recurringEmpty)
            else ...[
              if (active.isNotEmpty)
                SureListGroup(
                  header: l.recurringActiveHeader,
                  children: [for (final item in active) _row(context, item)],
                ),
              if (active.isNotEmpty && others.isNotEmpty) const SizedBox(height: SureSpacing.xxxl),
              if (others.isNotEmpty)
                SureListGroup(
                  header: l.recurringInactiveHeader,
                  children: [for (final item in others) _row(context, item)],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, RecurringTransaction item) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    final details = <String>[
      if (!item.isActive)
        _statusLabel(l, item.status)
      else if (item.nextExpectedDate != null)
        l.recurringNext(DateFormat.MMMd(locale).format(item.nextExpectedDate!)),
      if (item.accountName != null) item.accountName!,
    ];

    return SureListRow(
      key: ValueKey('recurring_${item.id}'),
      title: item.displayName,
      subtitle: details.isEmpty ? null : details.join(' · '),
      trailing: Text(
        MoneyMasker.mask(item.amount, hidden: hidden),
        style: SureMoney.tabular(
          theme.textTheme.titleSmall?.copyWith(
            fontWeight: SureTokens.weightMedium,
            color: item.isIncome ? palette.success : palette.textPrimary,
          ),
        ),
      ),
      onTap: () => _showActions(item),
    );
  }

  static String _statusLabel(AppLocalizations l, String status) {
    switch (status) {
      case 'suggested':
        return l.recurringStatusSuggested;
      case 'paused':
        return l.recurringStatusPaused;
      case 'ended':
        return l.recurringStatusEnded;
      default:
        return l.recurringStatusInactive;
    }
  }
}
