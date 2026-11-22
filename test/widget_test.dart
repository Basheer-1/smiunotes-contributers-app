import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_navigation.dart';

void main() {
  test('Contributor workspace is HTTPS and within allowed routes', () {
    final url = Uri.https('smiunotes.com', '/staff');
    expect(url.scheme, 'https');
    expect(ContributorNavigation.classify(url.toString()),
        ContributorDestination.internal);
  });

  test('Contributors can use existing login and recovery', () {
    for (final path in ['/login', '/auth/callback', '/account-recovery', '/profile']) {
      expect(ContributorNavigation.classify('https://smiunotes.com$path'),
          ContributorDestination.internal);
    }
  });

  test('Admin, updater and unrelated website pages stay outside app', () {
    for (final path in ['/admin', '/updates', '/editor', '/', '/staffing']) {
      expect(ContributorNavigation.classify('https://smiunotes.com$path'),
          ContributorDestination.blocked);
    }
  });

  test('Host confusion and nonsecure URLs cannot open internally', () {
    expect(ContributorNavigation.classify('https://smiunotes.com.evil.test/staff'),
        ContributorDestination.external);
    expect(ContributorNavigation.classify('http://smiunotes.com/staff'),
        ContributorDestination.blocked);
    expect(ContributorNavigation.classify('javascript:alert(1)'),
        ContributorDestination.blocked);
  });

  test('External HTTPS and mail links open outside the app', () {
    expect(ContributorNavigation.classify('https://example.com/document'),
        ContributorDestination.external);
    expect(ContributorNavigation.classify('mailto:help@example.com'),
        ContributorDestination.external);
  });
}
