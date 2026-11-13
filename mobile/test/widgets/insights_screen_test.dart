import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/insights_screen.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

import '../support/insights_fixture.dart';

void main() {
  final requests = <http.Request>[];

  InsightsService service({String insights = insightsFixture, int insightsStatus = 200}) {
    return InsightsService(
      client: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/v1/spending_vs_normal':
            return http.Response(spendingVsNormalFixture, 200);
          case '/api/v1/insights':
            return http.Response(insights, insightsStatus);
          default:
            return http.Response('', 204);
        }
      }),
    );
  }

  Widget harness(InsightsService insightsService, {bool hidden = false}) {
    return ChangeNotifierProvider<PrivacyProvider>.value(
      value: PrivacyProvider(initialHidden: hidden),
      child: MaterialApp(
        theme: SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InsightsScreen(
          service: insightsService,
          accessTokenLoader: (_) async => 'token',
          onUnauthorized: (_) async {},
        ),
      ),
    );
  }

  setUp(requests.clear);

  testWidgets('shows spending against normal per category and insights', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(service()));
    await tester.pumpAndSettle();

    expect(find.text('\$300.00'), findsOneWidget);
    expect(find.text('50.0% above normal'), findsOneWidget);
    expect(find.text('Normal: \$200.00'), findsOneWidget);
    expect(find.text('+50.0%'), findsOneWidget);
    expect(find.text('-25.0%'), findsOneWidget);
    expect(find.text('Groceries are up'), findsOneWidget);
  });

  testWidgets('dismissing an insight acknowledges it and removes the card', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(service()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Groceries are up'), findsNothing);
    expect(find.text('No insights right now.'), findsOneWidget);
    final patch = requests.singleWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/v1/insights/33333333-3333-3333-3333-333333333333/acknowledge');
  });

  testWidgets('explains preview features when insights are disabled', (tester) async {
    await tester.pumpWidget(
      harness(service(insights: featureDisabledBody, insightsStatus: 403)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Turn on preview features'), findsOneWidget);
    expect(find.text('50.0% above normal'), findsOneWidget);
  });

  testWidgets('masks amounts and percentages in privacy mode', (tester) async {
    await tester.pumpWidget(harness(service(), hidden: true));
    await tester.pumpAndSettle();

    expect(find.text('\$300.00'), findsNothing);
    expect(find.text('+50.0%'), findsNothing);
  });
}
