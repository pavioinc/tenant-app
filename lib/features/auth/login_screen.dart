import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_logo.dart';
import '../home/home_screen.dart';
import 'auth_repository.dart';
import 'signup_screen.dart';

/// Entry point for a returning renter — email + password against the general NivasaOS
/// platform account (see auth_repository.dart). New renters use [SignupScreen] instead;
/// there is no phone/OTP path anymore.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await _auth.login(email: email, password: password);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => HomeScreen(authRepository: _auth)), (route) => false);
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: NivasaSpacing.s48),
              Row(
                children: [
                  const NivasaLogoMark(size: 40),
                  const SizedBox(width: NivasaSpacing.s12),
                  Text('NivasaOS', style: NivasaText.h2.copyWith(color: NivasaColors.primary800)),
                ],
              ),
              const SizedBox(height: NivasaSpacing.s32),
              Text('Welcome back', style: NivasaText.h1),
              const SizedBox(height: NivasaSpacing.s8),
              Text('Log in to pay rent, raise complaints, and manage your stay.', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Email', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'you@example.com'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Password', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                style: NivasaText.body,
                decoration: InputDecoration(hintText: 'Your password', errorText: _error),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(label: 'Log in', loading: _submitting, loadingLabel: 'Logging in…', onPressed: _submit),
              const SizedBox(height: NivasaSpacing.s16),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignupScreen(authRepository: _auth))),
                  child: const Text('New to NivasaOS? Create an account'),
                ),
              ),
              const SizedBox(height: NivasaSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}
