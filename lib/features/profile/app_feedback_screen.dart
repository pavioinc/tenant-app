import 'package:flutter/material.dart';
import '../../core/url_opener.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';

const supportEmail = 'support@pavio.tech';

/// UserScreen's "App Feedback" row. There's no feedback-submission API anywhere in the
/// backend (checked tenant-service, notification-service — the closest thing is the
/// Complaints feature, which is property-maintenance-specific, not general app feedback),
/// so this hands the tenant's message to their own email client via a mailto: link rather
/// than pretending to submit it somewhere.
class AppFeedbackScreen extends StatefulWidget {
  const AppFeedbackScreen({super.key, this.urlOpener});

  final UrlOpener? urlOpener;

  @override
  State<AppFeedbackScreen> createState() => _AppFeedbackScreenState();
}

class _AppFeedbackScreenState extends State<AppFeedbackScreen> {
  late final UrlOpener _urlOpener = widget.urlOpener ?? const RealUrlOpener();
  final _messageController = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a message before sending');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final mailto = Uri(scheme: 'mailto', path: supportEmail, queryParameters: {'subject': 'Pavio app feedback', 'body': message});
    try {
      final opened = await _urlOpener.open(mailto.toString());
      if (!mounted) return;
      if (opened) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening your email app…')));
        Navigator.of(context).pop();
      } else {
        setState(() => _error = 'No email app found — write to $supportEmail directly');
      }
    } catch (_) {
      setState(() => _error = 'No email app found — write to $supportEmail directly');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Feedback')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PavioSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tell us what’s working, what’s not, or what you wish the app did.', style: PavioText.body.copyWith(color: PavioColors.ink500)),
              const SizedBox(height: PavioSpacing.s24),
              Text('Your feedback', style: PavioText.label),
              const SizedBox(height: PavioSpacing.s8),
              TextField(controller: _messageController, style: PavioText.body, minLines: 5, maxLines: 10),
              const SizedBox(height: PavioSpacing.s8),
              Text('Sent as an email to $supportEmail', style: PavioText.caption),
              if (_error != null) ...[
                const SizedBox(height: PavioSpacing.s16),
                Text(_error!, style: PavioText.body.copyWith(color: PavioColors.negativeFg)),
              ],
              const SizedBox(height: PavioSpacing.s24),
              PavioPrimaryButton(label: 'Send', loading: _sending, loadingLabel: 'Sending…', onPressed: _send),
            ],
          ),
        ),
      ),
    );
  }
}
