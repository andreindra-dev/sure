import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/spending_insights.dart';
import 'package:sure_mobile/services/insights_service.dart';

import '../support/insights_fixture.dart';

void main() {
  InsightsService serviceReturning(String body, int status, {List<http.Request>? log}) {
    return InsightsService(
      client: MockClient((request) async {
        log?.add(request);
        return http.Response(body, status);
      }),
    );
  }

  test('parses spending vs normal decimals and the overall ratio', () async {
    final result = await serviceReturning(spendingVsNormalFixture, 200)
        .getSpendingVsNormal(accessToken: 'token');

    expect(result['success'], isTrue);
    final report = result['report'] as SpendingVsNormal;
    expect(report.currency, 'USD');
    expect(report.inProgress, isTrue);
    expect(report.comparable, isTrue);
    expect(report.total, 300);
    expect(report.ratio, closeTo(0.5, 1e-9));
    expect(report.categories.map((c) => c.name), ['Groceries', 'Dining']);
    expect(report.categories.last.ratio, -0.25);
  });

  test('has no overall ratio without a normal', () {
    final report = SpendingVsNormal.fromJson({
      'currency': 'USD',
      'comparable': false,
      'total': '10.0',
      'normal_total': null,
      'categories': [],
    });
    expect(report.ratio, isNull);
  });

  test('parses insights', () async {
    final result = await serviceReturning(insightsFixture, 200)
        .getInsights(accessToken: 'token');

    final insights = result['insights'] as List<Insight>;
    expect(insights.single.title, 'Groceries are up');
    expect(insights.single.isHighPriority, isTrue);
  });

  test('maps a preview-features 403 to featureDisabled', () async {
    final result = await serviceReturning(featureDisabledBody, 403)
        .getInsights(accessToken: 'token');

    expect(result, {'success': false, 'error': InsightsService.featureDisabled});
  });

  test('acknowledges with PATCH and treats 204 as success', () async {
    final log = <http.Request>[];
    final result = await serviceReturning('', 204, log: log)
        .acknowledgeInsight(accessToken: 'token', id: 'abc');

    expect(result['success'], isTrue);
    expect(log.single.method, 'PATCH');
    expect(log.single.url.path, '/api/v1/insights/abc/acknowledge');
  });

  test('reports unauthorized on 401', () async {
    final result = await serviceReturning('', 401)
        .getSpendingVsNormal(accessToken: 'token');

    expect(result, {'success': false, 'error': 'unauthorized'});
  });
}
