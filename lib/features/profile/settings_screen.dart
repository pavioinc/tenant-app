import 'package:flutter/material.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../auth/auth_repository.dart';
import '../auth/login_screen.dart';
import 'change_password_screen.dart';

/// Reached from ProfileScreen's settings-gear action (2026-08-18 redesign) — logout used
/// to be a bare button on HomeScreen's header; it lives here now instead.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          children: [
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangePasswordScreen(authRepository: _auth))),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(NivasaSpacing.s16),
                decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: NivasaColors.ink500),
                    const SizedBox(width: NivasaSpacing.s12),
                    Text('Change password', style: NivasaText.body),
                    const Spacer(),
                    Icon(Icons.chevron_right, color: NivasaColors.ink500),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NivasaSpacing.s12),
            InkWell(
              onTap: _loggingOut ? null : _logout,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(NivasaSpacing.s16),
                decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.logout, color: NivasaColors.negativeFg),
                    const SizedBox(width: NivasaSpacing.s12),
                    Text('Log out', style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
                    const Spacer(),
                    if (_loggingOut) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
