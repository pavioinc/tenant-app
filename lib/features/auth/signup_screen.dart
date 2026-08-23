import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_logo.dart';
import '../../widgets/nivasa_password_field.dart';
import '../home/home_screen.dart';
import 'auth_repository.dart';

/// General, standalone NivasaOS platform signup for renters — full name, email, and
/// password, independent of any org/property (see auth_repository.dart). A fresh account
/// starts unconnected; [HomeScreen] prompts the renter to ask their property manager to
/// add them, and connects automatically once that happens.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (fullName.isEmpty) {
      setState(() => _error = 'Enter your full name');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await _auth.signup(fullName: fullName, email: email, password: password);
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
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const NivasaLogoMark(size: 40),
                  const SizedBox(width: NivasaSpacing.s12),
                  Text('NivasaOS', style: NivasaText.h2.copyWith(color: NivasaColors.primary800)),
                ],
              ),
              const SizedBox(height: NivasaSpacing.s32),
              Text('Create your account', style: NivasaText.h1),
              const SizedBox(height: NivasaSpacing.s8),
              Text(
                "You'll connect to your property once your manager adds your email — no need to wait for that first.",
                style: NivasaText.body.copyWith(color: NivasaColors.ink500),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Full name', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _fullNameController,
                autofillHints: const [AutofillHints.name],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'Amit Kumar'),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Email', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Password', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              NivasaPasswordField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'At least 8 characters',
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(label: 'Create account', loading: _submitting, loadingLabel: 'Creating…', onPressed: _submit),
              const SizedBox(height: NivasaSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}
