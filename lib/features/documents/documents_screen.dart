import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../core/file_picker_service.dart';
import '../../core/share_service.dart';
import '../../core/url_opener.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'documents_repository.dart';

const _fileTypeLabels = {
  'application/pdf': 'PDF',
  'image/jpeg': 'JPG',
  'image/png': 'PNG',
};

String _fileTypeLabel(String contentType) =>
    _fileTypeLabels[contentType] ?? contentType.split('/').last.toUpperCase();

/// "245760" → "240 KB" — binary (1024-based) units, matching how a phone's own file
/// picker/gallery already shows sizes to this renter, not SI (1000-based) ones.
String _fileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

({Color bg, Color fg, IconData icon}) _fileVisual(TenantDocument document) {
  if (document.status == 'verified') {
    return (
      bg: NivasaColors.positiveTint,
      fg: NivasaColors.positiveTextOnTint,
      icon: Icons.verified,
    );
  }
  if (document.contentType == 'application/pdf') {
    return (
      bg: NivasaColors.negativeTint,
      fg: NivasaColors.negativeTextOnTint,
      icon: Icons.picture_as_pdf,
    );
  }
  return (
    bg: NivasaColors.infoTint,
    fg: NivasaColors.infoTextOnTint,
    icon: Icons.image,
  );
}

