import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/recurring_transaction.dart';
import 'api_config.dart';
import 'response_list_parser.dart';

/// CRUD for `/api/v1/recurring_transactions`.
class RecurringTransactionsService {
  RecurringTransactionsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Upper bound on pages [getAll] follows, so a bad `total_pages` can't loop
  /// forever.
  static const int maxPages = 20;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _url([String suffix = '', Map<String, String>? query]) => Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/recurring_transactions$suffix',
      ).replace(queryParameters: query);

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  /// Every recurring transaction the user can see, all pages.
  ///
  /// Returns `{'success': true, 'recurring_transactions': List<RecurringTransaction>}`
  /// or `{'success': false, 'error': …}` (`'unauthorized'` on 401). A failed
  /// page fails the whole call, so callers never show a partial list.
  Future<Map<String, dynamic>> getAll({required String accessToken}) async {
    final items = <RecurringTransaction>[];
    var page = 1;
    var totalPages = 1;
    try {
      while (page <= totalPages && page <= maxPages) {
        final response = await _client
            .get(
              _url('', {'page': '$page', 'per_page': '100'}),
              headers: ApiConfig.getAuthHeaders(accessToken),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return _failure(response, 'Failed to load recurring transactions');

        final data = jsonDecode(response.body);
        items.addAll(
          extractJsonObjectList(data, key: 'recurring_transactions')
              .map(RecurringTransaction.fromJson)
              .where((r) => r.id.isNotEmpty),
        );
        final pagination = data is Map ? data['pagination'] : null;
        totalPages = pagination is Map && pagination['total_pages'] is int
            ? pagination['total_pages'] as int
            : 1;
        page++;
      }
      return {'success': true, 'recurring_transactions': items};
    } catch (_) {
      return {'success': false, 'error': 'Unable to load recurring transactions. Please try again later.'};
    }
  }

  /// Creates a monthly recurring transaction. [amount] is a canonical decimal
  /// string, positive for money out and negative for money in; dates are
  /// `yyyy-MM-dd`.
  Future<Map<String, dynamic>> create({
    required String accessToken,
    required String name,
    required String amount,
    required String currency,
    required String accountId,
    required DateTime nextExpectedDate,
    String? notes,
  }) {
    // The API requires a last occurrence; for a series entered by hand that
    // is one month before the next one, clamped so Mar 31 maps to Feb 28/29.
    final lastDayOfPreviousMonth = DateTime(nextExpectedDate.year, nextExpectedDate.month, 0).day;
    final last = DateTime(
      nextExpectedDate.year,
      nextExpectedDate.month - 1,
      nextExpectedDate.day < lastDayOfPreviousMonth ? nextExpectedDate.day : lastDayOfPreviousMonth,
    );
    return _write(
      () => _client.post(
        _url(),
        headers: _headers(accessToken),
        body: jsonEncode({
          'recurring_transaction': {
            'name': name,
            'amount': amount,
            'currency': currency,
            'account_id': accountId,
            'expected_day_of_month': nextExpectedDate.day,
            'next_expected_date': _isoDate(nextExpectedDate),
            'last_occurrence_date': _isoDate(last),
            'status': 'active',
            if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          },
        }),
      ),
      fallback: 'Failed to create recurring transaction',
    );
  }

  /// Sets `active` or `inactive`, the only statuses the API writes.
  Future<Map<String, dynamic>> setActive({
    required String accessToken,
    required String id,
    required bool active,
  }) {
    return _write(
      () => _client.patch(
        _url('/${Uri.encodeComponent(id)}'),
        headers: _headers(accessToken),
        body: jsonEncode({
          'recurring_transaction': {'status': active ? 'active' : 'inactive'},
        }),
      ),
      fallback: 'Failed to update recurring transaction',
    );
  }

  Future<Map<String, dynamic>> delete({
    required String accessToken,
    required String id,
  }) {
    return _write(
      () => _client.delete(
        _url('/${Uri.encodeComponent(id)}'),
        headers: ApiConfig.getAuthHeaders(accessToken),
      ),
      fallback: 'Failed to delete recurring transaction',
    );
  }

  Future<Map<String, dynamic>> _write(
    Future<http.Response> Function() send, {
    required String fallback,
  }) async {
    try {
      final response = await send().timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true};
      }
      return _failure(response, fallback);
    } catch (_) {
      return {'success': false, 'error': '$fallback. Please try again later.'};
    }
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) return {'success': false, 'error': 'unauthorized'};
    return {'success': false, 'error': _validationMessage(response.body) ?? extractErrorMessage(response.body, fallback: fallback)};
  }

  /// The first field error of a 422, which says more than the generic message.
  static String? _validationMessage(String body) {
    try {
      final data = jsonDecode(body);
      final errors = data is Map ? data['errors'] : null;
      return errors is List && errors.isNotEmpty ? errors.first.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
