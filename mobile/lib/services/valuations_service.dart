import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'response_list_parser.dart';

class ValuationsService {
  ValuationsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Records an account's balance on [date] via POST /api/v1/valuations.
  ///
  /// [amount] is a canonical decimal string (see `AmountParser.canonicalize`)
  /// and [date] is `yyyy-MM-dd`. The server reconciles the account to this
  /// balance and recalculates history in a background sync, so the account's
  /// balance may update a moment later. A valuation on a date that already
  /// has one replaces it.
  Future<Map<String, dynamic>> createValuation({
    required String accessToken,
    required String accountId,
    required String amount,
    required String date,
    String? notes,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/v1/valuations'),
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'valuation': {
                'account_id': accountId,
                'amount': amount,
                'date': date,
                if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }

      return {
        'success': false,
        'error': extractErrorMessage(
          response.body,
          fallback: 'Failed to update balance',
        ),
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
