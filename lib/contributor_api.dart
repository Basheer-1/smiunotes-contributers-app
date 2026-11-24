import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiOrigin = 'https://smiunotes.com';

/// Only explicit authentication/authorization revocation should forget a saved login.
bool contributorCredentialsRevoked(int status) =>
    status == 400 || status == 401 || status == 403;

class ContributorApiException implements Exception {
  const ContributorApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// User-safe login diagnostics. Never include passwords, IDs or tokens.
String contributorAuthError(Object error) {
  if (error is ContributorApiException) {
    final message = error.message.toLowerCase();
    if (error.status == 409 || message.contains('maximum device limit')) {
      return 'Four active devices are already signed in. Open SMIUNotes '
          'Profile > Active devices and sign out an old device, then retry.';
    }
    if (error.status == 403 &&
        (message.contains('security verification') ||
         message.contains('turnstile'))) {
      return 'Security verification expired or failed. Retry sign in.';
    }
    if (error.status == 403 &&
        (message.contains('contributor') || message.contains('approved'))) {
      return 'Only approved contributors and administrators can open the '
          'Contributors App. Both use the same Contributor Workspace.';
    }
    if (error.status == 401 && message.contains('invalid credentials')) {
      return 'Student ID or password was not accepted. Check your existing '
          'SMIUNotes credentials. You can recover access on the website.';
    }
    if (error.status == 401) {
      return 'Your session has expired. Sign in again.';
    }
    if (error.status == 429) {
      return 'Too many attempts. Try again later.';
    }
    if (error.status == 503) {
      return 'The SMIUNotes sign-in service is temporarily unavailable. '
          'Your account is not necessarily invalid.';
    }
    if (error.status == 404) {
      return 'This Contributors feature is awaiting a backend update.';
    }
  }
  if (error is SocketException || error is TimeoutException ||
      error is HandshakeException) {
    return 'Cannot connect to SMIUNotes right now. Check your internet.';
  }
  return 'Unable to complete sign-in. Retry or open SMIUNotes account settings.';
}

class ContributorSession {
  const ContributorSession(this.accessToken, this.refreshToken);
  final String accessToken;
  final String refreshToken;
  factory ContributorSession.parse(Map<String, dynamic> json) {
    final raw = json['session'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid sign-in response');
    }
    final a = raw['access_token'], r = raw['refresh_token'];
    if (a is! String || a.length < 30 || r is! String || r.length < 12) {
      throw const FormatException('Invalid session');
    }
    return ContributorSession(a, r);
  }
}

class ContributorApi {
  ContributorApi({FlutterSecureStorage? storage})
      : _vault = storage ?? const FlutterSecureStorage();

  static const _key = 'smiunotes.contributor.session.v1';
  final FlutterSecureStorage _vault;
  ContributorSession? session;
  Future<void>? _refreshInFlight;

  Future<void> _save(ContributorSession value) =>
      _vault.write(key: _key, value: jsonEncode({
        'version': 1,
        'access_token': value.accessToken,
        'refresh_token': value.refreshToken,
      }));

  Future<void> _clear() async {
    session = null;
    await _vault.delete(key: _key);
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool authenticate = true,
    String method = 'GET',
  }) async {
    try {
      return await _send(path, body: body, authenticate: authenticate,
          method: method);
    } on ContributorApiException catch (error) {
      if (!authenticate || error.status != 401 || session == null ||
          path == '/api/mobile/v1/session') {
        rethrow;
      }
      // The current access JWT may have expired. Serialize rotation, then
      // replay only once. Invalid/revoked refresh tokens clear this device.
      await _refresh();
      return _send(path, body: body, authenticate: authenticate, method: method);
    }
  }

