import 'package:flutter/material.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';

/// Bundled placeholder legal copy, not fetched from a backend — no CMS/static-content
/// endpoint exists anywhere in the platform (checked 2026-08-27). This text has not been
/// legally reviewed; replace it with counsel-approved copy before a production release.
class _LegalScreen extends StatelessWidget {
  const _LegalScreen({required this.title, required this.sections});

  final String title;
  final List<(String, String)> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PavioSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Last updated 27 August 2026', style: PavioText.caption),
              const SizedBox(height: PavioSpacing.s24),
              for (final (heading, body) in sections) ...[
                Text(heading, style: PavioText.h3),
                const SizedBox(height: PavioSpacing.s8),
                Text(body, style: PavioText.body.copyWith(color: PavioColors.ink700)),
                const SizedBox(height: PavioSpacing.s24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Privacy Policy',
      sections: [
        (
          'Information we collect',
          'We collect the information you give us when you sign up and use the app — your name, contact details, property and lease information, payment records, '
              'and any documents you upload — along with basic device and usage information needed to keep the app working reliably.',
        ),
        (
          'How we use it',
          'We use your information to operate the app: connecting you to your property, processing rent payments, routing maintenance requests, and sending '
              'service notifications such as rent-due reminders. We don\'t sell your personal information.',
        ),
        (
          'Sharing',
          'Your information is shared with your property manager (as part of running your tenancy) and with service providers who help us operate the app, '
              'such as payment processors and cloud hosting. We share only what those providers need to do their job.',
        ),
        ('Your choices', 'You can review and update most of your details from the Account Details and Emergency Contacts screens at any time.'),
        ('Contact us', 'Questions about this policy can be sent to support@pavio.tech.'),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Terms & Conditions',
      sections: [
        (
          'Using the app',
          'This app is provided to residents connected to a property managed on Pavio. You\'re responsible for keeping your account credentials '
              'confidential and for the accuracy of the information you provide.',
        ),
        (
          'Payments',
          'Rent and other charges processed through the app are subject to the payment terms of your lease. Pavio facilitates the payment but is not a '
              'party to your lease agreement.',
        ),
        (
          'Acceptable use',
          'You agree not to misuse the app — including attempting to access another resident\'s data, submitting false maintenance requests, or interfering '
              'with the service.',
        ),
        ('Changes', 'We may update these terms from time to time; continued use of the app after a change means you accept the updated terms.'),
        ('Contact us', 'Questions about these terms can be sent to support@pavio.tech.'),
      ],
    );
  }
}
