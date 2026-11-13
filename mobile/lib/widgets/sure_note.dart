import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';

/// Centered secondary text for an empty or error state, with an optional
/// action (e.g. a retry button) below it.
class SureNote extends StatelessWidget {
  const SureNote({super.key, required this.text, this.action});

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
