import 'package:flutter/material.dart';
import '../../core/session_store.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_menu_row.dart';
import '../auth/auth_repository.dart';
import '../contacts/contacts_screen.dart';
import '../documents/documents_screen.dart';
import '../guests/guests_screen.dart';
import '../kyc/kyc_repository.dart';
import '../lease/lease_screen.dart';
import '../vehicles/vehicles_screen.dart';
import 'user_screen.dart';

/// Me tab of the bottom-tab shell — design review option "1a"'s fourth destination.
/// Leads with the renter's identity (name + KYC status, per the wireframe's "Profile &
/// KYC" screen) and folds in everything that isn't one of the other three tabs: Lease
/// (renewal lives here, not on its own tab), Documents, Guests, Vehicles, Contacts, and
/// the full Account menu (settings, notifications, sign out — still its own screen,
/// UserScreen, since that menu is long enough to want one).
class MeTab extends StatefulWidget {
  const MeTab({super.key, this.authRepository, this.kycRepository});

  final AuthRepository? authRepository;
  final KycRepository? kycRepository;

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final KycRepository _kyc = widget.kycRepository ?? KycRepository();

  TenantUser? _user;
  KycStatus? _kycStatus;

  @override
  void initState() {
    super.initState();
    _auth.currentSession().then((session) {
      if (!mounted || session == null) return;
      setState(() => _user = session.user);
      // Fire-and-forget, same contract as every other KYC-badge read in this app
      // (UserScreen's own _loadKycStatus) — a slow or failed check just leaves the
      // header without a badge rather than blocking the rest of the tab.
      _kyc
          .status(session.accessToken)
          .then((status) {
            if (mounted) setState(() => _kycStatus = status);
          })
          .catchError((_) {});
    }).catchError((_) {});
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar — "Me" already labels this tab in the bottom nav, and the profile row
    // below (avatar + name) is header enough, same convention HomeTab uses.
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PavioSpacing.s24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: PavioColors.primary100,
                  child: Text(
                    (_user?.name.isNotEmpty ?? false)
                        ? _user!.name[0].toUpperCase()
                        : '…',
                    style: PavioText.h2.copyWith(color: PavioColors.primary700),
                  ),
                ),
                const SizedBox(width: PavioSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_user?.name ?? '…', style: PavioText.h3),
                      const SizedBox(height: PavioSpacing.s4),
                      _KycChip(status: _kycStatus),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: PavioSpacing.s24),
            Text('Manage', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s12),
            PavioMenuGroupCard(
              children: [
                PavioMenuRow(
                  icon: Icons.home_work_outlined,
                  label: 'Lease',
                  showCard: false,
                  onTap: () => _push(LeaseScreen(authRepository: _auth)),
                ),
                PavioMenuRow(
                  icon: Icons.description_outlined,
                  label: 'Documents',
                  showCard: false,
                  onTap: () => _push(DocumentsScreen(authRepository: _auth)),
                ),
                PavioMenuRow(
                  icon: Icons.person_add_alt_outlined,
                  label: 'Guests',
                  showCard: false,
                  onTap: () => _push(GuestsScreen(authRepository: _auth)),
                ),
                PavioMenuRow(
                  icon: Icons.directions_car_outlined,
                  label: 'Vehicles',
                  showCard: false,
                  onTap: () => _push(VehiclesScreen(authRepository: _auth)),
                ),
                PavioMenuRow(
                  icon: Icons.contacts_outlined,
                  label: 'Contacts',
                  showCard: false,
                  onTap: () => _push(ContactsScreen(authRepository: _auth)),
                ),
              ],
            ),
            const SizedBox(height: PavioSpacing.s24),
            Text('Account', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s12),
            PavioMenuGroupCard(
              children: [
                PavioMenuRow(
                  icon: Icons.person_outline,
                  label: 'Your account',
                  showCard: false,
                  onTap: () => _push(UserScreen(authRepository: _auth)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small status chip under the renter's name — "KYC verified ✓" per the design doc's
/// Aadhaar KYC flow, using the same status-badge vocabulary (tint + icon + label) as
/// every other status surface in the app. Reads null while the check is still in flight
/// or failed, same degrade-quietly contract as the rest of this tab.
class _KycChip extends StatelessWidget {
  const _KycChip({required this.status});

  final KycStatus? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox(height: 20);
    final verified = status!.isVerified;
    final fg = verified ? PavioColors.positiveTextOnTint : PavioColors.warningTextOnTint;
    final bg = verified ? PavioColors.positiveTint : PavioColors.warningTint;
    final border = verified ? PavioColors.positiveTintBorder : PavioColors.warningTintBorder;
    final icon = verified ? Icons.check_circle : Icons.schedule;
    final label = verified ? 'KYC verified' : 'KYC pending';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PavioSpacing.s8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(PavioRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: PavioSpacing.s4),
          Text(label, style: PavioText.badge.copyWith(color: fg)),
        ],
      ),
    );
  }
}
