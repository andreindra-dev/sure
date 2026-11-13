import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/spending_insights.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/insights_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import '../widgets/money_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_list_group.dart';
import 'cash_flow_screen.dart' show AccessTokenLoader, CashFlowFormat;

/// This month's spending per category against normal, plus the proactive
/// insights the server generated (a preview feature; hidden with a hint when
/// the user hasn't enabled preview features).
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final InsightsService? service;
  final AccessTokenLoader? accessTokenLoader;

  /// Defaults to [AuthProvider.logout], like the other screens.
  final Future<void> Function(BuildContext context)? onUnauthorized;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final InsightsService _service = widget.service ?? InsightsService();

  bool _loading = true;
  // Kept from the last successful load when a refresh fails.
  SpendingVsNormal? _spending;
  List<Insight> _insights = [];
  String? _insightsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader(context);
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _handleUnauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler(context);
    await context.read<AuthProvider>().logout();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      await _handleUnauthorized();
      return;
    }

    final results = await Future.wait([
      _service.getSpendingVsNormal(accessToken: token),
      _service.getInsights(accessToken: token),
    ]);
    if (!mounted) return;
    final spending = results[0];
    final insights = results[1];

    if (spending['error'] == 'unauthorized' || insights['error'] == 'unauthorized') {
      await _handleUnauthorized();
      return;
    }

    setState(() {
      _loading = false;
      if (spending['success'] == true) _spending = spending['report'] as SpendingVsNormal;
      _insightsError = insights['success'] == true ? null : insights['error']?.toString();
      if (_insightsError == null) _insights = insights['insights'] as List<Insight>;
    });
  }

  Future<void> _dismiss(Insight insight) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final index = _insights.indexOf(insight);
    setState(() => _insights = [..._insights]..remove(insight));

    final token = await _accessToken();
    final result = token == null
        ? {'success': false, 'error': 'unauthorized'}
        : await _service.acknowledgeInsight(accessToken: token, id: insight.id);
    if (!mounted || result['success'] == true) return;

    if (result['error'] == 'unauthorized') {
      await _handleUnauthorized();
      return;
    }
    setState(() => _insights = [..._insights]..insert(index.clamp(0, _insights.length), insight));
    messenger.showSnackBar(SnackBar(content: Text(l.insightsDismissFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.insightsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            SureSpacing.xl,
            SureSpacing.md,
            SureSpacing.xl,
            SureSpacing.huge,
          ),
          children: _loading && _spending == null
              ? const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: SureSpacing.huge * 2),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ]
              : [
                  ..._spendingSection(context),
                  const SizedBox(height: SureSpacing.xxxl),
                  ..._insightsSection(context),
                ],
        ),
      ),
    );
  }

  List<Widget> _spendingSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final spending = _spending;
    if (spending == null) {
      return [
        _Note(
          text: l.insightsSpendingLoadFailed,
          action: SureButton(
            label: l.commonTryAgain,
            onPressed: _load,
            leading: const SureIcon(SureIcons.refresh, size: SureIconSize.sm),
          ),
        ),
      ];
    }
    return [
      _SpendingSummary(spending: spending),
      if (spending.categories.isNotEmpty) ...[
        const SizedBox(height: SureSpacing.xl),
        _SpendingCategories(spending: spending),
      ],
    ];
  }

  List<Widget> _insightsSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: SureSpacing.md),
      child: Text(l.insightsSectionTitle, style: theme.textTheme.titleMedium),
    );

    if (_insightsError == InsightsService.featureDisabled) {
      return [header, _Note(text: l.insightsPreviewDisabled)];
    }
    if (_insightsError != null) {
      return [header, _Note(text: l.insightsLoadFailed)];
    }
    if (_insights.isEmpty) {
      return [header, _Note(text: l.insightsEmpty)];
    }
    return [
      header,
      for (final insight in _insights)
        Padding(
          padding: const EdgeInsets.only(bottom: SureSpacing.lg),
          child: _InsightCard(
            key: ValueKey('insight_${insight.id}'),
            insight: insight,
            onDismiss: () => _dismiss(insight),
          ),
        ),
    ];
  }
}

