import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/valuations_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/sure_button.dart';

/// Bottom sheet that records an account's balance on a date (a valuation).
/// Pops `true` once the server accepted it.
class UpdateBalanceScreen extends StatefulWidget {
  const UpdateBalanceScreen({super.key, required this.account, this.service});

  final Account account;
  final ValuationsService? service;

  @override
  State<UpdateBalanceScreen> createState() => _UpdateBalanceScreenState();
}

class _UpdateBalanceScreenState extends State<UpdateBalanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  late final ValuationsService _service =
      widget.service ?? ValuationsService();
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _localeName() =>
      Localizations.maybeLocaleOf(context)?.toString() ?? Intl.getCurrentLocale();

  String? _validateAmount(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l.transactionFormAmountRequiredPrompt;
    }
    try {
      AmountParser.parse(value, locale: _localeName());
    } on FormatException {
      return l.transactionFormAmountInvalidNumber;
    }
    return null;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authProvider = context.read<AuthProvider>();

    setState(() => _isSubmitting = true);
    final token = await authProvider.getValidAccessToken();
    if (token == null) {
      await authProvider.logout();
      return;
    }

    final result = await _service.createValuation(
      accessToken: token,
      accountId: widget.account.id,
      amount: AmountParser.canonicalize(_amountController.text, locale: _localeName()),
      date: DateFormat('yyyy-MM-dd').format(_date),
      notes: _notesController.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }

    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.updateBalanceSaved)));
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l.updateBalanceFailed(result['error'].toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hideAmounts = context.watch<PrivacyProvider>().hidden;

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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.updateBalanceTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                widget.account.name,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: SureSpacing.xl),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: '${l.updateBalanceAmountLabel} *',
                  suffixText: widget.account.currency,
                  helperText: l.updateBalanceCurrent(
                    MoneyMasker.mask(widget.account.balance, hidden: hideAmounts),
                  ),
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: SureSpacing.xl),
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.transactionFormDateLabel,
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    DateFormat.yMMMd(_localeName()).format(_date),
                  ),
                ),
              ),
              const SizedBox(height: SureSpacing.xl),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(labelText: l.updateBalanceNotesLabel),
              ),
              const SizedBox(height: SureSpacing.lg),
              Text(
                l.updateBalanceLinkedHint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textSubdued),
              ),
              const SizedBox(height: SureSpacing.xl),
              SureButton(
                label: l.updateBalanceSave,
                onPressed: _isSubmitting ? null : _submit,
                loading: _isSubmitting,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
