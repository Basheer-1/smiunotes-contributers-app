import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_api.dart';

void main() {
  test('Native auth response requires opaque access and refresh tokens', () {
    expect(() => ContributorSession.parse({'session': {'access_token': 'no',
      'refresh_token': 'no'}}), throwsFormatException);
    expect(() => ContributorSession.parse({'session': null}), throwsFormatException);
    final session = ContributorSession.parse({'session': {
      'access_token': 'access_' + 'a' * 48,
      'refresh_token': 'refresh_' + 'b' * 40,
    }});
    expect(session.accessToken.startsWith('access_'), isTrue);
    expect(session.refreshToken.startsWith('refresh_'), isTrue);
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
