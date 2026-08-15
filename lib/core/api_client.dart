import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Thrown for any non-2xx response from api-gateway. [code] is the JSON body's `error`
/// field when present (e.g. 'email_taken', 'invalid_credentials'), so screens can match
/// on it instead of parsing [message] — mirrors owner-dashboard/lib/api.ts's ApiError.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

/// Talks to api-gateway only — this app never calls a backend service directly, same
/// principle as owner-dashboard. [token], when given, is attached as a Bearer
/// Authorization header — needed for endpoints behind the gateway's authenticated
/// catch-all (e.g. GET /tenant/me), unlike signup/login/refresh which are public.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? httpClient}) : baseUrl = baseUrl ?? _defaultBaseUrl(), _client = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// 10.0.2.2 is the Android emulator's alias for the host machine's localhost — a
  /// physical device or simulator needs the host's real LAN IP instead, set via
  /// `--dart-define=API_BASE_URL=http://<lan-ip>:4000` at run time.
  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? token}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    final res = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body, {String? token}) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, (body['error'] as String?) ?? 'request_error', (body['message'] as String?) ?? 'request failed');
    }
    return body;
  }
}
