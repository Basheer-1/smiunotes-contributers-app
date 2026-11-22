import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiOrigin = 'https://smiunotes.com';

class ContributorSession {
  const ContributorSession(this.accessToken, this.refreshToken);
  final String accessToken;
  final String refreshToken;
  factory ContributorSession.parse(Map<String, dynamic> json) {
    final session = json['session'];
    if (session is! Map<String, dynamic>) throw const FormatException('Invalid sign-in response');
    final a = session['access_token'], r = session['refresh_token'];
    if (a is! String || a.length < 30 || r is! String || r.length < 12) {
      throw const FormatException('Invalid session');
    }
    return ContributorSession(a, r);
  }
}

class ContributorApi {
  static const _vault = FlutterSecureStorage();
  static const _key = 'smiunotes.contributor.session.v1';
  ContributorSession? session;

  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic>? body, bool authenticate = true,
       String method = 'GET'}) async {
    final uri = Uri.parse(apiOrigin).resolve(path);
    if (uri.scheme != 'https' || uri.host != 'smiunotes.com') {
      throw const FormatException('Untrusted API endpoint');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(
        method == 'GET' && body != null ? 'POST' : method == 'GET' && body == null
          ? 'GET' : method,
        uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (authenticate) {
        final token = session?.accessToken;
        if (token == null) throw const HttpException('Sign-in required.');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.isRedirect) throw const HttpException('Unexpected redirect.');
      if (response.statusCode == 404) {
        await response.drain<void>();
        throw const HttpException('Contributor API is not deployed on this backend.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        if (bytes.length + chunk.length > 524288) {
          throw const FormatException('Response too large');
        }
        bytes.addAll(chunk);
      }
      final raw = utf8.decode(bytes, allowMalformed: false);
      Map<String, dynamic> parsed;
      try {
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) throw const FormatException('Unexpected JSON');
        parsed = json;
      } on FormatException {
        throw const HttpException('Backend returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = parsed['error'];
        throw HttpException(message is String && message.length < 180
            ? message : 'Backend request unavailable.');
      }
      return parsed;
    } finally {
      client.close(force: true);
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
    // Authorization check precedes persistence; revoked or admin/editor
    // accounts must never enter the contributor app.
    session = next;
    try {
      await workspace();
      await _vault.write(key: _key, value: jsonEncode({
        'access_token': next.accessToken,
        'refresh_token': next.refreshToken,
      }));
    } catch (_) {
      session = null;
      await _vault.delete(key: _key);
      rethrow;
    }
  }

  Future<bool> restore() async {
    try {
      final stored = await _vault.read(key: _key);
      if (stored == null) return false;
      final data = jsonDecode(stored);
      if (data is! Map<String, dynamic>) return false;
      final refresh = data['refresh_token'];
      if (refresh is! String || refresh.length < 12) return false;
      final result = await request('/api/mobile/v1/session',
          authenticate: false, body: {'op': 'refresh', 'refreshToken': refresh});
      session = ContributorSession.parse(result);
      await workspace();
      await _vault.write(key: _key, value: jsonEncode({
        'access_token': session!.accessToken,
        'refresh_token': session!.refreshToken,
      }));
      return true;
    } catch (_) {
      session = null;
      await _vault.delete(key: _key);
      return false;
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
  Future<void> createDraft(String title, String description, String subjectId) async {
    await request('/api/mobile/v1/contributor-workspace',
        body: {'title': title, 'description': description, 'subject_id': subjectId});
  }

  Future<void> updateDraft(String id, String title, String description,
      String subjectId) async {
    await request('/api/mobile/v1/contributor-notes/$id', method: 'PATCH',
      body: {'title': title, 'description': description, 'subject_id': subjectId});
  }

  Future<void> deleteDraft(String id) async {
    await request('/api/mobile/v1/contributor-notes/$id', method: 'DELETE');
  }

  Future<void> signOut() async {
    final current = session;
    session = null;
    try {
      if (current != null) {
        session = current;
        await request('/api/mobile/v1/session', body: {'op': 'logout'});
      }
    } finally {
      session = null;
      await _vault.delete(key: _key);
    }
  }
}