  Future<Map<String, dynamic>> _send(
    String path, {
    Map<String, dynamic>? body,
    required bool authenticate,
    required String method,
  }) async {
    final uri = Uri.parse(apiOrigin).resolve(path);
    if (uri.scheme != 'https' || uri.host != 'smiunotes.com' ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Untrusted API endpoint');
    }
    final actualMethod = method == 'GET' && body != null ? 'POST' : method;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(actualMethod, uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (authenticate) {
        final token = session?.accessToken;
        if (token == null) {
          throw const ContributorApiException(401, 'Sign-in required.');
        }
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close()
          .timeout(const Duration(seconds: 25));
      if (response.isRedirect) {
        throw const ContributorApiException(502, 'Unexpected redirect.');
      }
      if (response.statusCode == 404) {
        await response.drain<void>();
        throw const ContributorApiException(404,
            'Contributor API is not deployed on this backend.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        if (bytes.length + chunk.length > 524288) {
          throw const FormatException('Response too large.');
        }
        bytes.addAll(chunk);
      }
      Map<String, dynamic> parsed;
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        parsed = decoded;
      } on FormatException {
        throw const ContributorApiException(502,
            'Backend returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = parsed['error'];
        throw ContributorApiException(response.statusCode,
            message is String && message.length < 180
                ? message : 'Backend request unavailable.');
      }
      return parsed;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final work = _rotate();
    _refreshInFlight = work;
    return work.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _rotate() async {
    final old = session;
    if (old == null) {
      throw const ContributorApiException(401, 'Sign-in required.');
    }
    try {
      final result = await _send('/api/mobile/v1/session',
          authenticate: false, method: 'POST',
          body: {'op': 'refresh', 'refreshToken': old.refreshToken});
      final updated = ContributorSession.parse(result);
      // Persist every rotation before any downstream workspace request:
      // refresh tokens are single-use and must never be lost on app restart.
      await _save(updated);
      session = updated;
    } on ContributorApiException catch (error) {
      // A definite invalid/revoked session must be cleared. Connectivity,
      // rate limiting, or 5xx must NOT log the student out.
      if (contributorCredentialsRevoked(error.status)) {
        await _clear();
      }
      rethrow;
    }
  }

  Future<bool> isLoginEnabled() async {
    try {
      final status = await request('/api/mobile/v1/auth', authenticate: false);
      return status['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signIn(String id, String password, String challenge) async {
    final result = await request('/api/mobile/v1/auth', authenticate: false,
        body: {'op': 'password', 'studentId': id.trim().toUpperCase(),
          'password': password, 'turnstileToken': challenge});
    final next = ContributorSession.parse(result);
    session = next;
    // Persist an authenticated session immediately so that a temporary
    // contributor-workspace outage cannot create an orphan device slot.
    await _save(next);
    try {
      // The server authorizes both approved contributors and site admins;
      // the native UI always remains the contributor-only workspace.
      await workspace();
    } on ContributorApiException catch (error) {
      if (error.status == 403 || error.status == 401) {
        // A confirmed access rejection is NOT a contributor login.
        try {
          await signOut();
        } catch (_) {
          await _clear();
        }
      }
      // Network/429/5xx errors preserve the verified, encrypted login.
      rethrow;
    }
  }

  Future<bool> restore() async {
    final encoded = await _vault.read(key: _key);
    if (encoded == null) return false;
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) throw const FormatException();
      // Legacy installation saved the same fields without a version marker.
      if (data['version'] != null && data['version'] != 1) {
        throw const FormatException();
      }
      final tokens = ContributorSession.parse({'session': data});
      session = tokens;
    } on FormatException {
      await _clear();
      return false;
    }

    try {
      // Try the still-valid access JWT FIRST. Do not rotate refresh tokens
      // unnecessarily on each app launch.
      await workspace();
      return true;
    } on ContributorApiException catch (error) {
      if (error.status == 401 || error.status == 403) {
        // On a genuine revoked identity we clear credentials; a transient
        // route/rate-limit/5xx error must not behave like logout.
        await _clear();
        return false;
      }
      // Offline/5xx/404: keep encrypted credentials and show a retry screen.
      return session != null;
    } on IOException {
      return session != null;
    } on TimeoutException {
      return session != null;
    }
  }

  Future<Map<String, dynamic>> workspace() =>
      request('/api/mobile/v1/contributor-workspace');

  Future<Map<String, dynamic>> notifications() =>
      request('/api/mobile/v1/notifications');

  Future<void> markRead(String id) async {
    await request('/api/mobile/v1/notifications',
        body: {'op': 'read', 'id': id});
  }

  Future<int> clearNotifications() async {
    final response = await request('/api/mobile/v1/notifications',
        body: {'op': 'clear'});
    return response['cleared'] is int ? response['cleared'] as int : 0;
  }

  Future<String> createDraft(
      String title, String description, String subjectId,
      {bool verifiedOnly = false}) async {
    final result = await request('/api/mobile/v1/contributor-workspace',
        body: {'title': title, 'description': description,
          'subject_id': subjectId, 'is_sensitive': verifiedOnly});
    final newId = result['id'];
    if (result['ok'] != true || newId is! String || newId.length != 36 ||
        !RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').hasMatch(newId)) {
      throw const ContributorApiException(502, 'Draft ID confirmation failed.');
    }
    return newId;
  }

  Future<void> updateDraft(String id, String title, String description,
      String subjectId, {bool verifiedOnly = false}) async {
    await request('/api/mobile/v1/contributor-notes/$id', method: 'PATCH',
      body: {'title': title, 'description': description,
        'subject_id': subjectId, 'is_sensitive': verifiedOnly});
  }

  Future<void> deleteDraft(String id) async {
    await request('/api/mobile/v1/contributor-notes/$id', method: 'DELETE');
  }

  Future<void> signOut() async {
    final current = session;
    if (current == null) {
      await _clear();
      return;
    }
    // Never claim a device has been signed out if the network or backend
    // could not confirm revocation; otherwise its GoTrue slot is stranded.
    final result = await request('/api/mobile/v1/session',
        method: 'POST', body: {'op': 'logout'});
    if (result['signed_out'] != true) {
      throw const ContributorApiException(503,
          'Could not confirm device sign-out. Retry when online.');
    }
    await _clear();
  }
}
