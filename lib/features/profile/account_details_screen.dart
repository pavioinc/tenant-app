import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';
import '../../widgets/pavio_menu_row.dart';
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
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
  const AccountDetailsScreen({
    super.key,
    this.authRepository,
    this.profileRepository,
    this.kycRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final KycRepository? kycRepository;
  final CacheStore? cacheStore;

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ProfileRepository _profiles =
      widget.profileRepository ?? ProfileRepository();
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
        fromJson: (json) =>
            TenantProfile.fromJson(json as Map<String, dynamic>),
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
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KycScreen(authRepository: _auth, kycRepository: _kyc),
      ),
    );
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
      final updated = await _profiles.update(
        _token!,
        phone: _phoneController.text.trim(),
        permanentAddress: _nullIfEmpty(_permanentAddressController.text),
      );
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account details updated')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
        () => _error = 'Could not save — check your connection and try again',
      );
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
            ? const _AccountDetailsLoadingSkeleton()
            : _profile == null
            ? _ErrorState(
                message: _error ?? 'Could not load your profile',
                onRetry: _load,
              )
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PavioSpacing.s24,
                        PavioSpacing.s24,
                        PavioSpacing.s24,
                        0,
                      ),
                      child: PavioStaleBanner(
                        lastSyncedAt: _lastSyncedAt,
                        onRetry: _load,
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(PavioSpacing.s24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name', style: PavioText.label),
                          const SizedBox(height: PavioSpacing.s8),
                          Text(_profile!.name, style: PavioText.body),
                          const SizedBox(height: PavioSpacing.s24),
                          Text('Email', style: PavioText.label),
                          const SizedBox(height: PavioSpacing.s8),
                          Text(
                            _profile!.email ?? 'No email on file',
                            style: PavioText.body.copyWith(
                              color: PavioColors.ink500,
                            ),
                          ),
                          if (_profile!.propertyName != null) ...[
                            const SizedBox(height: PavioSpacing.s24),
                            Text('Property', style: PavioText.label),
                            const SizedBox(height: PavioSpacing.s8),
                            Text(
                              [
                                _profile!.propertyName,
                                _profile!.propertyCity,
                              ].whereType<String>().join(', '),
                              style: PavioText.body.copyWith(
                                color: PavioColors.ink500,
                              ),
                            ),
                            if (_profile!.propertyAddress != null)
                              Text(
                                _profile!.propertyAddress!,
                                style: PavioText.bodySmall.copyWith(
                                  color: PavioColors.ink500,
                                ),
                              ),
                          ],
                          const SizedBox(height: PavioSpacing.s24),
                          Text('Phone', style: PavioText.label),
                          const SizedBox(height: PavioSpacing.s8),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: PavioText.body,
                          ),
                          const SizedBox(height: PavioSpacing.s24),
                          Text('Permanent address', style: PavioText.label),
                          const SizedBox(height: PavioSpacing.s8),
                          TextField(
                            controller: _permanentAddressController,
                            style: PavioText.body,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Optional',
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: PavioSpacing.s16),
                            Text(
                              _error!,
                              style: PavioText.body.copyWith(
                                color: PavioColors.negativeFg,
                              ),
                            ),
                          ],
                          const SizedBox(height: PavioSpacing.s24),
                          PavioPrimaryButton(
                            label: 'Save',
                            loading: _saving,
                            loadingLabel: 'Saving…',
                            onPressed: _save,
                          ),
                          const SizedBox(height: PavioSpacing.s32),
                          PavioMenuRow(
                            icon: Icons.lock_outline,
                            label: 'Change password',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ChangePasswordScreen(authRepository: _auth),
                              ),
                            ),
                          ),
                          const SizedBox(height: PavioSpacing.s32),
                          Text(
                            'Identity verification',
                            style: PavioText.label,
                          ),
                          const SizedBox(height: PavioSpacing.s8),
                          _KycStatusCard(
                            status: _kycStatus,
                            onVerify: _openKyc,
                          ),
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

/// Mirrors the loaded form's real shape (doc option "1l") — label/value pairs, the two
/// editable fields, Save, Change password, and the identity-verification card, in the
/// exact order the real content renders, replacing the old
/// `Center(child: CircularProgressIndicator())`.
class _AccountDetailsLoadingSkeleton extends StatelessWidget {
  const _AccountDetailsLoadingSkeleton();

  static Widget _labeled(double labelWidth, Widget value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PavioSkeleton(width: labelWidth, height: 11),
      const SizedBox(height: PavioSpacing.s8),
      value,
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PavioSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labeled(40, const PavioSkeleton(width: 150, height: 15)),
          const SizedBox(height: PavioSpacing.s24),
          _labeled(40, const PavioSkeleton(width: 180, height: 15)),
          const SizedBox(height: PavioSpacing.s24),
          _labeled(
            48,
            const PavioSkeleton(height: 52, borderRadius: PavioRadius.input),
          ),
          const SizedBox(height: PavioSpacing.s24),
          _labeled(
            140,
            const PavioSkeleton(height: 80, borderRadius: PavioRadius.input),
          ),
          const SizedBox(height: PavioSpacing.s24),
          const PavioSkeleton(height: 52, borderRadius: PavioRadius.button),
          const SizedBox(height: PavioSpacing.s32),
          const PavioSkeleton(height: 52, borderRadius: PavioRadius.card),
          const SizedBox(height: PavioSpacing.s32),
          _labeled(
            140,
            const PavioSkeleton(height: 70, borderRadius: PavioRadius.card),
          ),
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
      'verified' => (
        'Verified',
        PavioColors.positiveTextOnTint,
        PavioColors.positiveTint,
        PavioColors.positiveTintBorder,
      ),
      'pending' => (
        'Verification in progress',
        PavioColors.warningTextOnTint,
        PavioColors.warningTint,
        PavioColors.warningTintBorder,
      ),
      'failed' => (
        'Verification failed — try again',
        PavioColors.negativeTextOnTint,
        PavioColors.negativeTint,
        PavioColors.negativeTintBorder,
      ),
      'expired' => (
        'OTP expired — try again',
        PavioColors.negativeTextOnTint,
        PavioColors.negativeTint,
        PavioColors.negativeTintBorder,
      ),
      _ => (
        'Not verified',
        PavioColors.offlineTextOnTint,
        PavioColors.offlineTint,
        PavioColors.offlineTintBorder,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(PavioSpacing.s16),
      decoration: BoxDecoration(
        color: tint,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(PavioRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: PavioText.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (verified && status?.aadhaarLast4 != null) ...[
                  const SizedBox(height: PavioSpacing.s4),
                  Text(
                    'Aadhaar •••• ${status!.aadhaarLast4}',
                    style: PavioText.bodySmall.copyWith(color: fg),
                  ),
                ],
              ],
            ),
          ),
          if (!verified)
            TextButton(onPressed: onVerify, child: const Text('Verify now')),
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
        padding: const EdgeInsets.all(PavioSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: PavioText.body.copyWith(color: PavioColors.ink500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PavioSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
