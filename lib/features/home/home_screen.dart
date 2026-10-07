import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date_utils.dart';
import '../../core/session_store.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_elevation.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_logo.dart';
import '../../widgets/pavio_menu_row.dart';
import '../auth/auth_repository.dart';
import '../profile/user_screen.dart';
import '../lease/lease_screen.dart';
import '../rental/rental_repository.dart';
import '../complaints/complaints_screen.dart';
import '../complaints/complaints_repository.dart';
import '../contacts/contacts_screen.dart';
import '../vehicles/vehicles_screen.dart';
import '../guests/guests_screen.dart';
import '../documents/documents_screen.dart';
import '../documents/documents_repository.dart';
import '../payments/payments_screen.dart';
import '../payments/payments_repository.dart';

typedef _ScreenBuilder = Widget Function(AuthRepository auth);

class _MenuItem {
  const _MenuItem(this.icon, this.label, {this.screenBuilder});
  final IconData icon;
  final String label;
  final _ScreenBuilder? screenBuilder;
}

/// Each tile in both the connected Resident Hub / "Everything else" list and the
/// unconnected locked-pills row (`_AlmostThereCard`) dispatches through one of these
/// shared `_MenuItem` instances, so navigation and coming-soon handling only live once
/// (see `_onMenuTap`).
final _paymentsMenuItem = _MenuItem(
  Icons.receipt_long_outlined,
  'Payments',
  screenBuilder: (auth) => PaymentsScreen(authRepository: auth),
);
final _maintenanceMenuItem = _MenuItem(
  Icons.build_outlined,
  'Maintenance',
  screenBuilder: (auth) => ComplaintsScreen(authRepository: auth),
);
final _leaseMenuItem = _MenuItem(
  Icons.home_work_outlined,
  'Lease',
  screenBuilder: (auth) => LeaseScreen(authRepository: auth),
);
final _documentsMenuItem = _MenuItem(
  Icons.description_outlined,
  'Documents',
  screenBuilder: (auth) => DocumentsScreen(authRepository: auth),
);
final _guestsMenuItem = _MenuItem(
  Icons.person_add_alt_outlined,
  'Guests',
  screenBuilder: (auth) => GuestsScreen(authRepository: auth),
);
final _vehiclesMenuItem = _MenuItem(
  Icons.directions_car_outlined,
  'Vehicles',
  screenBuilder: (auth) => VehiclesScreen(authRepository: auth),
);
final _contactsMenuItem = _MenuItem(
  Icons.contacts_outlined,
  'Contacts',
  screenBuilder: (auth) => ContactsScreen(authRepository: auth),
);

/// All seven destinations, in the order the locked state's "Unlocks once you're
/// connected" chip row lists them (see `_AlmostThereCard`) — independent of how the
/// connected Resident Hub groups them into rich tiles vs. the "Everything else" list.
final _menuItems = [
  _contactsMenuItem,
  _documentsMenuItem,
  _guestsMenuItem,
  _maintenanceMenuItem,
  _leaseMenuItem,
  _vehiclesMenuItem,
  _paymentsMenuItem,
];

/// Renter's home. An unconnected renter (signed up but not yet added by a property
/// manager, see auth_repository.dart) sees a single "Almost there" card instead of the
/// menu — see `_AlmostThereCard` below; a silent connection check runs on load so a
/// renter who was linked while the app was closed sees it reflected immediately, with a
/// manual "Check again" action as a fallback. Tiles with no backend yet say so rather
/// than pretending to work; once connected, account details/settings/logout move into
/// the "Everything else" list (UserScreen), out of the header — see `build()`.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.authRepository,
    this.paymentsRepository,
    this.complaintsRepository,
    this.rentalRepository,
    this.documentsRepository,
  });

  final AuthRepository? authRepository;
  final PaymentsRepository? paymentsRepository;
  final ComplaintsRepository? complaintsRepository;
  final RentalRepository? rentalRepository;
  final DocumentsRepository? documentsRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

