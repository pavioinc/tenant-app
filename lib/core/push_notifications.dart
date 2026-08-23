import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'api_client.dart';

/// Requests push permission, registers this device's FCM token with
/// notification-service, and unregisters it on logout — see
/// notification-service/src/routes/deviceTokens.ts.
///
/// Firebase isn't configured in every environment (no google-services.json /
/// GoogleService-Info.plist until a real Firebase project is set up — see
/// tenant-app/README.md's "Push notifications" section for the one-time setup this
/// needs). Every method here is best-effort: it must never throw into a caller on the
/// login/signup/logout path, since push is a supplementary channel, not a requirement to
/// use the app (WhatsApp/SMS rent-due reminders keep working regardless).
class PushNotifications {
  PushNotifications({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static bool? _firebaseReady;

  static Future<bool> _ensureInitialized() async {
    if (_firebaseReady != null) return _firebaseReady!;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
    }
    return _firebaseReady!;
  }

  String get _platform => !kIsWeb && Platform.isIOS ? 'ios' : 'android';

  /// Call after a successful login/signup, and again on app relaunch with an existing
  /// session (see main.dart's _SessionGate) — safe to call repeatedly, the backend
  /// upserts by token (see deviceTokens.ts). No-ops quietly if Firebase isn't
  /// configured yet or the user declines the permission prompt.
  Future<void> register(String accessToken) async {
    try {
      if (!await _ensureInitialized()) return;
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _api.post('/api/notification/v1/device-tokens', {'fcm_token': token, 'platform': _platform}, token: accessToken);
    } catch (_) {
      // Best-effort — see class doc comment.
    }
  }

  /// Call on logout, before the session is cleared — stops this device from receiving
  /// pushes meant for the account that just signed out of it.
  Future<void> unregister(String accessToken) async {
    try {
      if (!await _ensureInitialized()) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _api.delete('/api/notification/v1/device-tokens', token: accessToken, body: {'fcm_token': token});
    } catch (_) {
      // Best-effort — see class doc comment.
    }
  }
}
