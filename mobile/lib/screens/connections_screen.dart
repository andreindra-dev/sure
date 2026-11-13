import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/provider_connection.dart';
import '../providers/auth_provider.dart';
import '../services/provider_connections_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_list_group.dart';

/// Bank connection health plus a button that asks the server to sync them.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, this.service});

  final ProviderConnectionsService? service;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  static const _pollInterval = Duration(seconds: 5);
  // ponytail: fixed poll cap; long first-time syncs just need a manual refresh.
  static const _maxPolls = 24;

  late final ProviderConnectionsService _service =
      widget.service ?? ProviderConnectionsService();
  List<ProviderConnection> _connections = [];
  bool _loading = true;
  bool _requestingSync = false;
  String? _error;
  Timer? _pollTimer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<String?> _accessToken() async {
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getValidAccessToken();
    if (token == null) await authProvider.logout();
    return token;
  }

  Future<void> _load() async {
    final token = await _accessToken();
    if (token == null || !mounted) return;

    final result = await _service.getConnections(accessToken: token);
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await context.read<AuthProvider>().logout();
      return;
    }

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _connections = result['connections'] as List<ProviderConnection>;
        _error = null;
      } else {
        _error = result['error']?.toString();
      }
    });

    if (!_connections.any((c) => c.syncing)) _pollTimer?.cancel();
  }

  void _pollWhileSyncing() {
    _pollTimer?.cancel();
    _polls = 0;
    _pollTimer = Timer.periodic(_pollInterval, (timer) {
      if (++_polls >= _maxPolls) timer.cancel();
      _load();
    });
  }

  Future<void> _requestSync() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = await _accessToken();
    if (token == null || !mounted) return;

    setState(() => _requestingSync = true);
    final result = await _service.requestSync(accessToken: token);
    if (!mounted) return;
    setState(() => _requestingSync = false);

    if (result['error'] == 'unauthorized') {
      await context.read<AuthProvider>().logout();
      return;
    }

    final ok = result['success'] == true;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? l.connectionsSyncStarted : l.connectionsSyncFailed)),
    );
    if (ok) {
      await _load();
      _pollWhileSyncing();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    return Scaffold(
      appBar: AppBar(title: Text(l.connectionsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(SureSpacing.xl),
                children: [
                  SureButton(
                    label: l.connectionsSyncNow,
                    onPressed: _requestingSync ? null : _requestSync,
                    loading: _requestingSync,
                    fullWidth: true,
                    leading: const SureIcon(SureIcons.refresh, size: SureIconSize.sm),
                  ),
                  const SizedBox(height: SureSpacing.xl),
                  if (_error != null)
                    _message(l.connectionsLoadFailed, _error, palette.destructive)
                  else if (_connections.isEmpty)
                    _message(l.connectionsEmpty, null, palette.textSecondary)
                  else
                    SureListGroup(
                      children: [
                        for (final connection in _connections) _row(context, connection),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  Widget _message(String title, String? detail, Color color) {
    return Padding(
      padding: const EdgeInsets.all(SureSpacing.xl),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: color)),
          if (detail != null) ...[
            const SizedBox(height: SureSpacing.md),
            Text(detail, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ProviderConnection connection) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();

    final String icon;
    final Color color;
    final String status;
    if (connection.syncing) {
      icon = SureIcons.refresh;
      color = palette.textSecondary;
      status = l.connectionsStatusSyncing;
    } else if (connection.needsAttention) {
      icon = SureIcons.circleAlert;
      color = palette.destructive;
      status = connection.syncErrorMessage ?? l.connectionsStatusNeedsAttention;
    } else {
      icon = SureIcons.circleCheck;
      color = palette.success;
      status = connection.lastSyncedAt == null
          ? l.connectionsNeverSynced
          : l.connectionsLastSynced(
              DateFormat.yMMMd(locale).add_jm().format(connection.lastSyncedAt!.toLocal()),
            );
    }

    return SureListRow(
      leading: SureIcon(icon, color: color, size: SureIconSize.md),
      title: connection.displayName,
      subtitle: connection.statusSummary == null
          ? status
          : '$status · ${connection.statusSummary}',
    );
  }
}
