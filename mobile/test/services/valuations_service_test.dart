import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/valuations_service.dart';

void main() {
  group('ValuationsService.createValuation', () {
    test('posts a nested valuation and succeeds on 201', () async {
      late http.Request sent;
      final service = ValuationsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'id': 'entry_1'}), 201);
        }),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '1234.50',
        date: '2026-11-14',
        notes: '  counted cash  ',
      );

      expect(result['success'], isTrue);
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/valuations');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {
        'valuation': {
          'account_id': 'acct_1',
          'amount': '1234.50',
          'date': '2026-11-14',
          'notes': 'counted cash',
        },
      });
    });

    test('omits blank notes and accepts 200 for a same-date update', () async {
      late http.Request sent;
      final service = ValuationsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'id': 'entry_1'}), 200);
        }),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '0',
        date: '2026-11-14',
        notes: '   ',
      );

      expect(result['success'], isTrue);
      expect(
        (jsonDecode(sent.body) as Map)['valuation'],
        isNot(contains('notes')),
      );
    });

    test('surfaces the server message on 422', () async {
      final service = ValuationsService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'validation_failed',
              'message': 'Valuation could not be created',
              'errors': ['Date cannot be in the future'],
            }),
            422,
          ),
        ),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '10',
        date: '2026-11-14',
      );

      expect(result['success'], isFalse);
      expect(result['error'], 'Valuation could not be created');
    });

    test('reports unauthorized on 401', () async {
      final service = ValuationsService(
        client: MockClient((_) async => http.Response('', 401)),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '10',
        date: '2026-11-14',
      );

      expect(result, {'success': false, 'error': 'unauthorized'});
    });
  });
}
