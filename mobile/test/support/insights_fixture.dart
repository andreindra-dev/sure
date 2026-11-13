/// A `GET /api/v1/spending_vs_normal` body for an unfinished month: 50% above
/// normal overall, Groceries up 50%, Dining down 25%.
const spendingVsNormalFixture = '''
{
  "currency": "USD",
  "period": {"start_date": "2026-11-01", "end_date": "2026-11-14"},
  "in_progress": true,
  "baseline_period": {"start_date": "2025-11-01", "end_date": "2026-10-31"},
  "comparable": true,
  "total": "300.0",
  "normal_total": "200.0",
  "categories": [
    {"id": "11111111-1111-1111-1111-111111111111", "name": "Groceries", "color": "#4da568",
     "filter_value": "Groceries", "total": "225.0", "normal": "150.0", "change": "75.0", "ratio": "0.5"},
    {"id": "22222222-2222-2222-2222-222222222222", "name": "Dining", "color": "#e99537",
     "filter_value": "Dining", "total": "75.0", "normal": "100.0", "change": "-25.0", "ratio": "-0.25"}
  ]
}
''';

const insightsFixture = '''
{
  "insights": [
    {"id": "33333333-3333-3333-3333-333333333333", "type": "spending_spike",
     "title": "Groceries are up", "body": "You spent 50% more on groceries than usual.",
     "priority": "high", "status": "active", "generated_at": "2026-11-13T08:00:00Z"}
  ]
}
''';

const featureDisabledBody =
    '{"error":"feature_disabled","message":"Preview features are not enabled for this user"}';
