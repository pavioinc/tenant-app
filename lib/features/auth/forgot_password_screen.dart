import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import 'auth_repository.dart';
import 'reset_password_screen.dart';

/// First half of the forgot-password flow, reached from LoginScreen — see
/// ResetPasswordScreen for the code-entry half. auth-service's POST /password/forgot
/// always responds 200 regardless of whether the email matches an account (no
/// enumeration — see its own doc comment) and even once rate-limited, so a caught
/// [ApiException]/network failure here only ever means the request never reached the
/// server at all — worth a real error and staying put, not silently moving on.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _emailController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await _auth.requestPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("If that email has an account, we've sent a reset code.")));
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetPasswordScreen(authRepository: _auth)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error — check your connection and try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Enter the email you signed up with. If it has an account, we'll send a reset code.",
                style: NivasaText.body.copyWith(color: NivasaColors.ink500),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Email', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: NivasaText.body,
                decoration: InputDecoration(hintText: 'you@example.com', errorText: _error),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(label: 'Send reset code', loading: _submitting, loadingLabel: 'Sending…', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
