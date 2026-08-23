import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../auth/auth_repository.dart';
import 'kyc_repository.dart';

enum _KycStep { enterAadhaar, enterOtp }

/// Two-step Aadhaar OTP verification, pushed from ProfileScreen. Plain TextFields
/// throughout — matches login_screen.dart's existing style; there's no reusable 6-box
/// OTP-entry widget in this app to inherit (login moved to email+password only).
/// Pops `true` on success so the caller can refresh its own status.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key, this.authRepository, this.kycRepository});

  final AuthRepository? authRepository;
  final KycRepository? kycRepository;

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final KycRepository _kyc = widget.kycRepository ?? KycRepository();
  final _aadhaarController = TextEditingController();
  final _codeController = TextEditingController();

  _KycStep _step = _KycStep.enterAadhaar;
  String? _token;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _aadhaarController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final aadhaar = _aadhaarController.text.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(aadhaar)) {
      setState(() => _error = 'Enter your 12-digit Aadhaar number');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await _auth.currentSession();
      if (session == null) throw StateError('no active session');
      _token = session.accessToken;
      await _kyc.requestOtp(_token!, aadhaarNumber: aadhaar);
      if (!mounted) return;
      setState(() => _step = _KycStep.enterOtp);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not send the OTP — check your connection and try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the OTP');
      return;
    }
    if (_token == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _kyc.verifyOtp(_token!, code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not verify — check your connection and try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identity verification')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _step == _KycStep.enterAadhaar ? _aadhaarStep() : _otpStep()),
        ),
      ),
    );
  }

  List<Widget> _aadhaarStep() {
    return [
      Text('Verify with Aadhaar', style: NivasaText.h1),
      const SizedBox(height: NivasaSpacing.s8),
      Text(
        "We'll send a one-time code to verify your identity. Your full Aadhaar number is never stored — only the last 4 digits.",
        style: NivasaText.body.copyWith(color: NivasaColors.ink500),
      ),
      const SizedBox(height: NivasaSpacing.s24),
      Text('Aadhaar number', style: NivasaText.label),
      const SizedBox(height: NivasaSpacing.s8),
      TextField(
        key: const Key('aadhaar-field'),
        controller: _aadhaarController,
        keyboardType: TextInputType.number,
        maxLength: 12,
        style: NivasaText.body,
        decoration: InputDecoration(hintText: '123456789012', errorText: _error, counterText: ''),
        onSubmitted: (_) => _requestOtp(),
      ),
      const SizedBox(height: NivasaSpacing.s24),
      NivasaPrimaryButton(label: 'Send OTP', loading: _submitting, loadingLabel: 'Sending…', onPressed: _requestOtp),
    ];
  }

  List<Widget> _otpStep() {
    return [
      Text('Enter the OTP', style: NivasaText.h1),
      const SizedBox(height: NivasaSpacing.s8),
      Text('Enter the 6-digit code sent to verify your Aadhaar.', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
      const SizedBox(height: NivasaSpacing.s24),
      Text('OTP', style: NivasaText.label),
      const SizedBox(height: NivasaSpacing.s8),
      TextField(
        key: const Key('otp-field'),
        controller: _codeController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        style: NivasaText.body,
        decoration: InputDecoration(hintText: '123456', errorText: _error, counterText: ''),
        onSubmitted: (_) => _verifyOtp(),
      ),
      const SizedBox(height: NivasaSpacing.s16),
      NivasaPrimaryButton(label: 'Verify', loading: _submitting, loadingLabel: 'Verifying…', onPressed: _verifyOtp),
      const SizedBox(height: NivasaSpacing.s12),
      Center(
        child: TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() {
                  _step = _KycStep.enterAadhaar;
                  _error = null;
                }),
          child: const Text('Use a different Aadhaar number'),
        ),
      ),
    ];
  }
}
