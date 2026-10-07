import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavio_tenant_app/features/profile/notifications_screen.dart';
import 'package:pavio_tenant_app/theme/pavio_theme.dart';

void main() {
  testWidgets('shows the informational channel cards, no fake toggles', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: PavioTheme.light(), home: const NotificationsScreen()));

    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('WhatsApp & SMS reminders'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}
