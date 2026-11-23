import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_api.dart';

void main() {
  test('Native auth response requires opaque access and refresh tokens', () {
    expect(() => ContributorSession.parse({'session': {'access_token': 'no',
      'refresh_token': 'no'}}), throwsFormatException);
    expect(() => ContributorSession.parse({'session': null}), throwsFormatException);
    final session = ContributorSession.parse({'session': {
      'access_token': 'access_${'a' * 48}',
      'refresh_token': 'refresh_${'b' * 40}',
    }});
    expect(session.accessToken.startsWith('access_'), isTrue);
    expect(session.refreshToken.startsWith('refresh_'), isTrue);
  });

  test('Production Supabase 12-character refresh tokens are accepted', () {
    // Website server permits refresh tokens of >=12 characters.
    final session = ContributorSession.parse({'session': {
      'access_token': 'a' * 90,
      'refresh_token': '123456789012',
    }});
    expect(session.refreshToken, '123456789012');
    expect(() => ContributorSession.parse({'session': {
      'access_token': 'a' * 90,
      'refresh_token': '12345678901',
    }}), throwsFormatException);
  });

  test('Temporary backend failures never classify as revoked credentials', () {
    for (final status in [404, 408, 429, 500, 502, 503, 504]) {
      expect(contributorCredentialsRevoked(status), isFalse,
          reason: 'HTTP $status must preserve encrypted login');
    }
    for (final status in [400, 401, 403]) {
      expect(contributorCredentialsRevoked(status), isTrue);
    }
  });

  test('Four-device login limit has specific recovery message', () {
    final message = contributorAuthError(
      const ContributorApiException(409, 'Maximum device limit reached.'));
    expect(message, contains('Four active devices'));
    expect(message, contains('Active devices'));
    expect(message, isNot(contains('invalid password')));
  });

  test('Contributor and administrator workspace roles are both permitted', () {
    final message = contributorAuthError(
      const ContributorApiException(403, 'Contributor access required.'));
    expect(message, contains('contributors and administrators'));
    expect(message, contains('Contributor Workspace'));
  });

  test('Authentication failures remain distinguishable', () {
    expect(contributorAuthError(const ContributorApiException(401,
      'Invalid credentials or verification.')), contains('password'));
    expect(contributorAuthError(const ContributorApiException(503,
      'Sign-in temporarily unavailable.')), contains('temporarily'));
    expect(contributorAuthError(const ContributorApiException(403,
      'Security verification required.')), contains('Security verification'));
  });

  test('Missing or malformed session response fails closed', () {
    for (final response in [
      <String, dynamic>{},
      <String, dynamic>{'session': []},
      <String, dynamic>{'session': <String, dynamic>{'access_token': 3}},
    ]) {
      expect(() => ContributorSession.parse(response), throwsFormatException);
    }
  });
}
