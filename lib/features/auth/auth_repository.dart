import 'dart:async' show unawaited;
import '../../core/api_client.dart';
import '../../core/push_notifications.dart';
import '../../core/session_store.dart';

/// Renters sign up directly with full name/email/password — a general NivasaOS platform
/// account, not gated behind a pre-existing `tenants` row (see auth-service's
/// tenantAuth.ts "tenant_accounts vs. tenants" reasoning). A fresh signup is
/// "unconnected" until a property manager adds this same email via tenant-service, at
/// which point [TenantUser.connected] flips to true. Connection status is never cached
/// beyond what's in the current session — [refreshConnectionStatus] is how the app picks
/// up a manager having linked the renter in the meantime.
class AuthRepository {
  AuthRepository({ApiClient? apiClient, SessionStore? sessionStore, PushNotifications? pushNotifications})
    : _api = apiClient ?? ApiClient(),
      _sessions = sessionStore ?? SessionStore(),
      _push = pushNotifications ?? PushNotifications();

  final ApiClient _api;
  final SessionStore _sessions;
  final PushNotifications _push;

  Future<Session> signup({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? birthdate,
  }) async {
    final body = await _api.post('/api/auth/v1/tenant/signup', {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'password': password,
      'birthdate': ?birthdate,
    });
    final session = await _saveSession(body);
    // Fire-and-forget — a push-registration failure (declined permission, no Firebase
    // project configured yet) must never block or fail signup/login itself.
    unawaited(_push.register(session.accessToken));
    return session;
  }

  Future<Session> login({required String email, required String password}) async {
    final body = await _api.post('/api/auth/v1/tenant/login', {'email': email, 'password': password});
    final session = await _saveSession(body);
    unawaited(_push.register(session.accessToken));
    return session;
  }

  Future<Session> _saveSession(Map<String, dynamic> body) async {
    final session = Session(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      user: TenantUser.fromJson(body['user'] as Map<String, dynamic>),
      accessTokenExpiresAt: DateTime.parse(body['expires_at'] as String),
    );
    await _sessions.save(session);
    return session;
  }

  Future<Session?>? _refreshInFlight;

  /// The one method every screen calls before making its own API requests — this is
  /// where access-token expiry is handled for the whole app, not per-screen. Access
  /// tokens live 30 minutes (auth-service's ACCESS_TOKEN_TTL_SECONDS); before this
  /// existed, every screen just read whatever token secure storage had and sent it
  /// as-is, so any session older than 30 minutes surfaced "jwt expired" from
  /// api-gateway's JWT verification on essentially every request (the real bug this
  /// fixes — see auth-service's jwt.ts / api-gateway's requireAuth). A session with no
  /// recorded expiry (saved before this field existed) is treated as needing a refresh
  /// too, not as "assume still valid" — the whole point is to heal already-broken
  /// sessions, not just protect new ones. Concurrent callers during the same expiry
  /// window share one in-flight refresh via [_refreshInFlight] rather than each
  /// triggering their own — `/refresh` rotates the refresh token itself, so two
  /// simultaneous calls would make the second one fail with an "already used" refresh
  /// token if they weren't deduped.
  Future<Session?> currentSession() async {
    final session = await _sessions.read();
    if (session == null) return null;
    if (_isFresh(session)) return session;
    return _refreshInFlight ??= _refreshStaleSession().whenComplete(() => _refreshInFlight = null);
  }

  bool _isFresh(Session session) {
    final expiresAt = session.accessTokenExpiresAt;
    if (expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt.subtract(const Duration(seconds: 30)));
  }

  Future<Session?> _refreshStaleSession() async {
    try {
      return await rotateTokens();
    } on ApiException {
      // auth-service rejected the refresh token outright (expired/revoked/reused,
      // e.g. past its 7-day TTL) — the session is genuinely gone. Clear it so
      // callers' existing "no active session" handling takes over, instead of
      // retrying forever with tokens that will never work.
      await _sessions.clear();
      return null;
    }
    // Any other exception (connectivity failure mid-refresh) intentionally
    // propagates, leaving the stale session in storage untouched — same as this
    // app's existing offline-handling convention, a network hiccup shouldn't force
    // a real logout.
  }

  /// Calls POST /refresh and persists the new token pair against the *current*
  /// session's user — does not re-check connection status (that needs a follow-up
  /// GET /tenant/me, since /refresh alone only returns tokens). See
  /// [refreshConnectionStatus] for the version that also does that.
  Future<Session> rotateTokens() async {
    final current = await _sessions.read();
    if (current == null) {
      throw StateError('no active session to refresh');
    }
    final refreshed = await _api.post('/api/auth/v1/refresh', {'refresh_token': current.refreshToken});
    final session = Session(
      accessToken: refreshed['access_token'] as String,
      refreshToken: refreshed['refresh_token'] as String,
      user: current.user,
      accessTokenExpiresAt: DateTime.parse(refreshed['expires_at'] as String),
    );
    await _sessions.save(session);
    return session;
  }

  /// Rotates the refresh token (which re-checks the connection fresh server-side, see
  /// auth-service's tokens.ts /refresh handler) and then reads the up-to-date profile via
  /// GET /tenant/me — /refresh alone only returns a token pair, not `connected`/org/
  /// property/tenant fields. Call this from the home screen's "check connection" action
  /// and on app resume, since the backend never pushes this — the client has to ask.
  Future<Session> refreshConnectionStatus() async {
    final rotated = await rotateTokens();
    final me = await _api.get('/api/auth/v1/tenant/me', token: rotated.accessToken);
    final session = Session(
      accessToken: rotated.accessToken,
      refreshToken: rotated.refreshToken,
      user: TenantUser.fromJson(me),
      accessTokenExpiresAt: rotated.accessTokenExpiresAt,
    );
    await _sessions.save(session);
    return session;
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final session = await currentSession();
    if (session == null) throw StateError('no active session');
    await _api.patch(
      '/api/auth/v1/tenant/password',
      {'current_password': currentPassword, 'new_password': newPassword},
      token: session.accessToken,
    );
  }

  Future<void> logout() async {
    final session = await _sessions.read();
    if (session != null) {
      try {
        await _api.post('/api/auth/v1/logout', {'refresh_token': session.refreshToken});
      } catch (_) {
        // Best-effort — clear the local session regardless, same rationale as
        // owner-dashboard's AccountMenu.onLogout.
      }
      await _push.unregister(session.accessToken);
    }
    await _sessions.clear();
  }
}
