import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../auth/auth_repository.dart';
import '../rental/rental_repository.dart';
import 'renewal_repository.dart';

class RenewalScreen extends StatefulWidget {
  const RenewalScreen({super.key, this.authRepository, this.renewalRepository, this.rentalRepository});

  final AuthRepository? authRepository;
  final RenewalRepository? renewalRepository;
  final RentalRepository? rentalRepository;

  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final RenewalRepository _renewals = widget.renewalRepository ?? RenewalRepository();
  late final RentalRepository _rentals = widget.rentalRepository ?? RentalRepository();

  String? _token;
  Agreement? _agreement;
  List<RenewalRequest> _requests = [];
  DateTime? _preferredEndDate;
  bool _loading = true;
  bool _requesting = false;
  String? _error;

  bool get _hasPending => _requests.any((r) => r.status == 'pending');

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
      final results = await Future.wait([_rentals.fetch(_token!), _renewals.list(_token!)]);
      if (!mounted) return;
      setState(() {
        _agreement = (results[0] as RentalInfo).agreement;
        _requests = results[1] as List<RenewalRequest>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your renewal details — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPreferredDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredEndDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _preferredEndDate = picked);
  }

  Future<void> _requestRenewal() async {
    if (_token == null) return;
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final requestedEndDate = _preferredEndDate == null
          ? null
          : '${_preferredEndDate!.year.toString().padLeft(4, '0')}-${_preferredEndDate!.month.toString().padLeft(2, '0')}-${_preferredEndDate!.day.toString().padLeft(2, '0')}';
      await _renewals.request(_token!, requestedEndDate: requestedEndDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Renewal requested — your property manager has been notified')));
      await _load();
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A renewal request is already pending')));
        await _load();
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error = 'Could not send the request — try again');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Renewal')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                  children: [
                    if (_agreement != null)
                      Container(
                        padding: const EdgeInsets.all(NivasaSpacing.s16),
                        decoration: BoxDecoration(
                          color: NivasaColors.white,
                          border: Border.all(color: NivasaColors.line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current agreement', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                            const SizedBox(height: NivasaSpacing.s8),
                            Text(
                              _agreement!.endDate != null ? 'Ends ${_agreement!.endDate}' : 'No end date on file',
                              style: NivasaText.h3,
                            ),
                          ],
                        ),
                      )
                    else
                      Text('No agreement on file yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    const SizedBox(height: NivasaSpacing.s24),
                    if (_hasPending)
                      Container(
                        padding: const EdgeInsets.all(NivasaSpacing.s16),
                        decoration: BoxDecoration(
                          color: NivasaColors.warningTint,
                          border: Border.all(color: NivasaColors.warningTintBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'A renewal request is pending — your property manager has been notified.',
                          style: NivasaText.body.copyWith(color: NivasaColors.warningTextOnTint),
                        ),
                      )
                    else ...[
                      TextButton(
                        onPressed: _requesting ? null : _pickPreferredDate,
                        child: Text(
                          _preferredEndDate == null
                              ? 'Set a preferred end date (optional)'
                              : 'Preferred end date: ${_preferredEndDate!.year}-${_preferredEndDate!.month.toString().padLeft(2, '0')}-${_preferredEndDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                      const SizedBox(height: NivasaSpacing.s8),
                      NivasaPrimaryButton(
                        label: 'Request renewal',
                        loading: _requesting,
                        loadingLabel: 'Sending…',
                        onPressed: _requestRenewal,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: NivasaSpacing.s16),
                      Text(_error!, style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
                    ],
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Request history', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                    const SizedBox(height: NivasaSpacing.s8),
                    if (_requests.isEmpty)
                      Text('No renewal requests yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500))
                    else
                      ..._requests.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: NivasaSpacing.s8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.requestedEndDate != null ? 'Requested end date: ${r.requestedEndDate}' : 'Requested ${r.createdAt}',
                                  style: NivasaText.body,
                                ),
                              ),
                              Text(
                                r.status == 'pending' ? 'Pending' : 'Acknowledged',
                                style: NivasaText.body.copyWith(
                                  color: r.status == 'pending' ? NivasaColors.warningTextOnTint : NivasaColors.positiveTextOnTint,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