/// Redesigned (doc option "1f") from two adjacent 48px icon buttons — irreversible
/// delete 8px from download, no way to tell two Aadhaar scans apart (design review
/// finding TT-2) — into: one overflow menu per row (Download/Share/Delete…, delete
/// still behind the existing confirm dialog), and a type · size · date subtitle so two
/// scans of the same document actually read as different files. Size/date were nowhere
/// in the schema before migration 039; status (manager-reviewed or not) already was —
/// a verified document gets the same green "verified" treatment CLO-232's Documents
/// redesign gave it on the owner-dashboard side, and a rejected one surfaces the
/// manager's own note instead of leaving a renter to guess why nothing happened.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    this.authRepository,
    this.documentsRepository,
    this.cacheStore,
    this.filePicker,
    this.urlOpener,
    this.shareService,
  });

  final AuthRepository? authRepository;
  final DocumentsRepository? documentsRepository;
  final CacheStore? cacheStore;
  final FilePickerService? filePicker;
  final UrlOpener? urlOpener;
  final ShareService? shareService;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final DocumentsRepository _documents =
      widget.documentsRepository ?? DocumentsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final FilePickerService _filePicker =
      widget.filePicker ?? const RealFilePickerService();
  late final UrlOpener _urlOpener = widget.urlOpener ?? const RealUrlOpener();
  late final ShareService _shareService =
      widget.shareService ?? const RealShareService();

  String? _token;
  List<TenantDocument> _items = [];
  bool _loading = true;
  bool _uploading = false;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final result = await fetchWithCache<List<TenantDocument>>(
        cache: _cache,
        cacheKey: 'documents',
        fetchNetwork: () => _documents.list(_token!),
        toJson: (items) => items.map((d) => d.toJson()).toList(),
        fromJson: (json) => (json as List)
            .map((d) => TenantDocument.fromJson(d as Map<String, dynamic>))
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
      setState(() => _error = 'Could not load your documents — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_token == null) return;
    final picked = await _filePicker.pickDocument();
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _documents.upload(
        _token!,
        label: picked.name,
        contentType: picked.contentType,
        bytes: picked.bytes,
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload — try again')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(TenantDocument document) async {
    if (_token == null) return;
    try {
      final url = await _documents.downloadUrl(_token!, document.documentId);
      await _urlOpener.open(url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open — try again')),
      );
    }
  }

  Future<void> _share(TenantDocument document) async {
    if (_token == null) return;
    try {
      final url = await _documents.downloadUrl(_token!, document.documentId);
      await _shareService.shareUrl(url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share — try again')),
      );
    }
  }

  Future<void> _delete(TenantDocument document) async {
    if (_token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          '"${document.label}" will be permanently removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _documents.delete(_token!, document.documentId);
      if (!mounted) return;
      setState(
        () => _items = _items
            .where((d) => d.documentId != document.documentId)
            .toList(),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove — try again')),
      );
    }
  }

  void _onMenuSelected(String action, TenantDocument document) {
    switch (action) {
      case 'download':
        _download(document);
      case 'share':
        _share(document);
      case 'delete':
        _delete(document);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NivasaSpacing.s24,
                        NivasaSpacing.s24,
                        NivasaSpacing.s24,
                        0,
                      ),
                      child: NivasaStaleBanner(
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
                                    NivasaSpacing.s24,
                                  ),
                                  child: Text(
                                    'No documents yet — tap "Upload a document" to add an ID proof or other document.',
                                    style: NivasaText.body.copyWith(
                                      color: NivasaColors.ink500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.all(NivasaSpacing.s24),
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: NivasaColors.white,
                                    border: Border.all(
                                      color: NivasaColors.line,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      NivasaRadius.card,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < _items.length;
                                        i++
                                      ) ...[
                                        _DocumentRow(
                                          document: _items[i],
                                          onMenuSelected: (action) =>
                                              _onMenuSelected(
                                                action,
                                                _items[i],
                                              ),
                                        ),
                                        if (i != _items.length - 1)
                                          const Divider(
                                            height: 1,
                                            indent: 70,
                                            color: NivasaColors.line,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: NivasaSpacing.s16),
                                Text(
                                  'Documents you upload are visible to your property manager.',
                                  style: NivasaText.bodySmall.copyWith(
                                    color: NivasaColors.ink500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  _UploadBar(
                    uploading: _uploading,
                    onPressed: _uploading ? null : _upload,
                  ),
                ],
              ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.onMenuSelected});

  final TenantDocument document;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final visual = _fileVisual(document);
    final sizeLabel = document.fileSizeBytes != null
        ? _fileSizeLabel(document.fileSizeBytes!)
        : null;
    final subtitleParts = [
      _fileTypeLabel(document.contentType),
      ?sizeLabel,
      formatDisplayDate(document.uploadedAt),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: visual.bg,
              borderRadius: BorderRadius.circular(NivasaRadius.md),
            ),
            child: Icon(visual.icon, size: 21, color: visual.fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.label,
                  style: NivasaText.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(subtitleParts.join(' · '), style: NivasaText.caption),
                if (document.status == 'rejected') ...[
                  const SizedBox(height: 3),
                  Text(
                    document.reviewNote != null
                        ? 'Rejected — ${document.reviewNote}'
                        : 'Rejected',
                    style: NivasaText.caption.copyWith(
                      color: NivasaColors.negativeFg,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: NivasaColors.ink500),
            color: NivasaColors.ink900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NivasaRadius.lg),
            ),
            onSelected: onMenuSelected,
            itemBuilder: (context) => [
              _menuItem('download', Icons.download_outlined, 'Download'),
              _menuItem('share', Icons.ios_share, 'Share'),
              const PopupMenuDivider(height: 1),
              _menuItem(
                'delete',
                Icons.delete_outline,
                'Delete…',
                color: NivasaColors.negativeTintBorder,
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color color = NivasaColors.white,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: NivasaSpacing.s12),
          Text(
            label,
            style: NivasaText.body.copyWith(color: color, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _UploadBar extends StatelessWidget {
  const _UploadBar({required this.uploading, required this.onPressed});

  final bool uploading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NivasaSpacing.s24,
        NivasaSpacing.s12,
        NivasaSpacing.s24,
        NivasaSpacing.s24,
      ),
      decoration: const BoxDecoration(
        color: NivasaColors.white,
        border: Border(top: BorderSide(color: NivasaColors.line)),
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(NivasaColors.white),
                  ),
                )
              : const Icon(Icons.upload_outlined, size: 20),
          label: Text(uploading ? 'Uploading…' : 'Upload a document'),
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
            Text(
              message,
              style: NivasaText.body.copyWith(color: NivasaColors.ink500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
