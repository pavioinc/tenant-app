import 'package:flutter/material.dart';
import '../core/date_utils.dart';
import '../theme/nivasa_colors.dart';
import '../theme/nivasa_spacing.dart';
import '../theme/nivasa_text_styles.dart';

/// Shown at the top of a screen's content when it's rendering a cached response instead
/// of a fresh one — see `fetchWithCache` in core/cached_fetch.dart. Pull-to-refresh
/// (already on every screen that uses this) is the retry mechanism, so there's no button.
class NivasaStaleBanner extends StatelessWidget {
  const NivasaStaleBanner({super.key, required this.lastSyncedAt});

  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final when = lastSyncedAt != null ? formatSyncedAt(lastSyncedAt!) : 'earlier';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NivasaSpacing.s12),
      decoration: BoxDecoration(
        color: NivasaColors.offlineTint,
        border: Border.all(color: NivasaColors.offlineTintBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Showing saved data from $when — check your connection',
        style: NivasaText.body.copyWith(color: NivasaColors.offlineTextOnTint, fontSize: 13),
      ),
    );
  }
}
