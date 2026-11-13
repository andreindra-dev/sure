import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/spending_insights.dart';
import 'api_config.dart';
import 'response_list_parser.dart';

/// Proactive insights (`/api/v1/insights`) and the current month's spending
/// against normal (`/api/v1/spending_vs_normal`).
class InsightsService {
  InsightsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Error returned when the user hasn't turned on preview features, which
  /// insights require.
  static const featureDisabled = 'feature_disabled';

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Returns `{'success': true, 'insights': List<Insight>}` or
  /// `{'success': false, 'error': …}` with `'unauthorized'` on 401 and
  /// [featureDisabled] when preview features are off.
  Future<Map<String, dynamic>> getInsights({required String accessToken}) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/v1/insights'),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final insights = extractJsonObjectList(
          jsonDecode(response.body),
          key: 'insights',
        ).map(Insight.fromJson).where((i) => i.id.isNotEmpty).toList();
        return {'success': true, 'insights': insights};
      }
      return _failure(response, fallback: 'Failed to load insights');
    } catch (_) {
      return {'success': false, 'error': 'Unable to load insights. Please try again later.'};
    }
  }

  /// Dismisses an insight via PATCH /api/v1/insights/{id}/acknowledge (204).
  Future<Map<String, dynamic>> acknowledgeInsight({
    required String accessToken,
    required String id,
  }) async {
    try {
      final response = await _client
          .patch(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/v1/insights/${Uri.encodeComponent(id)}/acknowledge',
            ),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return _failure(response, fallback: 'Failed to dismiss insight');
    } catch (_) {
      return {'success': false, 'error': 'Unable to dismiss insight. Please try again later.'};
    }
  }

  /// The current month to date against normal.
  ///
  /// Returns `{'success': true, 'report': SpendingVsNormal}` or
  /// `{'success': false, 'error': …}` (`'unauthorized'` on 401).
  Future<Map<String, dynamic>> getSpendingVsNormal({
    required String accessToken,
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/v1/spending_vs_normal'),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is! Map) {
          return {'success': false, 'error': 'Unexpected spending response'};
        }
        return {
          'success': true,
          'report': SpendingVsNormal.fromJson(data.cast<String, dynamic>()),
        };
      }
      return _failure(response, fallback: 'Failed to load spending');
    } catch (_) {
      return {'success': false, 'error': 'Unable to load spending. Please try again later.'};
    }
  }

  Map<String, dynamic> _failure(http.Response response, {required String fallback}) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    if (response.statusCode == 403 && _errorCode(response.body) == featureDisabled) {
      return {'success': false, 'error': featureDisabled};
    }
    return {
      'success': false,
      'error': extractErrorMessage(response.body, fallback: fallback),
    };
  }

  static String? _errorCode(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map ? data['error']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
