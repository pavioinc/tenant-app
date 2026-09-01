import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_password_field.dart';
import 'auth_repository.dart';
import 'login_screen.dart';

/// Second half of the forgot-password flow — [ForgotPasswordScreen] pushes here after
/// requesting a reset code. No deep-link handling yet (see auth-service's
/// TENANT_PASSWORD_RESET_URL comment): the renter copies the code out of the email by
/// hand into [_tokenController], same as a one-time-passcode flow. A real `nivasaos://`
/// link handler can pre-fill this field later without changing anything else here.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _tokenError;
  String? _passwordError;
  String? _confirmError;
  bool _submitting = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Mirrors auth-service's isStrongEnough() exactly, same as signup_screen.dart's own
  // copy — a password that passes here is guaranteed to pass server-side too.
  bool _isStrongPassword(String value) => RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$').hasMatch(value);

  Future<void> _submit() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    setState(() {
      _tokenError = token.isEmpty ? 'Enter the reset code from your email' : null;
      _passwordError = _isStrongPassword(password) ? null : 'Password does not meet the requirements below';
      _confirmError = confirm != password ? 'Passwords do not match' : null;
    });
    if (_tokenError != null || _passwordError != null || _confirmError != null) return;

    setState(() => _submitting = true);
    try {
      await _auth.resetPassword(token: token, newPassword: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated — log in with your new password')));
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen(authRepository: _auth)), (route) => false);
    } on ApiException catch (e) {
      setState(() {
        if (e.code == 'invalid_token') {
          _tokenError = 'This code is invalid or has expired — request a new one';
        } else if (e.code == 'weak_password') {
          _passwordError = e.message;
        } else {
          _tokenError = e.message;
        }
      });
    } catch (_) {
      setState(() => _tokenError = 'Network error — check your connection and try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Enter the code we emailed you, along with your new password.",
                style: NivasaText.body.copyWith(color: NivasaColors.ink500),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Reset code', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _tokenController,
                style: NivasaText.body,
                decoration: InputDecoration(hintText: 'Paste the code from your email', errorText: _tokenError),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('New password', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              NivasaPasswordField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'Enter a new password',
                errorText: _passwordError,
              ),
              const SizedBox(height: NivasaSpacing.s8),
              Text('Minimum 8 characters, 1 lowercase letter, 1 uppercase letter, 1 number, and 1 special character', style: NivasaText.caption),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Confirm new password', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              NivasaPasswordField(
                controller: _confirmController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'Re-enter new password',
                errorText: _confirmError,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(label: 'Reset password', loading: _submitting, loadingLabel: 'Resetting…', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
