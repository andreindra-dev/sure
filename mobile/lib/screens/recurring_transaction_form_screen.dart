import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/amount_parser.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_segmented_control.dart';

/// Bottom sheet that creates a monthly recurring expense or income on an
/// account. Pops `true` once the server created it.
class RecurringTransactionFormScreen extends StatefulWidget {
  const RecurringTransactionFormScreen({super.key, this.service});

  final RecurringTransactionsService? service;

  @override
  State<RecurringTransactionFormScreen> createState() => _RecurringTransactionFormScreenState();
}

class _RecurringTransactionFormScreenState extends State<RecurringTransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  late final RecurringTransactionsService _service =
      widget.service ?? RecurringTransactionsService();

  bool _isIncome = false;
  Account? _account;
  DateTime _nextDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _localeName() =>
      Localizations.maybeLocaleOf(context)?.toString() ?? Intl.getCurrentLocale();

  String? _validateAmount(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l.transactionFormAmountRequiredPrompt;
    final double amount;
    try {
      amount = AmountParser.parse(value, locale: _localeName()).value;
    } on FormatException {
      return l.transactionFormAmountInvalidNumber;
    }
    // Direction comes from the expense/income toggle, not the sign.
    return amount <= 0 ? l.transactionFormAmountTooSmall : null;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) setState(() => _nextDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authProvider = context.read<AuthProvider>();
    final account = _account!;
    final amount = AmountParser.canonicalize(_amountController.text, locale: _localeName());

    setState(() => _isSubmitting = true);
    final token = await authProvider.getValidAccessToken();
    if (token == null) {
      await authProvider.logout();
      return;
    }

    final result = await _service.create(
      accessToken: token,
      name: _nameController.text.trim(),
      // The API stores money out as positive and money in as negative.
      amount: _isIncome ? '-$amount' : amount,
      currency: account.currency,
      accountId: account.id,
      nextExpectedDate: _nextDate,
      notes: _notesController.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.recurringCreated)));
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l.recurringCreateFailed(result['error'].toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = context.watch<AccountsProvider>().accounts;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: SureSpacing.xxl,
        right: SureSpacing.xxl,
        top: SureSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + SureSpacing.xxl,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.recurringAdd, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: SureSpacing.lg),
                SureSegmentedControl<bool>(
                  selected: _isIncome,
                  onChanged: (value) => setState(() => _isIncome = value),
                  segments: [
                    SureSegment(value: false, label: l.transactionFormTypeExpense),
                    SureSegment(value: true, label: l.transactionFormTypeIncome),
                  ],
                ),
                const SizedBox(height: SureSpacing.xl),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: '${l.recurringNameLabel} *'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? l.recurringNameRequired : null,
                ),
                const SizedBox(height: SureSpacing.xl),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${l.transactionFormAmountLabel} *',
                    suffixText: _account?.currency,
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: SureSpacing.xl),
                DropdownButtonFormField<Account>(
                  // `value`, not `initialValue`: CI builds with Flutter 3.32.
                  value: _account,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: '${l.recurringAccountLabel} *'),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(value: account, child: Text(account.name)),
                  ],
                  onChanged: (account) => setState(() => _account = account),
                  validator: (account) => account == null ? l.recurringAccountRequired : null,
                ),
                const SizedBox(height: SureSpacing.xl),
                InkWell(
                  onTap: _selectDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.recurringNextDateLabel,
                      prefixIcon: const Icon(Icons.calendar_today),
                      helperText: l.recurringMonthlyHint,
                    ),
                    child: Text(DateFormat.yMMMd(_localeName()).format(_nextDate)),
                  ),
                ),
                const SizedBox(height: SureSpacing.xl),
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(labelText: l.updateBalanceNotesLabel),
                ),
                if (accounts.isEmpty) ...[
                  const SizedBox(height: SureSpacing.lg),
                  Text(l.recurringNoAccounts, style: TextStyle(color: palette.destructive)),
                ],
                const SizedBox(height: SureSpacing.xl),
                SureButton(
                  label: l.recurringSave,
                  onPressed: _isSubmitting ? null : _submit,
                  loading: _isSubmitting,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
