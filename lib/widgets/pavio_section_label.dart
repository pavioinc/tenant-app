import 'package:flutter/material.dart';
import '../theme/pavio_colors.dart';
import '../theme/pavio_spacing.dart';
import '../theme/pavio_text_styles.dart';

/// The small green accent bar + bold label the design doc's redesigned screens use ahead
/// of a section ("Your rental", "Renewal", "Recent payments") — first introduced for
/// Lease (doc option "1d"), promoted here once Payments (option "1c") needed the exact
/// same pattern rather than a second hand-copied one.
class PavioSectionLabel extends StatelessWidget {
  const PavioSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: PavioColors.primary700,
            borderRadius: BorderRadius.circular(PavioRadius.accentBar),
          ),
        ),
        const SizedBox(width: PavioSpacing.s8),
        Text(label, style: PavioText.sectionTitle),
      ],
    );
  }
}
