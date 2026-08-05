import 'package:flutter/material.dart';
import '../../core/session_store.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_logo.dart';
import '../auth/auth_repository.dart';
import '../auth/login_screen.dart';

class _MenuItem {
  const _MenuItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

const _menuItems = [
  _MenuItem(Icons.payments_outlined, 'Pay rent'),
  _MenuItem(Icons.report_problem_outlined, 'Complaints'),
  _MenuItem(Icons.autorenew, 'Renewal'),
  _MenuItem(Icons.person_outline, 'Profile'),
];

/// Renter's home — always shows the menu shell regardless of connection status. An
/// unconnected renter (signed up but not yet added by a property manager, see
/// auth_repository.dart) sees a prompt instead of live data; a silent connection check
/// runs on load so a renter who was linked while the app was closed sees it reflected
/// immediately, with a manual "Check again" action as a fallback. Pay rent, complaints,
/// renewal, and profile aren't built yet — tapping a menu tile surfaces that rather than
/// pretending it works.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  TenantUser? _user;
  bool _checkingConnection = false;

  @override
  void initState() {
    super.initState();
    _auth.currentSession().then((session) {
      if (!mounted) return;
      setState(() => _user = session?.user);
      if (session != null && !session.user.connected) {
        _checkConnection(silent: true);
      }
    });
  }

  Future<void> _checkConnection({bool silent = false}) async {
    if (_checkingConnection) return;
    setState(() => _checkingConnection = true);
    try {
      final session = await _auth.refreshConnectionStatus();
      if (!mounted) return;
      setState(() => _user = session.user);
      if (!silent && session.user.connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You're connected to your property!")));
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not connected yet — check back after your manager adds you.')));
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check connection — try again')));
      }
    } finally {
      if (mounted) setState(() => _checkingConnection = false);
    }
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  void _onMenuTap(_MenuItem item) {
    final connected = _user?.connected ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          connected ? '${item.label} is coming soon' : 'Connect with your property manager first to use ${item.label.toLowerCase()}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _user?.connected ?? false;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _checkConnection(silent: true),
          child: ListView(
            padding: const EdgeInsets.all(NivasaSpacing.s24),
            children: [
              Row(
                children: [
                  const NivasaLogoMark(size: 36),
                  const SizedBox(width: NivasaSpacing.s12),
                  Text('NivasaOS', style: NivasaText.h3.copyWith(color: NivasaColors.primary800)),
                  const Spacer(),
                  TextButton(onPressed: _logout, child: const Text('Log out')),
                ],
              ),
              const SizedBox(height: NivasaSpacing.s32),
              Text('Namaskaram 🙏', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s4),
              Text(_user?.name ?? '…', style: NivasaText.h1),
              const SizedBox(height: NivasaSpacing.s24),
              if (!connected) _ConnectPrompt(checking: _checkingConnection, onCheck: () => _checkConnection()),
              if (!connected) const SizedBox(height: NivasaSpacing.s24),
              Text('Menu', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s12),
              ..._menuItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: NivasaSpacing.s12),
                  child: _MenuTile(item: item, enabled: connected, onTap: () => _onMenuTap(item)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt({required this.checking, required this.onCheck});

  final bool checking;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(
        color: NivasaColors.infoTint,
        border: Border.all(color: NivasaColors.infoTintBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect with your property manager', style: NivasaText.h3.copyWith(color: NivasaColors.infoTextOnTint)),
          const SizedBox(height: NivasaSpacing.s8),
          Text(
            "Ask your property manager to add you using the email you signed up with. Once they do, this app connects automatically — no code to enter.",
            style: NivasaText.body.copyWith(color: NivasaColors.infoTextOnTint, fontSize: 14),
          ),
          const SizedBox(height: NivasaSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: checking ? null : onCheck,
              child: checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Check again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.enabled, required this.onTap});

  final _MenuItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(NivasaSpacing.s16),
          decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(item.icon, color: NivasaColors.primary700),
              const SizedBox(width: NivasaSpacing.s12),
              Text(item.label, style: NivasaText.body),
              const Spacer(),
              if (!enabled) Icon(Icons.lock_outline, size: 18, color: NivasaColors.ink400),
            ],
          ),
        ),
      ),
    );
  }
}
