import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';
import '../../widgets/pavio_password_field.dart';
import '../auth/auth_repository.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _currentError;
  String? _newError;
  String? _confirmError;
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    setState(() {
      _currentError = current.isEmpty ? 'Enter your current password' : null;
      _newError = next.length < 8 ? 'Must be at least 8 characters' : null;
      _confirmError = confirm != next ? 'Passwords do not match' : null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) return;

    setState(() => _submitting = true);
    try {
      await _auth.changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() {
        if (e.code == 'invalid_password') {
          _currentError = 'Current password is incorrect';
        } else {
          _currentError = e.message;
        }
      });
    } catch (_) {
      setState(() => _currentError = 'Network error — check your connection and try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PavioSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current password', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              PavioPasswordField(
                controller: _currentController,
                autofillHints: const [AutofillHints.password],
                hintText: 'Your current password',
                errorText: _currentError,
              ),
              const SizedBox(height: PavioSpacing.s16),
              Text('New password', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              PavioPasswordField(
                controller: _newController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'At least 8 characters',
                errorText: _newError,
              ),
              const SizedBox(height: PavioSpacing.s16),
              Text('Confirm new password', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              PavioPasswordField(
                controller: _confirmController,
                autofillHints: const [AutofillHints.newPassword],
                hintText: 'Re-enter new password',
                errorText: _confirmError,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: PavioSpacing.s24),
              PavioPrimaryButton(label: 'Update password', loading: _submitting, loadingLabel: 'Updating…', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
