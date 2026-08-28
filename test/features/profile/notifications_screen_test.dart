import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivasaos_tenant_app/features/profile/notifications_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

void main() {
  testWidgets('shows the informational channel cards, no fake toggles', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: NivasaTheme.light(), home: const NotificationsScreen()));

    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('WhatsApp & SMS reminders'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}
