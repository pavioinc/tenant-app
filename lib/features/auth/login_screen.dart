import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';
import '../../widgets/pavio_logo.dart';
import '../../widgets/pavio_password_field.dart';
import '../home/home_screen.dart';
import 'auth_repository.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

/// Entry point for a returning renter — email + password against the general Pavio
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
          padding: const EdgeInsets.symmetric(horizontal: PavioSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: PavioSpacing.s48),
              Row(
                children: [
                  const PavioLogoMark(size: 40),
                  const SizedBox(width: PavioSpacing.s12),
                  Text('Pavio', style: PavioText.h2.copyWith(color: PavioColors.primary800)),
                ],
              ),
              const SizedBox(height: PavioSpacing.s32),
              Text('Welcome back', style: PavioText.h1),
              const SizedBox(height: PavioSpacing.s8),
              Text('Log in to pay rent, raise complaints, and manage your stay.', style: PavioText.body.copyWith(color: PavioColors.ink500)),
              const SizedBox(height: PavioSpacing.s24),
              Text('Email', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: PavioText.body,
                decoration: const InputDecoration(hintText: 'you@example.com'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: PavioSpacing.s16),
              Text('Password', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              PavioPasswordField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.password],
                hintText: 'Your password',
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(authRepository: _auth))),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: PavioSpacing.s8),
              PavioPrimaryButton(label: 'Log in', loading: _submitting, loadingLabel: 'Logging in…', onPressed: _submit),
              const SizedBox(height: PavioSpacing.s16),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignupScreen(authRepository: _auth))),
                  child: const Text('New to Pavio? Create an account'),
                ),
              ),
              const SizedBox(height: PavioSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}
