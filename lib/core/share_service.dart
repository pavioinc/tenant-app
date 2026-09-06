import 'package:share_plus/share_plus.dart';

/// Thin seam over `share_plus`, same shape/reason as `UrlOpener` — a platform channel
/// `flutter test` can't exercise, so tests inject a fake instead.
abstract class ShareService {
  Future<void> shareUrl(String url);
}

class RealShareService implements ShareService {
  const RealShareService();

  @override
  Future<void> shareUrl(String url) async {
    await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
  }
}
