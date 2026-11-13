import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/recurring_transactions_screen.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

void main() {
  final writes = <http.Request>[];
  late List<Map<String, dynamic>> serverItems;

  Map<String, dynamic> item(String id, String name, String status, String next, String amount, int cents) => {
        'id': id,
        'name': name,
        'amount': amount,
        'amount_cents': cents,
        'currency': 'USD',
        'status': status,
        'next_expected_date': next,
        'account': {'id': 'acct_1', 'name': 'Checking'},
        'merchant': null,
      };

  setUp(() {
    writes.clear();
    serverItems = [
      item('rt_rent', 'Rent', 'active', '2026-12-01', r'$1,200.00', 120000),
      item('rt_gym', 'Gym', 'inactive', '2026-11-05', r'$40.00', 4000),
      item('rt_netflix', 'Netflix', 'active', '2026-11-20', r'$15.99', 1599),
      item('rt_salary', 'Salary', 'active', '2026-11-25', r'-$3,000.00', -300000),
    ];
  });

  RecurringTransactionsService service() => RecurringTransactionsService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'recurring_transactions': serverItems,
                'pagination': {'total_pages': 1},
              }),
              200,
            );
          }
          writes.add(request);
          final id = request.url.pathSegments.last;
          if (request.method == 'DELETE') {
            serverItems.removeWhere((i) => i['id'] == id);
          } else if (request.method == 'PATCH') {
            final status = (jsonDecode(request.body) as Map)['recurring_transaction']['status'];
            serverItems.firstWhere((i) => i['id'] == id)['status'] = status;
          }
          return http.Response('{}', 200);
        }),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<PrivacyProvider>.value(
        value: PrivacyProvider(initialHidden: false),
        child: MaterialApp(
          theme: SureTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RecurringTransactionsScreen(
            service: service(),
            accessTokenLoader: (_) async => 'token',
            onUnauthorized: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> rowOrder(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('recurring_'),
      ))
      .map((w) => (w.key as ValueKey<String>).value)
      .toList();

  testWidgets('lists active items by next date, then inactive ones', (tester) async {
    await pumpScreen(tester);

    expect(rowOrder(tester), [
      'recurring_rt_netflix',
      'recurring_rt_salary',
      'recurring_rt_rent',
      'recurring_rt_gym',
    ]);
    expect(find.text('Next Nov 20 · Checking'), findsOneWidget);
    expect(find.text('Inactive · Checking'), findsOneWidget);
  });

  testWidgets('marking an item inactive patches it and reloads', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark inactive'));
    await tester.pumpAndSettle();

    expect(writes.single.method, 'PATCH');
    expect(rowOrder(tester).last, 'recurring_rt_netflix');
  });

  testWidgets('deleting asks for confirmation, then removes the item', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete recurring transaction?'), findsOneWidget);
    expect(writes, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(writes.single.method, 'DELETE');
    expect(find.text('Gym'), findsNothing);
  });
}
