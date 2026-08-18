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
import 'profile_repository.dart';

/// Name and account email stay manager/signup-set — only phone and language are
/// editable here (2026-08-14 scope call, see tenant-service/README.md's
/// "Tenant self-service" section).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.authRepository, this.profileRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final CacheStore? cacheStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ProfileRepository _profiles = widget.profileRepository ?? ProfileRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();
  final _phoneController = TextEditingController();

  String? _token;
  TenantProfile? _profile;
  String? _language;
  bool _loading = true;
  bool _saving = false;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
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
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your profile — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_token == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _profiles.update(_token!, phone: _phoneController.text.trim(), language: _language);
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
      appBar: AppBar(title: const Text('Profile')),
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
