/// A proactive insight from `GET /api/v1/insights` (a preview feature).
class Insight {
  final String id;
  final String type;
  final String title;
  final String body;

  /// `high`, `medium` or `low`.
  final String priority;
  final DateTime? generatedAt;

  const Insight({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    this.generatedAt,
  });

  bool get isHighPriority => priority == 'high';

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'low',
      generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
    );
  }
}

/// One parent category from `GET /api/v1/spending_vs_normal`.
class SpendingVsNormalCategory {
  final String? id;
  final String name;
  final String? color;
  final double total;

  /// Null without enough history.
  final double? normal;

  /// Fractional change against normal (0.5 = 50% more); null without a
  /// positive normal.
  final double? ratio;

  const SpendingVsNormalCategory({
    this.id,
    required this.name,
    this.color,
    required this.total,
    this.normal,
    this.ratio,
  });

  factory SpendingVsNormalCategory.fromJson(Map<String, dynamic> json) {
    return SpendingVsNormalCategory(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString(),
      total: _decimal(json['total']) ?? 0,
      normal: _decimal(json['normal']),
      ratio: _decimal(json['ratio']),
    );
  }
}

/// Net spending per category for a period against each category's normal.
class SpendingVsNormal {
  final String currency;

  /// The period hasn't ended; it is cut to today and compared with the same
  /// days of earlier months.
  final bool inProgress;

  /// False with too little history to compute a normal.
  final bool comparable;
  final double total;
  final double? normalTotal;

  /// Parent categories, largest total first.
  final List<SpendingVsNormalCategory> categories;

  const SpendingVsNormal({
    required this.currency,
    required this.inProgress,
    required this.comparable,
    required this.total,
    this.normalTotal,
    required this.categories,
  });

  /// Overall fractional change against normal; null without a positive normal.
  double? get ratio {
    final normal = normalTotal;
    if (normal == null || normal <= 0) return null;
    return (total - normal) / normal;
  }

  factory SpendingVsNormal.fromJson(Map<String, dynamic> json) {
    final categories = json['categories'];
    return SpendingVsNormal(
      currency: json['currency']?.toString() ?? '',
      inProgress: json['in_progress'] == true,
      comparable: json['comparable'] == true,
      total: _decimal(json['total']) ?? 0,
      normalTotal: _decimal(json['normal_total']),
      categories: categories is List
          ? categories
              .whereType<Map>()
              .map((c) => SpendingVsNormalCategory.fromJson(c.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// The API sends money and ratios as plain decimal strings ("1234.5").
double? _decimal(dynamic value) =>
    value == null ? null : double.tryParse(value.toString());
