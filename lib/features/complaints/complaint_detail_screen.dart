import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_skeleton.dart';
import '../auth/auth_repository.dart';
import 'complaints_repository.dart';

/// Answers the design review's IA-9 finding — Maintenance cards weren't tappable, so a
/// renter could see a status badge change color but never what a manager actually said
/// or did about it. Backed by tenant-service's `complaint_notes` table (2026-08-31): a
/// real back-and-forth thread, not the single mutable `resolution_note` field the
/// manager side used to be limited to. Styled as a WhatsApp-style bubble thread using
/// PavioColors' existing chatCanvas/inboundBubble/outboundBubble tokens — defined for
/// exactly this "Product Pattern" but unused anywhere until now.
class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({
    super.key,
    required this.complaint,
    this.authRepository,
    this.complaintsRepository,
  });

  final Complaint complaint;
  final AuthRepository? authRepository;
  final ComplaintsRepository? complaintsRepository;

  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ComplaintsRepository _complaints =
      widget.complaintsRepository ?? ComplaintsRepository();
  final _messageController = TextEditingController();

  String? _token;
  List<ComplaintNote> _notes = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
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
      final notes = await _complaints.listNotes(
        _token!,
        widget.complaint.complaintId,
      );
      if (!mounted) return;
      setState(() => _notes = notes);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load updates — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _token == null || _sending) return;
    setState(() => _sending = true);
    try {
      final note = await _complaints.addNote(
        _token!,
        widget.complaint.complaintId,
        text,
      );
      if (!mounted) return;
      setState(() => _notes = [..._notes, note]);
      _messageController.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send — try again')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg) = complaintStatusColors(widget.complaint.status);
    return Scaffold(
      appBar: AppBar(title: Text(widget.complaint.category)),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(PavioSpacing.s16),
              decoration: const BoxDecoration(
                color: PavioColors.white,
                border: Border(bottom: BorderSide(color: PavioColors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(
                            PavioRadius.pill,
                          ),
                        ),
                        child: Text(
                          complaintStatusLabels[widget.complaint.status] ??
                              widget.complaint.status,
                          style: PavioText.badge.copyWith(color: badgeFg),
                        ),
                      ),
                      const SizedBox(width: PavioSpacing.s8),
                      Text(
                        formatDisplayDate(widget.complaint.createdAt),
                        style: PavioText.bodySmall.copyWith(
                          color: PavioColors.ink500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PavioSpacing.s8),
                  Text(widget.complaint.description, style: PavioText.body),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: PavioColors.chatCanvas,
                child: _loading
                    ? const _NotesLoadingSkeleton()
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(PavioSpacing.s24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: PavioText.body.copyWith(
                                  color: PavioColors.ink500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: PavioSpacing.s16),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _notes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(PavioSpacing.s24),
                          child: Text(
                            'No updates yet — your property manager will reply here.',
                            style: PavioText.body.copyWith(
                              color: PavioColors.ink500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(PavioSpacing.s16),
                        itemCount: _notes.length,
                        itemBuilder: (context, index) =>
                            _NoteBubble(note: _notes[index]),
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                PavioSpacing.s16,
                PavioSpacing.s12,
                PavioSpacing.s16,
                PavioSpacing.s12,
              ),
              decoration: const BoxDecoration(
                color: PavioColors.white,
                border: Border(top: BorderSide(color: PavioColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: PavioText.body,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add an update…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: PavioSpacing.s8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PavioColors.white,
                            ),
                          )
                        : const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the chat timeline's real shape (doc option "1l") — bubble-sized bones
/// alternating sides, so the thread doesn't jump from a spinner straight into bubbles.
class _NotesLoadingSkeleton extends StatelessWidget {
  const _NotesLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bubble(double width, {required bool left}) => Align(
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      child: PavioSkeleton(
        width: width,
        height: 44,
        borderRadius: PavioRadius.lg,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(PavioSpacing.s16),
      child: Column(
        children: [
          bubble(200, left: true),
          const SizedBox(height: PavioSpacing.s12),
          bubble(160, left: false),
          const SizedBox(height: PavioSpacing.s12),
          bubble(230, left: true),
        ],
      ),
    );
  }
}

class _NoteBubble extends StatelessWidget {
  const _NoteBubble({required this.note});

  final ComplaintNote note;

  @override
  Widget build(BuildContext context) {
    // Tenant's own notes render like an outbound WhatsApp message (right, green);
    // manager notes render inbound (left, white) with the manager's name above the
    // bubble — there can be more than one manager on a thread, unlike a 1:1 DM.
    final isMine = !note.isFromManager;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: PavioSpacing.s8),
        padding: const EdgeInsets.all(PavioSpacing.s12),
        decoration: BoxDecoration(
          color: isMine
              ? PavioColors.outboundBubble
              : PavioColors.inboundBubble,
          borderRadius: BorderRadius.circular(PavioRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: PavioSpacing.s4),
                child: Text(
                  note.authorName ?? 'Property manager',
                  style: PavioText.badge.copyWith(
                    color: PavioColors.primary700,
                  ),
                ),
              ),
            Text(note.body, style: PavioText.body),
            const SizedBox(height: PavioSpacing.s4),
            Text(formatDisplayDate(note.createdAt), style: PavioText.caption),
          ],
        ),
      ),
    );
  }
}
