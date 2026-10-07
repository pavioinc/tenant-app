import 'package:flutter/material.dart';
import '../core/date_utils.dart';
import '../theme/pavio_colors.dart';
import '../theme/pavio_spacing.dart';
import '../theme/pavio_text_styles.dart';

/// Shown pinned above a screen's scrolling content when it's rendering a cached response
/// instead of a fresh one — see `fetchWithCache` in core/cached_fetch.dart. Every screen
/// places this the same way now (2026-08-31: outside the scrollable, directly above
/// RefreshIndicator/ListView — it used to drift between "pinned" and "scrolls away with
/// the list" screen by screen). [onRetry] gives it an explicit action alongside
/// pull-to-refresh, which is invisible and unavailable while a load is in flight.
class PavioStaleBanner extends StatelessWidget {
  const PavioStaleBanner({super.key, required this.lastSyncedAt, required this.onRetry});

  final DateTime? lastSyncedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final when = lastSyncedAt != null ? formatSyncedAt(lastSyncedAt!) : 'earlier';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PavioSpacing.s12),
      decoration: BoxDecoration(
        color: PavioColors.offlineTint,
        border: Border.all(color: PavioColors.offlineTintBorder),
        borderRadius: BorderRadius.circular(PavioRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing saved data from $when — check your connection',
              style: PavioText.bodySmall.copyWith(color: PavioColors.offlineTextOnTint),
            ),
          ),
          const SizedBox(width: PavioSpacing.s8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: PavioColors.offlineTextOnTint,
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: PavioSpacing.s8),
              textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
