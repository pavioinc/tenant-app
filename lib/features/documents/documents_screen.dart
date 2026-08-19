import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/file_picker_service.dart';
import '../../core/url_opener.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'documents_repository.dart';

const _contentTypeIcons = {'application/pdf': Icons.picture_as_pdf_outlined, 'image/jpeg': Icons.image_outlined, 'image/png': Icons.image_outlined};

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, this.authRepository, this.documentsRepository, this.cacheStore, this.filePicker, this.urlOpener});

  final AuthRepository? authRepository;
  final DocumentsRepository? documentsRepository;
  final CacheStore? cacheStore;
  final FilePickerService? filePicker;
  final UrlOpener? urlOpener;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final DocumentsRepository _documents = widget.documentsRepository ?? DocumentsRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final FilePickerService _filePicker = widget.filePicker ?? const RealFilePickerService();
  late final UrlOpener _urlOpener = widget.urlOpener ?? const RealUrlOpener();

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
        fromJson: (json) => (json as List).map((d) => TenantDocument.fromJson(d as Map<String, dynamic>)).toList(),
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
      await _documents.upload(_token!, label: picked.name, contentType: picked.contentType, bytes: picked.bytes);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not upload — try again')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open — try again')));
    }
  }

  Future<void> _delete(TenantDocument document) async {
    if (_token == null) return;
    try {
      await _documents.delete(_token!, document.documentId);
      if (!mounted) return;
      setState(() => _items = _items.where((d) => d.documentId != document.documentId).toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove — try again')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        label: Text(_uploading ? 'Uploading…' : 'Upload'),
        icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_outlined),
      ),
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
                      child: NivasaStaleBanner(lastSyncedAt: _lastSyncedAt),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                                  child: Text(
                                    'No documents yet — tap "Upload" to add an ID proof or other document.',
                                    style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(NivasaSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: NivasaSpacing.s12),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return Container(
                                  padding: const EdgeInsets.all(NivasaSpacing.s16),
                                  decoration: BoxDecoration(
                                    color: NivasaColors.white,
                                    border: Border.all(color: NivasaColors.line),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_contentTypeIcons[item.contentType] ?? Icons.description_outlined, color: NivasaColors.primary700),
                                      const SizedBox(width: NivasaSpacing.s12),
                                      Expanded(child: Text(item.label, style: NivasaText.body, overflow: TextOverflow.ellipsis)),
                                      IconButton(icon: const Icon(Icons.download_outlined), onPressed: () => _download(item)),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, color: NivasaColors.negativeFg),
                                        onPressed: () => _delete(item),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
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