String _firstName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return '…';
  return fullName.trim().split(RegExp(r'\s+')).first;
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final PaymentsRepository _payments =
      widget.paymentsRepository ?? PaymentsRepository();
  late final ComplaintsRepository _complaints =
      widget.complaintsRepository ?? ComplaintsRepository();
  late final RentalRepository _rentals =
      widget.rentalRepository ?? RentalRepository();
  late final DocumentsRepository _documents =
      widget.documentsRepository ?? DocumentsRepository();

  TenantUser? _user;
  bool _checkingConnection = false;

  // Resident Hub tile summaries (doc option "1a") — each loads independently and
  // fails silently, same fire-and-forget contract as UserScreen's KYC badge: one
  // slow/failed service degrades its own tile to no subtitle rather than blocking
  // the rest of Home.
  int? _totalDue;
  String? _nextDueDate;
  int? _openComplaints;
  String? _leaseStatus;
  String? _leaseEndDate;
  int? _documentCount;

  @override
  void initState() {
    super.initState();
    _auth
        .currentSession()
        .then((session) {
          if (!mounted) return;
          setState(() => _user = session?.user);
          if (session == null) return;
          if (session.user.connected) {
            _loadSummary(session.accessToken);
          } else {
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
      if (session.user.connected) _loadSummary(session.accessToken);
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

  void _loadSummary(String token) {
    _loadPaymentsSummary(token);
    _loadComplaintsSummary(token);
    _loadLeaseSummary(token);
    _loadDocumentsSummary(token);
  }

  Future<void> _loadPaymentsSummary(String token) async {
    try {
      final invoices = await _payments.pendingInvoices(token);
      if (!mounted) return;
      setState(() {
        _totalDue = invoices.totalDue;
        _nextDueDate = invoices.invoices.isEmpty
            ? null
            : invoices.invoices.first.dueDate;
      });
    } catch (_) {
      // Non-fatal — tile just renders with no subtitle.
    }
  }

  Future<void> _loadComplaintsSummary(String token) async {
    try {
      final complaints = await _complaints.list(token);
      if (!mounted) return;
      setState(
        () => _openComplaints = complaints
            .where((c) => c.status != 'resolved')
            .length,
      );
    } catch (_) {
      // Non-fatal — see above.
    }
  }

  Future<void> _loadLeaseSummary(String token) async {
    try {
      final rental = await _rentals.fetch(token);
      if (!mounted) return;
      setState(() {
        _leaseStatus = rental.agreement?.status;
        _leaseEndDate = rental.agreement?.endDate;
      });
    } catch (_) {
      // Non-fatal — see above.
    }
  }

  Future<void> _loadDocumentsSummary(String token) async {
    try {
      final docs = await _documents.list(token);
      if (!mounted) return;
      setState(() => _documentCount = docs.length);
    } catch (_) {
      // Non-fatal — see above.
    }
  }

  void _openUserMenu() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserScreen(authRepository: _auth)),
    );
  }

  // Only ever called from a locked pill's would-be tap target — the connected Resident
  // Hub tiles below now navigate directly, each to its own real destination.
  void _onMenuTap(_MenuItem item) {
    if (item.screenBuilder != null) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => item.screenBuilder!(_auth)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.label} is coming soon')));
  }

  String? get _paymentsSubtitle {
    if (_totalDue == null) return null;
    if (_totalDue == 0) return 'All paid up';
    final due = '₹${(_totalDue! / 100).toStringAsFixed(0)} due';
    return _nextDueDate == null
        ? due
        : '$due · ${formatDisplayDate(_nextDueDate!)}';
  }

  String? get _maintenanceSubtitle {
    if (_openComplaints == null) return null;
    return _openComplaints == 0
        ? 'No open requests'
        : '$_openComplaints open request${_openComplaints == 1 ? '' : 's'}';
  }

  String? get _leaseSubtitle {
    if (_leaseStatus == null) return null;
    final status = _leaseStatus![0].toUpperCase() + _leaseStatus!.substring(1);
    return _leaseEndDate == null
        ? status
        : '$status · ends ${formatDisplayDate(_leaseEndDate!)}';
  }

  String? get _documentsSubtitle {
    if (_documentCount == null) return null;
    return _documentCount == 0
        ? 'No files yet'
        : '$_documentCount file${_documentCount == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _user?.connected ?? false;
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
                  // Account access lives in the "Everything else" list once connected
                  // (doc option "1a" — pulls it out of the header's far corner, TT-4);
                  // an unconnected renter still needs it here since _AlmostThereCard
                  // below has no other way to reach Sign out.
                  if (!connected)
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
              Text(
                connected ? (_user?.name ?? '…') : _firstName(_user?.name),
                style: PavioText.h1,
              ),
              const SizedBox(height: PavioSpacing.s24),
              if (!connected)
                _AlmostThereCard(
                  email: _user?.email,
                  checking: _checkingConnection,
                  onCheck: () => _checkConnection(),
                )
              else ...[
                Text('Resident Hub', style: PavioText.label),
                const SizedBox(height: PavioSpacing.s12),
                // Two IntrinsicHeight rows instead of GridView's fixed aspect ratio —
                // tile content (icon + two text lines) doesn't fit one aspect ratio
                // cleanly across every device width, so each tile sizes to its own
                // content and the row matches both tiles to the taller one.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.receipt_long_outlined,
                          iconBg: PavioColors.gold100,
                          iconColor: PavioColors.gold800,
                          title: 'Payments',
                          subtitle: _paymentsSubtitle,
                          subtitleColor: _totalDue != null && _totalDue! > 0
                              ? PavioColors.gold800
                              : null,
                          onTap: () => _onMenuTap(_paymentsMenuItem),
                        ),
                      ),
                      const SizedBox(width: PavioSpacing.s12),
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.build_outlined,
                          iconBg: PavioColors.primary50,
                          iconColor: PavioColors.primary700,
                          title: 'Maintenance',
                          subtitle: _maintenanceSubtitle,
                          onTap: () => _onMenuTap(_maintenanceMenuItem),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PavioSpacing.s12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.home_work_outlined,
                          iconBg: PavioColors.primary50,
                          iconColor: PavioColors.primary700,
                          title: 'Lease',
                          subtitle: _leaseSubtitle,
                          onTap: () => _onMenuTap(_leaseMenuItem),
                        ),
                      ),
                      const SizedBox(width: PavioSpacing.s12),
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.description_outlined,
                          iconBg: PavioColors.primary50,
                          iconColor: PavioColors.primary700,
                          title: 'Documents',
                          subtitle: _documentsSubtitle,
                          onTap: () => _onMenuTap(_documentsMenuItem),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PavioSpacing.s24),
                Text('Everything else', style: PavioText.label),
                const SizedBox(height: PavioSpacing.s12),
                PavioMenuGroupCard(
                  children: [
                    PavioMenuRow(
                      icon: Icons.person_add_alt_outlined,
                      label: 'Guests',
                      showCard: false,
                      onTap: () => _onMenuTap(_guestsMenuItem),
                    ),
                    PavioMenuRow(
                      icon: Icons.directions_car_outlined,
                      label: 'Vehicles',
                      showCard: false,
                      onTap: () => _onMenuTap(_vehiclesMenuItem),
                    ),
                    PavioMenuRow(
                      icon: Icons.contacts_outlined,
                      label: 'Contacts',
                      showCard: false,
                      onTap: () => _onMenuTap(_contactsMenuItem),
                    ),
                    PavioMenuRow(
                      icon: Icons.person_outline,
                      label: 'Your account',
                      showCard: false,
                      onTap: _openUserMenu,
                    ),
                  ],
                ),
              ],
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
            children: [for (final item in _menuItems) _LockedPill(item: item)],
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

/// Resident Hub rich tile (2026-08-31, doc option "1a") — replaces both the old empty
/// gradient "Pay Rent" banner (IA-2: had no due amount, since Home fetched nothing
/// tenant-specific) and the plain icon+label `_HubTile` row. [subtitle] is null while
/// its own summary fetch is in flight or failed — the tile still renders, just without
/// a second line, rather than blocking on or hiding for one slow service.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.card),
      child: Container(
        padding: const EdgeInsets.all(PavioSpacing.s12),
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const Spacer(),
            Text(
              title,
              style: PavioText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PavioSpacing.s4),
            Text(
              subtitle ?? '…',
              style: PavioText.caption.copyWith(
                color: subtitleColor ?? PavioColors.ink500,
                fontWeight: subtitleColor != null
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
