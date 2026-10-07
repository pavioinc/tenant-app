import 'package:flutter/material.dart';
import '../theme/pavio_colors.dart';
import '../theme/pavio_spacing.dart';
import '../theme/pavio_text_styles.dart';

/// The empty state as a first screen (doc option "1g") — centred icon, headline, one
/// sentence saying what the feature is for and who can see it, and the action under the
/// thumb — replacing the one-line grey sentence top-left of an empty page quoting a FAB
/// in the opposite corner (finding ST-3, repeated identically across all six list
/// screens). First wired into Guests; the other five (Documents, Vehicles, Contacts,
/// Maintenance, ...) can adopt the same widget without re-deriving this layout.
class PavioEmptyState extends StatelessWidget {
  const PavioEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionIcon,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 40,
          vertical: PavioSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: PavioColors.primary50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: PavioColors.primary700),
            ),
            const SizedBox(height: PavioSpacing.s24 - 2),
            Text(title, style: PavioText.h2, textAlign: TextAlign.center),
            const SizedBox(height: PavioSpacing.s8 + 2),
            Text(
              message,
              style: PavioText.body.copyWith(color: PavioColors.ink700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PavioSpacing.s24 + 2),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 20),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
