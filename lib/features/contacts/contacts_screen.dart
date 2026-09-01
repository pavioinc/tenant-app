import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/url_opener.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'contacts_repository.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.authRepository, this.contactsRepository, this.cacheStore, this.urlOpener});

  final AuthRepository? authRepository;
  final ContactsRepository? contactsRepository;
  final CacheStore? cacheStore;
  final UrlOpener? urlOpener;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ContactsRepository _contacts = widget.contactsRepository ?? ContactsRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final UrlOpener _urlOpener = widget.urlOpener ?? const RealUrlOpener();

  List<Contact> _items = [];
  bool _loading = true;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _launch(String url, String failureMessage) async {
    try {
      final opened = await _urlOpener.open(url);
      if (!mounted || opened) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _call(String phone) => _launch('tel:$phone', 'No phone app found — call $phone directly');
  void _email(String email) => _launch('mailto:$email', 'No email app found — write to $email directly');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _auth.currentSession();
      if (session == null) throw StateError('no active session');
      final result = await fetchWithCache<List<Contact>>(
        cache: _cache,
        cacheKey: 'contacts',
        fetchNetwork: () => _contacts.list(session.accessToken),
        toJson: (items) => items.map((c) => c.toJson()).toList(),
        fromJson: (json) => (json as List).map((c) => Contact.fromJson(c as Map<String, dynamic>)).toList(),
      );
      if (!mounted) return;
      setState(() {
        _items = result.data;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Could not load your property's contacts — try again");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
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
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                                  child: Text('No contacts on file yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(NivasaSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: NivasaSpacing.s12),
                              itemBuilder: (context, index) => _ContactCard(contact: _items[index], onCall: _call, onEmail: _email),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onCall, required this.onEmail});
  final Contact contact;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(NivasaRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(contact.name, style: NivasaText.h3)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: NivasaColors.primary50, borderRadius: BorderRadius.circular(NivasaRadius.pill)),
                child: Text(
                  contactRoleLabel(contact.role),
                  style: NivasaText.badge.copyWith(color: NivasaColors.primary700),
                ),
              ),
            ],
          ),
          if (contact.phone != null) ...[
            const SizedBox(height: NivasaSpacing.s8),
            _TapToContactRow(icon: Icons.call_outlined, label: contact.phone!, onTap: () => onCall(contact.phone!)),
          ],
          if (contact.email != null) ...[
            const SizedBox(height: NivasaSpacing.s4),
            _TapToContactRow(icon: Icons.email_outlined, label: contact.email!, onTap: () => onEmail(contact.email!)),
          ],
        ],
      ),
    );
  }
}

/// Phone/email were plain, unstyled `Text` before this — a screen whose only purpose is
/// "reach a human" made you copy the number out by hand and dial it yourself. `tel:`/
/// `mailto:` via the same UrlOpener seam AppFeedbackScreen already uses for `mailto:`.
class _TapToContactRow extends StatelessWidget {
  const _TapToContactRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NivasaRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NivasaSpacing.s4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: NivasaColors.primary700),
            const SizedBox(width: NivasaSpacing.s8),
            Text(label, style: NivasaText.body.copyWith(color: NivasaColors.primary700)),
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
