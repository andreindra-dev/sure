/// A recurring transaction (bill, subscription, income) from
/// `/api/v1/recurring_transactions`.
class RecurringTransaction {
  final String id;
  final String? name;
  final String? merchantName;

  /// Server-formatted amount (e.g. "$15.99"); positive is money out.
  final String amount;
  final int? amountCents;
  final String currency;

  /// `active` or `inactive` are what the API writes; detection and the web
  /// can also set `suggested`, `paused` or `ended`.
  final String status;
  final DateTime? nextExpectedDate;
  final String? accountName;
  final String? notes;

  const RecurringTransaction({
    required this.id,
    this.name,
    this.merchantName,
    required this.amount,
    this.amountCents,
    required this.currency,
    required this.status,
    this.nextExpectedDate,
    this.accountName,
    this.notes,
  });

  bool get isActive => status == 'active';
  bool get isIncome => (amountCents ?? 0) < 0;

  String get displayName {
    final own = name?.trim() ?? '';
    if (own.isNotEmpty) return own;
    return merchantName?.trim() ?? '';
  }

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    final merchant = json['merchant'];
    final account = json['account'];
    return RecurringTransaction(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      merchantName: merchant is Map ? merchant['name']?.toString() : null,
      amount: json['amount']?.toString() ?? '',
      amountCents: json['amount_cents'] is num ? (json['amount_cents'] as num).toInt() : null,
      currency: json['currency']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      nextExpectedDate: DateTime.tryParse(json['next_expected_date']?.toString() ?? ''),
      accountName: account is Map ? account['name']?.toString() : null,
      notes: json['notes']?.toString(),
    );
  }
}