/// "+12.5%" / "-8.0%" for a fractional [ratio], masked in privacy mode.
String _change(BuildContext context, double ratio, bool hidden) {
  final percent = CashFlowFormat.percent(context, ratio * 100);
  return MoneyMasker.mask(ratio > 0 ? '+$percent' : percent, hidden: hidden);
}

Color _changeColor(BuildContext context, double? ratio) {
  final palette = SureColors.of(context).palette;
  if (ratio == null || ratio.abs() < 0.005) return palette.textSecondary;
  // More spending than normal is the bad direction.
  return ratio > 0 ? palette.destructive : palette.success;
}

class _SpendingSummary extends StatelessWidget {
  const _SpendingSummary({required this.spending});

  final SpendingVsNormal spending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    String money(double v) =>
        MoneyMasker.mask(CashFlowFormat.money(context, v, spending.currency), hidden: hidden);

    final ratio = spending.comparable ? spending.ratio : null;
    final String comparison;
    if (ratio == null) {
      comparison = l.insightsNotEnoughHistory;
    } else if (ratio.abs() < 0.005) {
      comparison = l.insightsAtNormal;
    } else {
      final percent = MoneyMasker.mask(
        CashFlowFormat.percent(context, ratio.abs() * 100),
        hidden: hidden,
      );
      comparison = ratio > 0 ? l.insightsAboveNormal(percent) : l.insightsBelowNormal(percent);
    }

    return SureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.insightsSpendingTitle,
            style: theme.textTheme.labelLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: SureSpacing.xs),
          Text(
            money(spending.total),
            style: SureMoney.tabular(
              theme.textTheme.headlineSmall?.copyWith(fontWeight: SureTokens.weightMedium),
            ),
          ),
          const SizedBox(height: SureSpacing.sm),
          Text(
            comparison,
            style: theme.textTheme.bodyMedium?.copyWith(color: _changeColor(context, ratio)),
          ),
          if (ratio != null && spending.normalTotal != null) ...[
            const SizedBox(height: SureSpacing.xs),
            Text(
              l.insightsNormal(money(spending.normalTotal!)),
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubdued),
            ),
          ],
          if (spending.inProgress) ...[
            const SizedBox(height: SureSpacing.sm),
            Text(
              l.insightsInProgressHint,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubdued),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpendingCategories extends StatelessWidget {
  const _SpendingCategories({required this.spending});

  final SpendingVsNormal spending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    String money(double v) =>
        MoneyMasker.mask(CashFlowFormat.money(context, v, spending.currency), hidden: hidden);

    return SureListGroup(
      header: l.insightsByCategory,
      children: [
        for (final category in spending.categories)
          SureListRow(
            key: ValueKey('spendingCategory_${category.id ?? category.name}'),
            title: category.name,
            subtitle: category.normal == null ? null : l.insightsNormal(money(category.normal!)),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(category.total),
                  style: SureMoney.tabular(
                    theme.textTheme.titleSmall?.copyWith(
                      fontWeight: SureTokens.weightMedium,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (category.ratio != null)
                  Text(
                    _change(context, category.ratio!, hidden),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _changeColor(context, category.ratio),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({super.key, required this.insight, required this.onDismiss});

  final Insight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);

    return SureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (insight.isHighPriority) ...[
                SureIcon(SureIcons.circleAlert, size: SureIconSize.md, color: palette.warning),
                const SizedBox(width: SureSpacing.md),
              ],
              Expanded(child: Text(insight.title, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: SureSpacing.sm),
          Text(
            insight.body,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onDismiss, child: Text(l.insightsDismiss)),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SureSpacing.xl),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: SureSpacing.lg), action!],
        ],
      ),
    );
  }
}
