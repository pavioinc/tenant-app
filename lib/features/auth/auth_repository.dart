import '../../core/api_client.dart';
import '../../core/session_store.dart';

/// Renters sign up directly with full name/email/password — a general NivasaOS platform
/// account, not gated behind a pre-existing `tenants` row (see auth-service's
/// tenantAuth.ts "tenant_accounts vs. tenants" reasoning). A fresh signup is
/// "unconnected" until a property manager adds this same email via tenant-service, at
/// which point [TenantUser.connected] flips to true. Connection status is never cached
/// beyond what's in the current session — [refreshConnectionStatus] is how the app picks
/// up a manager having linked the renter in the meantime.
class AuthRepository {
  AuthRepository({ApiClient? apiClient, SessionStore? sessionStore})
    : _api = apiClient ?? ApiClient(),
      _sessions = sessionStore ?? SessionStore();

  final ApiClient _api;
  final SessionStore _sessions;

  Future<Session> signup({required String fullName, required String email, required String password}) async {
    final body = await _api.post('/api/auth/v1/tenant/signup', {'full_name': fullName, 'email': email, 'password': password});
    return _saveSession(body);
  }

  Future<Session> login({required String email, required String password}) async {
    final body = await _api.post('/api/auth/v1/tenant/login', {'email': email, 'password': password});
    return _saveSession(body);
  }

  Future<Session> _saveSession(Map<String, dynamic> body) async {
    final session = Session(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      user: TenantUser.fromJson(body['user'] as Map<String, dynamic>),
    );
    await _sessions.save(session);
    return session;
  }

  Future<Session?> currentSession() => _sessions.read();

  /// Rotates the refresh token (which re-checks the connection fresh server-side, see
  /// auth-service's tokens.ts /refresh handler) and then reads the up-to-date profile via
  /// GET /tenant/me — /refresh alone only returns a token pair, not `connected`/org/
  /// property/tenant fields. Call this from the home screen's "check connection" action
  /// and on app resume, since the backend never pushes this — the client has to ask.
  Future<Session> refreshConnectionStatus() async {
    final current = await _sessions.read();
    if (current == null) {
      throw StateError('no active session to refresh');
    }
    final refreshed = await _api.post('/api/auth/v1/refresh', {'refresh_token': current.refreshToken});
    final newAccessToken = refreshed['access_token'] as String;
    final newRefreshToken = refreshed['refresh_token'] as String;
    final me = await _api.get('/api/auth/v1/tenant/me', token: newAccessToken);
    final session = Session(accessToken: newAccessToken, refreshToken: newRefreshToken, user: TenantUser.fromJson(me));
    await _sessions.save(session);
    return session;
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
    }
    await _sessions.clear();
  }
}
