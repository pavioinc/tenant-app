import 'package:flutter/material.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';

/// UserScreen's "Notifications" row. Deliberately read-only — notification-service only
/// has a device-token register/unregister API (see push_notifications.dart); there is no
/// per-category preferences endpoint to back real toggles yet (confirmed 2026-08-27), and
/// this app doesn't ship fake switches that don't persist anywhere. Once a preferences API
/// exists, this becomes the natural place to wire it up.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          children: [
            Text(
              "Per-notification controls aren't available yet — here's what's on today.",
              style: NivasaText.body.copyWith(color: NivasaColors.ink500),
            ),
            const SizedBox(height: NivasaSpacing.s24),
            const _ChannelCard(
              icon: Icons.notifications_active_outlined,
              title: 'Push notifications',
              description: 'Sent to this device when your property manager or the app has an update for you, if you granted permission on install.',
            ),
            const SizedBox(height: NivasaSpacing.s12),
            const _ChannelCard(
              icon: Icons.chat_outlined,
              title: 'WhatsApp & SMS reminders',
              description: 'Rent-due reminders go to your registered phone number automatically — this can’t be turned off from the app yet.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: NivasaColors.primary700),
          const SizedBox(width: NivasaSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: NivasaText.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: NivasaSpacing.s4),
                Text(description, style: NivasaText.body.copyWith(color: NivasaColors.ink500, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
