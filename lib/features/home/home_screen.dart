import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/session_store.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_elevation.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_logo.dart';
import '../auth/auth_repository.dart';
import '../profile/user_screen.dart';
import '../shell/main_shell.dart';

class _MenuItem {
  const _MenuItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// The seven renter-facing areas, in the order the locked state's "Unlocks once you're
/// connected" chip row lists them (see `_AlmostThereCard`) — purely informational for an
/// unconnected renter, who has no real destination to tap yet. Once connected, these same
/// areas are reachable for real from `MainShell`'s tabs (Payments → Pay, Maintenance →
/// Help) or from the Me tab's menu (Lease, Documents, Guests, Vehicles, Contacts).
const _lockedAreas = [
  _MenuItem(Icons.contacts_outlined, 'Contacts'),
  _MenuItem(Icons.description_outlined, 'Documents'),
  _MenuItem(Icons.person_add_alt_outlined, 'Guests'),
  _MenuItem(Icons.build_outlined, 'Maintenance'),
  _MenuItem(Icons.home_work_outlined, 'Lease'),
  _MenuItem(Icons.directions_car_outlined, 'Vehicles'),
  _MenuItem(Icons.receipt_long_outlined, 'Payments'),
];

/// Renter's home-screen gate. An unconnected renter (signed up but not yet added by a
/// property manager, see auth_repository.dart) sees a single "Almost there" card instead
/// of the app proper — see `_AlmostThereCard` below; a silent connection check runs on
/// load so a renter who was linked while the app was closed sees it reflected
/// immediately, with a manual "Check again" action as a fallback. Once connected, this
/// hands off entirely to `MainShell`'s bottom-tab spine (design review option "1a") —
/// this widget's own job stops at "is this renter connected yet?".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

String _firstName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return '…';
  return fullName.trim().split(RegExp(r'\s+')).first;
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();

  TenantUser? _user;
  bool _checkingConnection = false;

  @override
  void initState() {
    super.initState();
    _auth
        .currentSession()
        .then((session) {
          if (!mounted) return;
          setState(() => _user = session?.user);
          if (session == null) return;
          if (!session.user.connected) _checkConnection(silent: true);
        })
        // currentSession() can now hit the network (proactively refreshing an
        // expiring access token, see auth_repository.dart) and so can fail — e.g. a
        // connectivity hiccup mid-refresh. Swallow it here rather than an unhandled
        // Future rejection; _user just stays null, same degraded-but-safe state as
        // if this hadn't finished yet. Pull-to-refresh (_checkConnection) already has
        // its own error handling and gives the renter a way to recover.
        .catchError((_) {});
  }

  Future<void> _checkConnection({bool silent = false}) async {
    if (_checkingConnection) return;
    setState(() => _checkingConnection = true);
    try {
      final session = await _auth.refreshConnectionStatus();
      if (!mounted) return;
      setState(() => _user = session.user);
      if (!silent && session.user.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're connected to your property!")),
        );
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not connected yet — check back after your manager adds you.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check connection — try again'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingConnection = false);
    }
  }

  void _openUserMenu() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserScreen(authRepository: _auth)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user?.connected ?? false) {
      return MainShell(authRepository: _auth);
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _checkConnection(silent: true),
          child: ListView(
            padding: const EdgeInsets.all(PavioSpacing.s24),
            children: [
              Row(
                children: [
                  const PavioLogoMark(size: 36),
                  const SizedBox(width: PavioSpacing.s12),
                  Text(
                    'Pavio',
                    style: PavioText.h3.copyWith(
                      color: PavioColors.primary800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('user-menu-button'),
                    icon: const Icon(Icons.person_outline),
                    tooltip: 'Account',
                    onPressed: _openUserMenu,
                  ),
                ],
              ),
              const SizedBox(height: PavioSpacing.s24),
              Text(
                'Namaskaram 🙏',
                style: PavioText.body.copyWith(color: PavioColors.ink500),
              ),
              const SizedBox(height: PavioSpacing.s4),
              // The locked state (1n) greets by first name only — "Amit", not
              // "Amit Kumar" — since the mock's hero heading is meant to read as
              // a single short word next to the emoji line above it.
              Text(_firstName(_user?.name), style: PavioText.h1),
              const SizedBox(height: PavioSpacing.s24),
              _AlmostThereCard(
                email: _user?.email,
                checking: _checkingConnection,
                onCheck: () => _checkConnection(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Redesigned locked state (2026-08-31, doc option "1n") — a fresh, unconnected account
/// has exactly one thing to do, so the screen shows exactly one card instead of the old
/// opacity-dimmed grid (which also failed contrast: 15px ink900 at 50% alpha on white is
/// ~2.3:1, below WCAG AA). The locked areas render as quiet chips, legible at full
/// opacity, instead of six disabled buttons each inviting its own SnackBar.
class _AlmostThereCard extends StatelessWidget {
  const _AlmostThereCard({
    required this.email,
    required this.checking,
    required this.onCheck,
  });

  final String? email;
  final bool checking;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PavioSpacing.s20),
      decoration: BoxDecoration(
        color: PavioColors.white,
        border: Border.all(color: PavioColors.line),
        borderRadius: BorderRadius.circular(PavioRadius.card),
        boxShadow: PavioElevation.e1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: PavioColors.infoTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.link,
              size: 26,
              color: PavioColors.infoTextOnTint,
            ),
          ),
          const SizedBox(height: PavioSpacing.s16),
          Text('Almost there', style: PavioText.h3),
          const SizedBox(height: PavioSpacing.s8),
          Text.rich(
            TextSpan(
              style: PavioText.body,
              children: [
                const TextSpan(
                  text:
                      'Your account is ready. Ask your property manager to add ',
                ),
                if (email != null)
                  TextSpan(
                    text: email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )
                else
                  const TextSpan(
                    text: 'you using the email you signed up with',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                const TextSpan(
                  text:
                      " to your room — the moment they do, everything here unlocks on its own. There's no code to enter.",
                ),
              ],
            ),
          ),
          const SizedBox(height: PavioSpacing.s16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 19),
              label: const Text('Check again'),
            ),
          ),
          if (email != null) ...[
            const SizedBox(height: PavioSpacing.s8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(ClipboardData(text: email!));
                  messenger?.showSnackBar(
                    const SnackBar(content: Text('Email address copied')),
                  );
                },
                child: Text(
                  'Copy my email address',
                  style: PavioText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: PavioColors.ink500,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: PavioSpacing.s20),
          Text(
            'UNLOCKS ONCE YOU\'RE CONNECTED',
            style: PavioText.caption.copyWith(
              color: PavioColors.ink500,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: PavioSpacing.s12),
          Wrap(
            spacing: PavioSpacing.s8,
            runSpacing: PavioSpacing.s8,
            children: [for (final item in _lockedAreas) _LockedPill(item: item)],
          ),
        ],
      ),
    );
  }
}

class _LockedPill extends StatelessWidget {
  const _LockedPill({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PavioSpacing.s12,
        vertical: PavioSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: PavioColors.offlineTint,
        borderRadius: BorderRadius.circular(PavioRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 15, color: PavioColors.offlineTextOnTint),
          const SizedBox(width: PavioSpacing.s4),
          Text(
            item.label,
            style: PavioText.bodySmall.copyWith(
              color: PavioColors.offlineTextOnTint,
            ),
          ),
        ],
      ),
    );
  }
}
