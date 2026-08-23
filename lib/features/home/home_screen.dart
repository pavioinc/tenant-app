import 'package:flutter/material.dart';
import '../../core/session_store.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_logo.dart';
import '../auth/auth_repository.dart';
import '../profile/profile_screen.dart';
import '../lease/lease_screen.dart';
import '../complaints/complaints_screen.dart';
import '../contacts/contacts_screen.dart';
import '../vehicles/vehicles_screen.dart';
import '../guests/guests_screen.dart';
import '../documents/documents_screen.dart';
import '../payments/payments_screen.dart';

typedef _ScreenBuilder = Widget Function(AuthRepository auth);

class _MenuItem {
  const _MenuItem(this.icon, this.label, {this.screenBuilder});
  final IconData icon;
  final String label;
  final _ScreenBuilder? screenBuilder;
}

/// The "Payments" tile also backs the payment banner above the grid — both dispatch
/// through the same `_MenuItem` instance so tapping either goes through identical
/// connected-gating / coming-soon logic (see `_onMenuTap`).
final _paymentsMenuItem = _MenuItem(Icons.account_balance_wallet_outlined, 'Payments', screenBuilder: (auth) => PaymentsScreen(authRepository: auth));

/// Resident Hub grid (2026-08-18 redesign, replacing the old single-column menu).
/// Every tile now has a real screen — Contacts/Vehicles/Guest Manager/Documents/
/// Payments all got real backends in the direct follow-up arc; Maintenance and Lease
/// point at pre-existing screens (Complaints relabeled in its own UI, Lease merges the
/// former My rental + Renewal screens) — see tenant-app/README.md. The `_MenuItem`
/// mechanism itself (a nullable `screenBuilder`, "coming soon" if absent) stays in
/// place for whatever the next unbuilt tile turns out to be.
final _menuItems = [
  _MenuItem(Icons.contacts_outlined, 'Contacts', screenBuilder: (auth) => ContactsScreen(authRepository: auth)),
  _MenuItem(Icons.description_outlined, 'Documents', screenBuilder: (auth) => DocumentsScreen(authRepository: auth)),
  _MenuItem(Icons.person_add_alt_outlined, 'Guest Manager', screenBuilder: (auth) => GuestsScreen(authRepository: auth)),
  _MenuItem(Icons.build_outlined, 'Maintenance', screenBuilder: (auth) => ComplaintsScreen(authRepository: auth)),
  _MenuItem(Icons.home_work_outlined, 'Lease', screenBuilder: (auth) => LeaseScreen(authRepository: auth)),
  _MenuItem(Icons.directions_car_outlined, 'Vehicles', screenBuilder: (auth) => VehiclesScreen(authRepository: auth)),
  _paymentsMenuItem,
];

/// Renter's home — always shows the menu shell regardless of connection status. An
/// unconnected renter (signed up but not yet added by a property manager, see
/// auth_repository.dart) sees a prompt instead of live data; a silent connection check
/// runs on load so a renter who was linked while the app was closed sees it reflected
/// immediately, with a manual "Check again" action as a fallback. Tiles with no backend
/// yet say so rather than pretending to work; Profile/Settings/logout live behind the
/// header's person icon, not in the grid.
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
    _auth
        .currentSession()
        .then((session) {
          if (!mounted) return;
          setState(() => _user = session?.user);
          if (session != null && !session.user.connected) {
            _checkConnection(silent: true);
          }
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

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(authRepository: _auth)));
  }

  void _onMenuTap(_MenuItem item) {
    final connected = _user?.connected ?? false;
    if (!connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connect with your property manager first to use ${item.label.toLowerCase()}')));
      return;
    }
    if (item.screenBuilder != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.screenBuilder!(_auth)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.label} is coming soon')));
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
                  IconButton(
                    key: const Key('profile-button'),
                    icon: const Icon(Icons.person_outline),
                    tooltip: 'Profile',
                    onPressed: _openProfile,
                  ),
                ],
              ),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Namaskaram 🙏', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
              const SizedBox(height: NivasaSpacing.s4),
              Text(_user?.name ?? '…', style: NivasaText.h1),
              const SizedBox(height: NivasaSpacing.s24),
              if (!connected) _ConnectPrompt(checking: _checkingConnection, onCheck: () => _checkConnection()),
              if (!connected) const SizedBox(height: NivasaSpacing.s24),
              _PaymentBanner(enabled: connected, onTap: () => _onMenuTap(_paymentsMenuItem)),
              const SizedBox(height: NivasaSpacing.s24),
              Text('Resident Hub', style: NivasaText.label),
              const SizedBox(height: NivasaSpacing.s12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: NivasaSpacing.s12,
                crossAxisSpacing: NivasaSpacing.s12,
                childAspectRatio: 2.6,
                children: [
                  for (final item in _menuItems) _HubTile(item: item, enabled: connected, onTap: () => _onMenuTap(item)),
                ],
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

/// Deliberately doesn't pre-fetch and show a real due amount here — that would mean
/// HomeScreen doing its own tenant-specific data fetch on load, which nothing else on
/// this screen does today. The real total (payment-service's `GET
/// /tenant/me/invoices`) shows once inside `PaymentsScreen`, where it belongs with the
/// rest of that screen's own fetch — see tenant-app/README.md. A gradient `Container`,
/// not a photo — no image asset pipeline exists in this app.
class _PaymentBanner extends StatelessWidget {
  const _PaymentBanner({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(NivasaSpacing.s20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [NivasaColors.primary900, NivasaColors.primary700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay Rent', style: NivasaText.h3.copyWith(color: NivasaColors.white)),
                    const SizedBox(height: NivasaSpacing.s4),
                    Text('View & pay', style: NivasaText.body.copyWith(color: NivasaColors.white.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: NivasaColors.white, shape: BoxShape.circle),
                child: Icon(Icons.arrow_forward, size: 20, color: NivasaColors.primary700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({required this.item, required this.enabled, required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s16, vertical: NivasaSpacing.s12),
          decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(item.icon, color: NivasaColors.primary700, size: 20),
              const SizedBox(width: NivasaSpacing.s8),
              Expanded(child: Text(item.label, style: NivasaText.body, overflow: TextOverflow.ellipsis)),
              if (!enabled) Icon(Icons.lock_outline, size: 16, color: NivasaColors.ink400),
            ],
          ),
        ),
      ),
    );
  }
}
