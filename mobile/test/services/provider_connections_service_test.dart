import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/provider_connection.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';

/// Shape of one entry from the provider_connections jbuilder view.
Map<String, dynamic> connectionJson({
  String id = 'conn_1',
  String? status = 'good',
  bool requiresUpdate = false,
  bool syncing = false,
  Map<String, dynamic>? error,
}) {
  return {
    'id': id,
    'provider': 'simplefin',
    'provider_type': 'SimplefinItem',
    'name': 'SimpleFIN',
    'status': status,
    'requires_update': requiresUpdate,
    'credentials_configured': true,
    'scheduled_for_deletion': false,
    'pending_account_setup': false,
    'institution': {'name': 'Chase', 'domain': 'chase.com', 'url': null},
    'accounts': {'total_count': 2, 'linked_count': 2, 'unlinked_count': 0},
    'sync': {
      'syncing': syncing,
      'status_summary': '2 accounts synced',
      'last_synced_at': '2026-11-10T08:00:00Z',
      'latest': {
        'id': 'sync_1',
        'status': error == null ? 'completed' : 'failed',
        'created_at': '2026-11-10T07:59:00Z',
        'error': error,
      },
    },
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-11-10T08:00:00Z',
  };
}

void main() {
  group('ProviderConnectionsService.getConnections', () {
    test('parses connections from the data envelope', () async {
      final service = ProviderConnectionsService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/provider_connections');
          return http.Response(
            jsonEncode({
              'data': [
                connectionJson(),
                connectionJson(
                  id: 'conn_2',
                  error: {'present': true, 'message': 'Login required'},
                ),
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.getConnections(accessToken: 'token');

      expect(result['success'], isTrue);
      final connections = result['connections'] as List<ProviderConnection>;
      expect(connections, hasLength(2));
      expect(connections.first.displayName, 'Chase');
      expect(connections.first.needsAttention, isFalse);
      expect(connections.first.lastSyncedAt, DateTime.utc(2026, 11, 10, 8));
      expect(connections.first.statusSummary, '2 accounts synced');
      expect(connections.last.needsAttention, isTrue);
      expect(connections.last.syncErrorMessage, 'Login required');
    });

    test('flags requires_update status as needing attention', () {
      expect(
        ProviderConnection.fromJson(connectionJson(status: 'requires_update'))
            .needsAttention,
        isTrue,
      );
      expect(
        ProviderConnection.fromJson(connectionJson(requiresUpdate: true))
            .needsAttention,
        isTrue,
      );
    });

    test('reports unauthorized on 401', () async {
      final service = ProviderConnectionsService(
        client: MockClient((_) async => http.Response('', 401)),
      );

      final result = await service.getConnections(accessToken: 'token');

      expect(result, {'success': false, 'error': 'unauthorized'});
    });
  });

  group('ProviderConnectionsService.requestSync', () {
    test('posts to /api/v1/sync and succeeds on 202', () async {
      late http.Request sent;
      final service = ProviderConnectionsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'id': 'sync_1'}), 202);
        }),
      );

      final result = await service.requestSync(accessToken: 'token');

      expect(result['success'], isTrue);
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/sync');
    });

    test('surfaces the server message when scope is insufficient', () async {
      final service = ProviderConnectionsService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'insufficient_scope',
              'message': 'This action requires the \'write\' scope',
            }),
            403,
          ),
        ),
      );

      final result = await service.requestSync(accessToken: 'token');

      expect(result['success'], isFalse);
      expect(result['error'], 'This action requires the \'write\' scope');
    });
  });
}
