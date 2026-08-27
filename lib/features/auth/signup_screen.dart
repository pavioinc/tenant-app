import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_password_field.dart';
import '../home/home_screen.dart';
import 'auth_repository.dart';
import 'login_screen.dart';

/// General, standalone NivasaOS platform signup for renters — first/last name, email,
/// password, and an optional birthdate, independent of any org/property (see
/// auth_repository.dart). A fresh account starts unconnected; [HomeScreen] prompts the
/// renter to ask their property manager to add them, and connects automatically once
/// that happens. The email-associated-with-your-lease banner below is guidance only —
/// signup itself is deliberately permissive and never blocks on it (see auth-service's
/// tenantAuth.ts).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthdateController = TextEditingController();
  final _passwordController = TextEditingController();
  DateTime? _birthdate;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  // Mirrors auth-service's isStrongEnough() exactly, so a password that passes here is
  // guaranteed to pass server-side too — matches the hint caption shown below the field.
  bool _isStrongPassword(String value) =>
      RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$').hasMatch(value);

  String _formatBirthdate(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';

  String _isoBirthdate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthdate = picked;
        _birthdateController.text = _formatBirthdate(picked);
      });
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final password = _passwordController.text;

    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (firstName.isEmpty) {
      setState(() => _error = 'Enter your first name');
      return;
    }
    if (lastName.isEmpty) {
      setState(() => _error = 'Enter your last name');
      return;
    }
    if (!_isStrongPassword(password)) {
      setState(() => _error = 'Password does not meet the requirements below');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await _auth.signup(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        birthdate: _birthdate == null ? null : _isoBirthdate(_birthdate!),
      );
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
      appBar: AppBar(leading: const BackButton(), title: const Text('Create an Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s24, vertical: NivasaSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(NivasaSpacing.s16),
                decoration: BoxDecoration(
                  color: NivasaColors.warningTint,
                  border: Border.all(color: NivasaColors.warningTintBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Please Note: You must use the email address associated with your lease.',
                      style: NivasaText.body.copyWith(color: NivasaColors.warningTextOnTint, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: NivasaSpacing.s8),
                    Text(
                      "This is how we get you connected to your property. Please contact your property manager if you don't recall which email address you used when applying.",
                      style: NivasaText.body.copyWith(color: NivasaColors.warningTextOnTint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Email Associated With Your Lease', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'example@email.com'),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('First Name', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _firstNameController,
                autofillHints: const [AutofillHints.givenName],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'John'),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Last Name', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                controller: _lastNameController,
                autofillHints: const [AutofillHints.familyName],
                style: NivasaText.body,
                decoration: const InputDecoration(hintText: 'Smith'),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Birthdate (Optional)', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              TextField(
                readOnly: true,
                onTap: _submitting ? null : _pickBirthdate,
                style: NivasaText.body,
                controller: _birthdateController,
                decoration: const InputDecoration(
                  hintText: 'MM/dd/yyyy',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                ),
              ),
              const SizedBox(height: NivasaSpacing.s16),
              Text('Password', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s8),
              NivasaPasswordField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'Enter your password',
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NivasaSpacing.s8),
              Text(
                'Minimum 8 characters, 1 lowercase letter, 1 uppercase letter, 1 number, and 1 special character',
                style: NivasaText.caption,
              ),
              const SizedBox(height: NivasaSpacing.s24),
              NivasaPrimaryButton(label: 'Create Account', loading: _submitting, loadingLabel: 'Creating…', onPressed: _submit),
              const SizedBox(height: NivasaSpacing.s16),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen(authRepository: _auth))),
                  child: Text.rich(
                    TextSpan(
                      style: NivasaText.body.copyWith(color: NivasaColors.ink700),
                      children: const [TextSpan(text: 'Already have an account? '), TextSpan(text: 'Log In', style: TextStyle(decoration: TextDecoration.underline))],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
