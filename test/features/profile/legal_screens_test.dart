import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivasaos_tenant_app/features/profile/legal_screens.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

void main() {
  testWidgets('PrivacyPolicyScreen renders its sections', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: NivasaTheme.light(), home: const PrivacyPolicyScreen()));

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Information we collect'), findsOneWidget);
    expect(find.text('Contact us'), findsOneWidget);
  });

  testWidgets('TermsScreen renders its sections', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: NivasaTheme.light(), home: const TermsScreen()));

    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Using the app'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
  });
}
