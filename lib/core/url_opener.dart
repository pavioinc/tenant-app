import 'package:url_launcher/url_launcher.dart';

/// Thin seam over `url_launcher`, same shape/reason as `FilePickerService` — a platform
/// channel `flutter test` can't exercise, so tests inject a fake instead.
abstract class UrlOpener {
  Future<bool> open(String url);
}

class RealUrlOpener implements UrlOpener {
  const RealUrlOpener();

  @override
  Future<bool> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
