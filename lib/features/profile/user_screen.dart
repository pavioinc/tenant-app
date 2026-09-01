import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_menu_row.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../auth/login_screen.dart';
import '../kyc/kyc_repository.dart';
import 'account_details_screen.dart';
import 'app_feedback_screen.dart';
import 'emergency_contacts_screen.dart';
import 'legal_screens.dart';
import 'notifications_screen.dart';
import 'profile_repository.dart';

/// Reached from HomeScreen's header person icon (2026-08-27 redesign, replacing the old
/// ProfileScreen/SettingsScreen split) — one menu for identity, property, and app-level
/// settings, matching the reference design's "The Aire" resident-app user page. Everything
/// that used to be inline on ProfileScreen (edit phone/address, emergency contact, KYC) now
/// lives behind its own row/sub-screen; this screen itself only reads the profile, it never
/// edits it directly (except language, which the design shows inline).
class UserScreen extends StatefulWidget {
  const UserScreen({super.key, this.authRepository, this.profileRepository, this.kycRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final KycRepository? kycRepository;
  final CacheStore? cacheStore;

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ProfileRepository _profiles = widget.profileRepository ?? ProfileRepository();
  late final KycRepository _kyc = widget.kycRepository ?? KycRepository();
  // Same store/key as AccountDetailsScreen and EmergencyContactsScreen — one cached copy of
  // the tenant-self resource, not a per-screen fork of it. Secure, not SharedPreferences:
  // the cached payload carries PII (see cache_store.dart's SecureCacheStore doc).
  late final CacheStore _cache = widget.cacheStore ?? const SecureCacheStore();

  String? _token;
  TenantProfile? _profile;
  bool _loading = true;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;
  bool _propertyExpanded = false;
  String? _appVersion;
  KycStatus? _kycStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = 'Version ${info.version} (${info.buildNumber})');
    } catch (_) {
      // Non-fatal — the footer just stays blank.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _auth.currentSession();
      if (session == null) throw StateError('no active session');
      _token = session.accessToken;
      final result = await fetchWithCache<TenantProfile>(
        cache: _cache,
        cacheKey: 'profile',
        fetchNetwork: () => _profiles.fetch(_token!),
        toJson: (p) => p.toJson(),
        fromJson: (json) => TenantProfile.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() {
        _profile = result.data;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
      _loadKycStatus();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your profile — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fire-and-forget, same rationale as AccountDetailsScreen's: a failure here just
  /// leaves the Account Details row without a status badge instead of blocking the rest
  /// of this screen from loading.
  Future<void> _loadKycStatus() async {
    if (_token == null) return;
    try {
      final status = await _kyc.status(_token!);
      if (!mounted) return;
      setState(() => _kycStatus = status);
    } catch (_) {
      // Non-fatal — see comment above.
    }
  }

  Future<void> _pickLanguage() async {
    final profile = _profile;
    if (profile == null || _token == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(NivasaSpacing.s16),
              child: Text('Preferred language', style: NivasaText.h3),
            ),
            for (final code in supportedLanguages)
              ListTile(
                title: Text(languageLabels[code] ?? code),
                trailing: code == profile.language ? const Icon(Icons.check, color: NivasaColors.primary700) : null,
                onTap: () => Navigator.of(context).pop(code),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == profile.language) return;
    try {
      final updated = await _profiles.update(_token!, language: selected);
      if (!mounted) return;
      setState(() => _profile = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update language — try again')));
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll need to sign in again to use the app."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profile == null
            ? _ErrorState(message: _error ?? 'Could not load your profile', onRetry: _load)
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(NivasaSpacing.s24, NivasaSpacing.s24, NivasaSpacing.s24, 0),
                      child: NivasaStaleBanner(lastSyncedAt: _lastSyncedAt, onRetry: _load),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(NivasaSpacing.s24),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(_profile!.name, style: NivasaText.h2)),
                              InkWell(
                                key: const Key('user-avatar'),
                                borderRadius: BorderRadius.circular(NivasaRadius.pill),
                                onTap: () => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute(builder: (_) => AccountDetailsScreen(authRepository: _auth))),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(color: NivasaColors.primary50, shape: BoxShape.circle),
                                  child: const Icon(Icons.person_outline, color: NivasaColors.primary700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: NivasaSpacing.s24),
                          _PropertyRow(
                            profile: _profile!,
                            expanded: _propertyExpanded,
                            onTap: () => setState(() => _propertyExpanded = !_propertyExpanded),
                          ),
                          const SizedBox(height: NivasaSpacing.s24),
                          // Grouped into three cards (2026-08-31, doc option "1i") — the old
                          // flat list of eight identical rows had a real Identity/Preferences/
                          // Legal structure that only showed up as a single extra gap before
                          // "Privacy Policy"; every other boundary looked the same.
                          NivasaMenuGroupCard(
                            title: 'Profile',
                            children: [
                              NivasaMenuRow(
                                icon: Icons.badge_outlined,
                                label: 'Account Details',
                                showCard: false,
                                trailing: _KycBadge(status: _kycStatus),
                                onTap: () => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute(builder: (_) => AccountDetailsScreen(authRepository: _auth))),
                              ),
                              NivasaMenuRow(
                                icon: Icons.emergency_outlined,
                                label: 'Emergency Contacts',
                                showCard: false,
                                onTap: () => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute(builder: (_) => EmergencyContactsScreen(authRepository: _auth))),
                              ),
                            ],
                          ),
                          const SizedBox(height: NivasaSpacing.s16),
                          NivasaMenuGroupCard(
                            title: 'Preferences',
                            children: [
                              NivasaMenuRow(
                                icon: Icons.notifications_outlined,
                                label: 'Notifications',
                                showCard: false,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                              ),
                              NivasaMenuRow(
                                icon: Icons.language_outlined,
                                label: 'Language: ${languageLabels[_profile!.language] ?? _profile!.language}',
                                trailing: const Icon(Icons.keyboard_arrow_down, color: NivasaColors.ink500),
                                showCard: false,
                                onTap: _pickLanguage,
                              ),
                              NivasaMenuRow(
                                icon: Icons.feedback_outlined,
                                label: 'App Feedback',
                                showCard: false,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppFeedbackScreen())),
                              ),
                            ],
                          ),
                          const SizedBox(height: NivasaSpacing.s16),
                          NivasaMenuGroupCard(
                            title: 'Legal',
                            children: [
                              NivasaMenuRow(
                                icon: Icons.privacy_tip_outlined,
                                label: 'Privacy Policy',
                                showCard: false,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                              ),
                              NivasaMenuRow(
                                icon: Icons.description_outlined,
                                label: 'Terms & Conditions',
                                showCard: false,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsScreen())),
                              ),
                            ],
                          ),
                          const SizedBox(height: NivasaSpacing.s16),
                          NivasaMenuRow(
                            icon: Icons.logout,
                            label: 'Sign Out',
                            iconColor: NivasaColors.negativeFg,
                            labelColor: NivasaColors.negativeFg,
                            trailing: const SizedBox.shrink(),
                            onTap: _confirmSignOut,
                          ),
                          if (_appVersion != null) ...[
                            const SizedBox(height: NivasaSpacing.s24),
                            Center(child: Text(_appVersion!, style: NivasaText.caption)),
                          ],
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

