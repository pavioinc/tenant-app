import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../auth/auth_repository.dart';
import 'rental_repository.dart';

String _formatInr(int amountMinor) => '₹${(amountMinor / 100).toStringAsFixed(0)}';

/// The tenant-initiated e-sign flow (CLO-147-adjacent rental agreement work) — review
/// the agreement's key terms and full clause text in-app, type a full legal name, give
/// explicit consent, and submit. No PDF viewer dependency: the generated PDF (with its
/// signature block and legal disclaimer) is the durable record, retrievable later via
/// the agreement detail; this screen's job is just informed, explicit consent before
/// tenant-service renders and stores that PDF — see rental_repository.dart's
/// signAgreement and tenant-service's POST /tenant/me/agreements/:id/sign.
class AgreementSignScreen extends StatefulWidget {
  const AgreementSignScreen({super.key, required this.agreement, this.authRepository, this.rentalRepository});

  final Agreement agreement;
  final AuthRepository? authRepository;
  final RentalRepository? rentalRepository;

  @override
  State<AgreementSignScreen> createState() => _AgreementSignScreenState();
}

class _AgreementSignScreenState extends State<AgreementSignScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final RentalRepository _rentals = widget.rentalRepository ?? RentalRepository();
  final _nameController = TextEditingController();
  bool _agreed = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty && _agreed && !_submitting;

  Future<void> _submit() async {
    final session = await _auth.currentSession();
    if (session == null) {
      setState(() => _error = 'Your session expired — please log in again');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _rentals.signAgreement(session.accessToken, agreementId: widget.agreement.agreementId, signedByName: _nameController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not sign the agreement — try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agreement = widget.agreement;
    final clauses = agreement.terms.split('\n').where((line) => line.trim().isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Review & sign')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rental Agreement', style: NivasaText.h2),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Monthly rent', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s4),
              Text(_formatInr(agreement.monthlyRent), style: NivasaText.h3),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Security deposit', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s4),
              Text(_formatInr(agreement.securityDeposit), style: NivasaText.h3),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Term', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s4),
              Text(
                agreement.endDate != null ? '${agreement.startDate} to ${agreement.endDate}' : 'Since ${agreement.startDate}',
                style: NivasaText.body,
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Terms & Conditions', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s8),
              for (var i = 0; i < clauses.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: NivasaSpacing.s8),
                  child: Text('${i + 1}. ${clauses[i]}', style: NivasaText.body),
                ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Full legal name', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _nameController,
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'As it appears on your ID'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreed,
                    activeColor: NivasaColors.ink900,
                    onChanged: _submitting ? null : (v) => setState(() => _agreed = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: NivasaSpacing.s12),
                      child: Text('I have read and agree to the terms of this Rental Agreement.', style: NivasaText.body),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NivasaSpacing.s8),
              Text(
                'Typing your name above and submitting is a legally binding electronic signature under the Information Technology Act, 2000, Section 10A.',
                style: NivasaText.caption,
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(
                label: 'Sign & Submit',
                loading: _submitting,
                loadingLabel: 'Submitting…',
                onPressed: _canSubmit ? _submit : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: NivasaSpacing.s16),
                Text(_error!, style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
