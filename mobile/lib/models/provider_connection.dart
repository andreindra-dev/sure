/// A bank/provider connection summary from `GET /api/v1/provider_connections`.
class ProviderConnection {
  final String id;
  final String name;
  final String provider;
  final String? institutionName;
  final String? status;
  final bool requiresUpdate;
  final bool pendingAccountSetup;
  final bool syncing;
  final String? statusSummary;
  final DateTime? lastSyncedAt;

  /// Sanitized error category from the latest sync; null when it didn't fail.
  final String? syncErrorMessage;
  final bool hasSyncError;

  ProviderConnection({
    required this.id,
    required this.name,
    required this.provider,
    this.institutionName,
    this.status,
    this.requiresUpdate = false,
    this.pendingAccountSetup = false,
    this.syncing = false,
    this.statusSummary,
    this.lastSyncedAt,
    this.syncErrorMessage,
    this.hasSyncError = false,
  });

  /// The user has to act (usually on the web app) before this connection
  /// syncs cleanly again.
  bool get needsAttention =>
      requiresUpdate ||
      status == 'requires_update' ||
      pendingAccountSetup ||
      hasSyncError;

  String get displayName =>
      (institutionName?.trim().isNotEmpty ?? false) ? institutionName! : name;

  factory ProviderConnection.fromJson(Map<String, dynamic> json) {
    final institution = json['institution'];
    final sync = json['sync'] is Map ? json['sync'] as Map : const {};
    final latest = sync['latest'] is Map ? sync['latest'] as Map : const {};
    final error = latest['error'] is Map ? latest['error'] as Map : null;

    return ProviderConnection(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      institutionName: institution is Map ? institution['name']?.toString() : null,
      status: json['status']?.toString(),
      requiresUpdate: json['requires_update'] == true,
      pendingAccountSetup: json['pending_account_setup'] == true,
      syncing: sync['syncing'] == true,
      statusSummary: sync['status_summary']?.toString(),
      lastSyncedAt: DateTime.tryParse(sync['last_synced_at']?.toString() ?? ''),
      syncErrorMessage: error?['message']?.toString(),
      hasSyncError: error != null,
    );
  }
}
