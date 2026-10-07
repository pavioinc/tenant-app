import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/url_opener.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'contacts_repository.dart';

const _avatarColors = [
  PavioColors.primary700,
  PavioColors.primary600,
  PavioColors.primary500,
];

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Redesigned (doc option "1h") — an avatar + Call/Email as real outlined buttons
/// instead of the small inline tap-rows this screen already had (an earlier pass had
/// already fixed the "Dead data" finding — phone/email used to be plain, unstyled
/// `Text` — this redesign is the visual weight a "reach a human" screen's one real
/// action deserves). A contact with only one reachable channel (no email on file, say)
/// gets a single compact icon button inline with their name instead of a full-width row
/// that would just be half-empty.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.authRepository,
    this.contactsRepository,
    this.cacheStore,
    this.urlOpener,
  });

  final AuthRepository? authRepository;
  final ContactsRepository? contactsRepository;
  final CacheStore? cacheStore;
  final UrlOpener? urlOpener;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ContactsRepository _contacts =
      widget.contactsRepository ?? ContactsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _call(String phone) =>
      _launch('tel:$phone', 'No phone app found — call $phone directly');
  void _email(String email) =>
      _launch('mailto:$email', 'No email app found — write to $email directly');

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
        fromJson: (json) => (json as List)
            .map((c) => Contact.fromJson(c as Map<String, dynamic>))
            .toList(),
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
      setState(
        () => _error = "Could not load your property's contacts — try again",
      );
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
            ? const PavioSkeletonList()
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
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
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(
                                    PavioSpacing.s24,
                                  ),
                                  child: Text(
                                    'No contacts on file yet',
                                    style: PavioText.body.copyWith(
                                      color: PavioColors.ink500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(PavioSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: PavioSpacing.s12),
                              itemBuilder: (context, index) => _ContactCard(
                                contact: _items[index],
                                avatarColor:
                                    _avatarColors[index % _avatarColors.length],
                                onCall: _call,
                                onEmail: _email,
                              ),
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
  const _ContactCard({
    required this.contact,
    required this.avatarColor,
    required this.onCall,
    required this.onEmail,
  });

  final Contact contact;
  final Color avatarColor;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onEmail;

  @override
  Widget build(BuildContext context) {
    final hasPhone = contact.phone != null;
    final hasEmail = contact.email != null;
    return Container(
      padding: const EdgeInsets.all(PavioSpacing.s16),
      decoration: BoxDecoration(
        color: PavioColors.white,
        border: Border.all(color: PavioColors.line),
        borderRadius: BorderRadius.circular(PavioRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _initials(contact.name),
                    style: PavioText.body.copyWith(
                      color: PavioColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PavioSpacing.s12 + 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: PavioText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contactRoleLabel(contact.role),
                      style: PavioText.bodySmall.copyWith(
                        color: PavioColors.ink500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Exactly one reachable channel — a single icon button inline rather
              // than a full-width row for the one that's missing.
              if (hasPhone && !hasEmail)
                _OutlinedIconAction(
                  icon: Icons.call_outlined,
                  onTap: () => onCall(contact.phone!),
                ),
              if (hasEmail && !hasPhone)
                _OutlinedIconAction(
                  icon: Icons.email_outlined,
                  onTap: () => onEmail(contact.email!),
                ),
            ],
          ),
          if (hasPhone && hasEmail) ...[
            const SizedBox(height: PavioSpacing.s16 - 2),
            Row(
              children: [
                Expanded(
                  child: _OutlinedLabelAction(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    onTap: () => onCall(contact.phone!),
                  ),
                ),
                const SizedBox(width: PavioSpacing.s8 + 2),
                Expanded(
                  child: _OutlinedLabelAction(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    onTap: () => onEmail(contact.email!),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OutlinedLabelAction extends StatelessWidget {
  const _OutlinedLabelAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.button),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          border: Border.all(color: PavioColors.primary700, width: 1.5),
          borderRadius: BorderRadius.circular(PavioRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: PavioColors.primary700),
            const SizedBox(width: PavioSpacing.s4 + 3),
            Text(
              label,
              style: PavioText.body.copyWith(
                color: PavioColors.primary700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedIconAction extends StatelessWidget {
  const _OutlinedIconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.button),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: PavioColors.primary700, width: 1.5),
          borderRadius: BorderRadius.circular(PavioRadius.button),
        ),
        child: Icon(icon, size: 19, color: PavioColors.primary700),
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
