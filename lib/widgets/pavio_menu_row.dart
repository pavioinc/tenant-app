import 'package:flutter/material.dart';
import '../theme/pavio_colors.dart';
import '../theme/pavio_spacing.dart';
import '../theme/pavio_text_styles.dart';

/// Shared "icon · label · trailing" row used by UserScreen and any sub-page that needs
/// the same list-item look (e.g. AccountDetailsScreen's "Change password" row) — lifted
/// out of the old SettingsScreen so the style stays in one place instead of copy-pasted
/// per screen.
class PavioMenuRow extends StatelessWidget {
  const PavioMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
    this.showCard = true,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// False when this row sits inside a group card that already supplies the white
  /// background/border/radius (see UserScreen's grouped Account layout) — the row then
  /// only needs its own padding and tap target, not a second nested card.
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.card),
      child: Container(
        padding: const EdgeInsets.all(PavioSpacing.s16),
        decoration: showCard
            ? BoxDecoration(color: PavioColors.white, border: Border.all(color: PavioColors.line), borderRadius: BorderRadius.circular(PavioRadius.card))
            : null,
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? PavioColors.ink500),
            const SizedBox(width: PavioSpacing.s12),
            Expanded(child: Text(label, style: PavioText.body.copyWith(color: labelColor))),
            trailing ?? Icon(Icons.chevron_right, color: PavioColors.ink500),
          ],
        ),
      ),
    );
  }
}

/// One card grouping several [PavioMenuRow]s (each with `showCard: false`, since this
/// container already supplies the white background/border/radius) with a plain [Divider]
/// standing in for the per-row border the rows would otherwise need for separation. An
/// optional [title] labels the group — pass null to use this purely as an unlabeled list
/// card (e.g. HomeScreen's "Everything else").
class PavioMenuGroupCard extends StatelessWidget {
  const PavioMenuGroupCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(color: PavioColors.white, border: Border.all(color: PavioColors.line), borderRadius: BorderRadius.circular(PavioRadius.card)),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[children[i], if (i != children.length - 1) const Divider(height: 1)],
        ],
      ),
    );
    if (title == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(title!, style: PavioText.label.copyWith(color: PavioColors.ink500)), const SizedBox(height: PavioSpacing.s8), card],
    );
  }
}