const _kycBadgeLabels = {'verified': 'Verified', 'pending': 'Pending', 'failed': 'Action needed', 'expired': 'Action needed'};

/// Compact status pill on the "Account Details" row (doc option "1i": "surface KYC
/// status on the row") — the full explanation/"Verify now" action still lives on
/// AccountDetailsScreen's own `_KycStatusCard`; this just answers "do I need to go in
/// there?" without opening the row.
class _KycBadge extends StatelessWidget {
  const _KycBadge({required this.status});

  final KycStatus? status;

  @override
  Widget build(BuildContext context) {
    final (fg, tint) = switch (status?.status) {
      'verified' => (NivasaColors.positiveTextOnTint, NivasaColors.positiveTint),
      'pending' => (NivasaColors.warningTextOnTint, NivasaColors.warningTint),
      'failed' || 'expired' => (NivasaColors.negativeTextOnTint, NivasaColors.negativeTint),
      _ => (NivasaColors.offlineTextOnTint, NivasaColors.offlineTint),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(NivasaRadius.pill)),
          child: Text(
            _kycBadgeLabels[status?.status] ?? 'Not verified',
            style: NivasaText.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: NivasaSpacing.s8),
        const Icon(Icons.chevron_right, color: NivasaColors.ink500),
      ],
    );
  }
}

/// The reference design shows a chevron suggesting a property switcher, but tenant-service
/// only ever returns one property per tenant today (no multi-property/switch API exists) —
/// see the 2026-08-27 investigation. The chevron here instead expands/collapses the full
/// property address, which is real data this screen already has.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.profile, required this.expanded, required this.onTap});

  final TenantProfile profile;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAddress = profile.propertyAddress != null && profile.propertyAddress!.isNotEmpty;
    return InkWell(
      onTap: hasAddress ? onTap : null,
      borderRadius: BorderRadius.circular(NivasaRadius.card),
      child: Container(
        padding: const EdgeInsets.all(NivasaSpacing.s16),
        decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(NivasaRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.propertyName ?? 'No property on file', style: NivasaText.h3),
                      if (profile.propertyCity != null) ...[
                        const SizedBox(height: NivasaSpacing.s4),
                        Text(profile.propertyCity!, style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500)),
                      ],
                    ],
                  ),
                ),
                if (hasAddress) Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: NivasaColors.ink500),
              ],
            ),
            if (expanded && hasAddress) ...[
              const SizedBox(height: NivasaSpacing.s12),
              const Divider(height: 1),
              const SizedBox(height: NivasaSpacing.s12),
              Text(profile.propertyAddress!, style: NivasaText.body.copyWith(color: NivasaColors.ink700)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NivasaSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: NivasaText.body.copyWith(color: NivasaColors.ink500), textAlign: TextAlign.center),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
