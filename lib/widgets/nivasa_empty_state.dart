import 'package:flutter/material.dart';
import '../theme/nivasa_colors.dart';
import '../theme/nivasa_spacing.dart';
import '../theme/nivasa_text_styles.dart';

/// The empty state as a first screen (doc option "1g") — centred icon, headline, one
/// sentence saying what the feature is for and who can see it, and the action under the
/// thumb — replacing the one-line grey sentence top-left of an empty page quoting a FAB
/// in the opposite corner (finding ST-3, repeated identically across all six list
/// screens). First wired into Guests; the other five (Documents, Vehicles, Contacts,
/// Maintenance, ...) can adopt the same widget without re-deriving this layout.
class NivasaEmptyState extends StatelessWidget {
  const NivasaEmptyState({
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
          vertical: NivasaSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: NivasaColors.primary50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: NivasaColors.primary700),
            ),
            const SizedBox(height: NivasaSpacing.s24 - 2),
            Text(title, style: NivasaText.h2, textAlign: TextAlign.center),
            const SizedBox(height: NivasaSpacing.s8 + 2),
            Text(
              message,
              style: NivasaText.body.copyWith(color: NivasaColors.ink700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NivasaSpacing.s24 + 2),
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
