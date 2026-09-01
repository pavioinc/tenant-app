import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_menu_row.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../kyc/kyc_repository.dart';
import '../kyc/kyc_screen.dart';
import 'change_password_screen.dart';
import 'profile_repository.dart';

/// UserScreen's "Account Details" row — the identity/editable-contact half of what used
/// to be the single ProfileScreen (see 2026-08-27 redesign). Name and account email stay
/// manager/signup-set; phone and permanent address are self-editable, same scope call as
/// before. Emergency contact and language moved to their own destinations off UserScreen
/// (EmergencyContactsScreen, and an inline picker) so this screen doesn't re-show them.
class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key, this.authRepository, this.profileRepository, this.kycRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final KycRepository? kycRepository;
  final CacheStore? cacheStore;

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ProfileRepository _profiles = widget.profileRepository ?? ProfileRepository();
  late final KycRepository _kyc = widget.kycRepository ?? KycRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SecureCacheStore();
  final _phoneController = TextEditingController();
  final _permanentAddressController = TextEditingController();

  String? _token;
  TenantProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;
  KycStatus? _kycStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _permanentAddressController.dispose();
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
        _permanentAddressController.text = result.data.permanentAddress ?? '';
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

  /// Fire-and-forget, same rationale as the old ProfileScreen's version: a failure here
  /// just leaves the identity-verification section showing "Not verified" instead of
  /// blocking the rest of the screen from loading.
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

  Future<void> _openKyc() async {
    final verified = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => KycScreen(authRepository: _auth, kycRepository: _kyc)));
    if (verified == true) _loadKycStatus();
  }

  String? _nullIfEmpty(String text) => text.trim().isEmpty ? null : text.trim();

  Future<void> _save() async {
    if (_token == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _profiles.update(_token!, phone: _phoneController.text.trim(), permanentAddress: _nullIfEmpty(_permanentAddressController.text));
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account details updated')));
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
      appBar: AppBar(title: const Text('Account Details')),
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(NivasaSpacing.s24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    Text('Name', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    Text(_profile!.name, style: NivasaText.body),
                    const SizedBox(height: NivasaSpacing.s24),
                    Text('Email', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    Text(_profile!.email ?? 'No email on file', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    if (_profile!.propertyName != null) ...[
                      const SizedBox(height: NivasaSpacing.s24),
                      Text('Property', style: NivasaText.label),
                      const SizedBox(height: NivasaSpacing.s8),
                      Text(
                        [_profile!.propertyName, _profile!.propertyCity].whereType<String>().join(', '),
                        style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                      ),
                      if (_profile!.propertyAddress != null)
                        Text(_profile!.propertyAddress!, style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500)),
                    ],
                    const SizedBox(height: NivasaSpacing.s24),
                    Text('Phone', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: NivasaText.body),
                    const SizedBox(height: NivasaSpacing.s24),
                    Text('Permanent address', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    TextField(
                      controller: _permanentAddressController,
                      style: NivasaText.body,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Optional'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: NivasaSpacing.s16),
                      Text(_error!, style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
                    ],
                    const SizedBox(height: NivasaSpacing.s24),
                    NivasaPrimaryButton(label: 'Save', loading: _saving, loadingLabel: 'Saving…', onPressed: _save),
                    const SizedBox(height: NivasaSpacing.s32),
                    NivasaMenuRow(
                      icon: Icons.lock_outline,
                      label: 'Change password',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangePasswordScreen(authRepository: _auth))),
                    ),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Identity verification', style: NivasaText.label),
                    const SizedBox(height: NivasaSpacing.s8),
                    _KycStatusCard(status: _kycStatus, onVerify: _openKyc),
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
      decoration: BoxDecoration(color: tint, border: Border.all(color: border), borderRadius: BorderRadius.circular(NivasaRadius.card)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: NivasaText.body.copyWith(color: fg, fontWeight: FontWeight.w600)),
                if (verified && status?.aadhaarLast4 != null) ...[
                  const SizedBox(height: NivasaSpacing.s4),
                  Text('Aadhaar •••• ${status!.aadhaarLast4}', style: NivasaText.bodySmall.copyWith(color: fg)),
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
