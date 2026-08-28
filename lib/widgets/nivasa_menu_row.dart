import 'package:flutter/material.dart';
import '../theme/nivasa_colors.dart';
import '../theme/nivasa_spacing.dart';
import '../theme/nivasa_text_styles.dart';

/// Shared "icon · label · trailing" row used by UserScreen and any sub-page that needs
/// the same list-item look (e.g. AccountDetailsScreen's "Change password" row) — lifted
/// out of the old SettingsScreen so the style stays in one place instead of copy-pasted
/// per screen.
class NivasaMenuRow extends StatelessWidget {
  const NivasaMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(NivasaSpacing.s16),
        decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? NivasaColors.ink500),
            const SizedBox(width: NivasaSpacing.s12),
            Expanded(child: Text(label, style: NivasaText.body.copyWith(color: labelColor))),
            trailing ?? Icon(Icons.chevron_right, color: NivasaColors.ink500),
          ],
        ),
      ),
    );
  }
}
