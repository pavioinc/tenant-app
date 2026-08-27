import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../kyc/kyc_repository.dart';
import '../kyc/kyc_screen.dart';
import '../payments/payments_repository.dart';
import 'profile_repository.dart';
import 'settings_screen.dart';

String _formatInr(int amountMinor) => '₹${(amountMinor / 100).toStringAsFixed(0)}';

/// Name and account email stay manager/signup-set — phone, language, permanent address,
/// and emergency contact are self-editable (2026-08-14 scope call for phone/language, see
/// tenant-service/README.md's "Tenant self-service" section; permanent address/emergency
/// contact added 2026-08-23 — personal-profile fields the tenant is the authority on,
/// unlike account credentials).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.authRepository,
    this.profileRepository,
    this.kycRepository,
    this.paymentsRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final KycRepository? kycRepository;
  final PaymentsRepository? paymentsRepository;
  final CacheStore? cacheStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ProfileRepository _profiles = widget.profileRepository ?? ProfileRepository();
  late final KycRepository _kyc = widget.kycRepository ?? KycRepository();
  late final PaymentsRepository _payments = widget.paymentsRepository ?? PaymentsRepository();
  // SecureCacheStore, not SharedPreferencesCacheStore: this screen's cached payload
  // (TenantProfile) includes home address and emergency contact — see cache_store.dart.
  late final CacheStore _cache = widget.cacheStore ?? const SecureCacheStore();
  final _phoneController = TextEditingController();
  final _permanentAddressController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _emergencyContactRelationshipController = TextEditingController();

  String? _token;
  TenantProfile? _profile;
  String? _language;
  bool _loading = true;
  bool _saving = false;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;
  KycStatus? _kycStatus;
  PendingInvoices? _rentDue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _permanentAddressController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _emergencyContactRelationshipController.dispose();
    super.dispose();
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
        _phoneController.text = result.data.phone;
        _language = result.data.language;
        _permanentAddressController.text = result.data.permanentAddress ?? '';
        _emergencyContactNameController.text = result.data.emergencyContactName ?? '';
        _emergencyContactPhoneController.text = result.data.emergencyContactPhone ?? '';
        _emergencyContactRelationshipController.text = result.data.emergencyContactRelationship ?? '';
      });
      _loadKycStatus();
      _loadRentDue();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your profile — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fire-and-forget, deliberately separate from the profile fetch above (which is
  /// cached/offline-tolerant via fetchWithCache) — a failure here just leaves the
  /// identity-verification section showing "Not verified" rather than blocking the
  /// rest of the profile screen from loading.
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

  /// Same fire-and-forget shape as _loadKycStatus — a failure here just leaves the rent
  /// due section hidden rather than blocking the rest of the profile from loading. The
  /// Payments tile is the full picker/pay flow; this is just a summary glance.
  Future<void> _loadRentDue() async {
    if (_token == null) return;
    try {
      final due = await _payments.pendingInvoices(_token!);
      if (!mounted) return;
      setState(() => _rentDue = due);
    } catch (_) {
      // Non-fatal — see comment above.
    }
  }

  Future<void> _openKyc() async {
    final verified = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => KycScreen(authRepository: _auth, kycRepository: _kyc)));
    if (verified == true) _loadKycStatus();
  }

  /// Empty text fields become null (omitted from the PATCH body), not '' — the backend
  /// coalesces a missing field against the existing value, so sending '' would silently
  /// blank out e.g. an emergency contact the tenant just isn't editing right now, every
  /// time they save an unrelated field like phone.
  String? _nullIfEmpty(String text) => text.trim().isEmpty ? null : text.trim();

  Future<void> _save() async {
    if (_token == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _profiles.update(
        _token!,
        phone: _phoneController.text.trim(),
        language: _language,
        permanentAddress: _nullIfEmpty(_permanentAddressController.text),
        emergencyContactName: _nullIfEmpty(_emergencyContactNameController.text),
        emergencyContactPhone: _nullIfEmpty(_emergencyContactPhoneController.text),
        emergencyContactRelationship: _nullIfEmpty(_emergencyContactRelationshipController.text),
      );
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save — check your connection and try again');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            key: const Key('settings-button'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(authRepository: _auth))),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profile == null
            ? _ErrorState(message: _error ?? 'Could not load your profile', onRetry: _load)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(NivasaSpacing.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_stale) ...[
                      NivasaStaleBanner(lastSyncedAt: _lastSyncedAt),
                      const SizedBox(height: NivasaSpacing.s16),
                    ],
                    Text(_profile!.name, style: NivasaText.h1),
                    const SizedBox(height: NivasaSpacing.s4),
                    Text(_profile!.email ?? 'No email on file', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    if (_profile!.propertyName != null) ...[
                      const SizedBox(height: NivasaSpacing.s4),
                      Text(
                        [_profile!.propertyName, _profile!.propertyCity].whereType<String>().join(', '),
                        style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                      ),
                      if (_profile!.propertyAddress != null)
                        Text(_profile!.propertyAddress!, style: NivasaText.body.copyWith(color: NivasaColors.ink500, fontSize: 13)),
                    ],
                    const SizedBox(height: NivasaSpacing.s24),
                    _RentDueCard(rentDue: _rentDue),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Phone', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: NivasaText.body),
                    const SizedBox(height: NivasaSpacing.s24),
                    Text('Preferred language', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    DropdownButtonFormField<String>(
                      initialValue: _language,
                      items: [
                        for (final code in supportedLanguages) DropdownMenuItem(value: code, child: Text(languageLabels[code] ?? code)),
                      ],
                      onChanged: (value) => setState(() => _language = value),
                    ),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Permanent address', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(
                      controller: _permanentAddressController,
                      style: NivasaText.body,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Optional'),
                    ),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Emergency contact', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(
                      controller: _emergencyContactNameController,
                      style: NivasaText.body,
                      decoration: const InputDecoration(hintText: 'Name'),
                    ),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(
                      controller: _emergencyContactPhoneController,
                      keyboardType: TextInputType.phone,
                      style: NivasaText.body,
                      decoration: const InputDecoration(hintText: 'Phone'),
                    ),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(
                      controller: _emergencyContactRelationshipController,
                      style: NivasaText.body,
                      decoration: const InputDecoration(hintText: 'Relationship, e.g. Parent, Spouse, Sibling'),
                    ),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Identity verification', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    _KycStatusCard(status: _kycStatus, onVerify: _openKyc),
                    if (_error != null) ...[
                      const SizedBox(height: NivasaSpacing.s16),
                      Text(_error!, style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
                    ],
                    const SizedBox(height: NivasaSpacing.s32),
                    NivasaPrimaryButton(label: 'Save', loading: _saving, loadingLabel: 'Saving…', onPressed: _save),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Summary glance at what's due — the Payments tile is the full pick-an-invoice-and-pay
/// flow; this just answers "am I current?" without leaving Profile. Null (not yet
/// loaded/failed — see _loadRentDue) renders nothing rather than a misleading "all
/// clear" the way an empty list would.
class _RentDueCard extends StatelessWidget {
  const _RentDueCard({required this.rentDue});

  final PendingInvoices? rentDue;

  @override
  Widget build(BuildContext context) {
    if (rentDue == null) return const SizedBox.shrink();
    final due = rentDue!;
    final hasDue = due.invoices.isNotEmpty;
    final (label, fg, tint, border) = hasDue
        ? (
            'Rent due',
            NivasaColors.warningTextOnTint,
            NivasaColors.warningTint,
            NivasaColors.warningTintBorder,
          )
        : ('No rent due', NivasaColors.positiveTextOnTint, NivasaColors.positiveTint, NivasaColors.positiveTintBorder);
    final earliest = hasDue ? due.invoices.reduce((a, b) => a.dueDate.compareTo(b.dueDate) <= 0 ? a : b) : null;
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(color: tint, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: NivasaText.body.copyWith(color: fg, fontWeight: FontWeight.w600)),
          if (hasDue && earliest != null) ...[
            const SizedBox(height: NivasaSpacing.s4),
            Text('${_formatInr(due.totalDue)} · next due ${earliest.dueDate}', style: NivasaText.body.copyWith(color: fg, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _KycStatusCard extends StatelessWidget {
  const _KycStatusCard({required this.status, required this.onVerify});

  final KycStatus? status;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final verified = status?.isVerified ?? false;
    final (label, fg, tint, border) = switch (status?.status) {
      'verified' => ('Verified', NivasaColors.positiveTextOnTint, NivasaColors.positiveTint, NivasaColors.positiveTintBorder),
      'pending' => ('Verification in progress', NivasaColors.warningTextOnTint, NivasaColors.warningTint, NivasaColors.warningTintBorder),
      'failed' => ('Verification failed — try again', NivasaColors.negativeTextOnTint, NivasaColors.negativeTint, NivasaColors.negativeTintBorder),
      'expired' => ('OTP expired — try again', NivasaColors.negativeTextOnTint, NivasaColors.negativeTint, NivasaColors.negativeTintBorder),
      _ => ('Not verified', NivasaColors.offlineTextOnTint, NivasaColors.offlineTint, NivasaColors.offlineTintBorder),
    };
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(color: tint, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: NivasaText.body.copyWith(color: fg, fontWeight: FontWeight.w600)),
                if (verified && status?.aadhaarLast4 != null) ...[
                  const SizedBox(height: NivasaSpacing.s4),
                  Text('Aadhaar •••• ${status!.aadhaarLast4}', style: NivasaText.body.copyWith(color: fg, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (!verified) TextButton(onPressed: onVerify, child: const Text('Verify now')),
        ],
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
