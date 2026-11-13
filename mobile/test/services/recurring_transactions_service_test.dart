import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';

Map<String, dynamic> recurringJson(String id, {String status = 'active'}) => {
      'id': id,
      'name': 'Netflix',
      'amount': r'$15.99',
      'amount_cents': 1599,
      'currency': 'USD',
      'status': status,
      'next_expected_date': '2026-11-20',
      'account': {'id': 'acct_1', 'name': 'Checking', 'account_type': 'depository'},
      'merchant': null,
    };

void main() {
  test('follows pagination until total_pages', () async {
    final pages = <String>[];
    final service = RecurringTransactionsService(
      client: MockClient((request) async {
        final page = request.url.queryParameters['page']!;
        pages.add(page);
        return http.Response(
          jsonEncode({
            'recurring_transactions': [recurringJson('rt_$page')],
            'pagination': {'page': int.parse(page), 'per_page': 100, 'total_count': 2, 'total_pages': 2},
          }),
          200,
        );
      }),
    );

    final result = await service.getAll(accessToken: 'token');

    final items = result['recurring_transactions'] as List<RecurringTransaction>;
    expect(items.map((r) => r.id), ['rt_1', 'rt_2']);
    expect(pages, ['1', '2']);
    expect(items.first.accountName, 'Checking');
    expect(items.first.nextExpectedDate, DateTime(2026, 11, 20));
  });

  test('fails without a partial list when a page fails', () async {
    final service = RecurringTransactionsService(
      client: MockClient((request) async {
        if (request.url.queryParameters['page'] == '2') return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'recurring_transactions': [recurringJson('rt_1')],
            'pagination': {'total_pages': 2},
          }),
          200,
        );
      }),
    );

    final result = await service.getAll(accessToken: 'token');

    expect(result['success'], isFalse);
    expect(result.containsKey('recurring_transactions'), isFalse);
  });

  test('creates a monthly series with a clamped last occurrence', () async {
    late http.Request sent;
    final service = RecurringTransactionsService(
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(recurringJson('rt_1')), 201);
      }),
    );

    final result = await service.create(
      accessToken: 'token',
      name: 'Rent',
      amount: '1200',
      currency: 'USD',
      accountId: 'acct_1',
      nextExpectedDate: DateTime(2026, 3, 31),
      notes: ' ',
    );

    expect(result['success'], isTrue);
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/recurring_transactions');
    expect(jsonDecode(sent.body), {
      'recurring_transaction': {
        'name': 'Rent',
        'amount': '1200',
        'currency': 'USD',
        'account_id': 'acct_1',
        'expected_day_of_month': 31,
        'next_expected_date': '2026-03-31',
        'last_occurrence_date': '2026-02-28',
        'status': 'active',
      },
    });
  });

  test('sets status with PATCH and deletes with DELETE', () async {
    final sent = <http.Request>[];
    final service = RecurringTransactionsService(
      client: MockClient((request) async {
        sent.add(request);
        return http.Response('{}', 200);
      }),
    );

    await service.setActive(accessToken: 'token', id: 'rt_1', active: false);
    await service.delete(accessToken: 'token', id: 'rt_1');

    expect(sent.map((r) => '${r.method} ${r.url.path}'), [
      'PATCH /api/v1/recurring_transactions/rt_1',
      'DELETE /api/v1/recurring_transactions/rt_1',
    ]);
    expect(jsonDecode(sent.first.body), {
      'recurring_transaction': {'status': 'inactive'},
    });
  });

  test('surfaces the first validation error of a 422', () async {
    final service = RecurringTransactionsService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'validation_failed',
            'message': 'Recurring transaction could not be created',
            'errors': ["Name can't be blank"],
          }),
          422,
        ),
      ),
    );

    final result = await service.create(
      accessToken: 'token',
      name: '',
      amount: '1',
      currency: 'USD',
      accountId: 'acct_1',
      nextExpectedDate: DateTime(2026, 11, 20),
    );

    expect(result, {'success': false, 'error': "Name can't be blank"});
  });

  test('reports unauthorized on 401', () async {
    final service = RecurringTransactionsService(
      client: MockClient((_) async => http.Response('', 401)),
    );

    final result = await service.getAll(accessToken: 'token');

    expect(result, {'success': false, 'error': 'unauthorized'});
  });
}
