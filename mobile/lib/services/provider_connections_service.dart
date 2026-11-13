import 'package:http/http.dart' as http;
import '../models/provider_connection.dart';
import 'api_config.dart';
import 'response_list_parser.dart';

class ProviderConnectionsService {
  ProviderConnectionsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Fetches connection health from GET /api/v1/provider_connections.
  ///
  /// Returns `{'success': true, 'connections': List<ProviderConnection>}` or
  /// `{'success': false, 'error': ...}` (`'unauthorized'` on 401).
  Future<Map<String, dynamic>> getConnections({
    required String accessToken,
  }) {
    return fetchApiList<ProviderConnection>(
      accessToken: accessToken,
      path: '/api/v1/provider_connections',
      key: 'data',
      resultKey: 'connections',
      fromJson: ProviderConnection.fromJson,
      isValid: (connection) => connection.id.isNotEmpty,
      failureMessage: 'Failed to fetch connections',
      client: _client,
    );
  }

  /// Queues a family sync (rules, every provider account, transfer matching)
  /// via POST /api/v1/sync. The server answers 202 before the sync runs.
  Future<Map<String, dynamic>> requestSync({
    required String accessToken,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/v1/sync'),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 202) {
        return {'success': true};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }

      return {
        'success': false,
        'error': extractErrorMessage(
          response.body,
          fallback: 'Failed to start sync',
        ),
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
