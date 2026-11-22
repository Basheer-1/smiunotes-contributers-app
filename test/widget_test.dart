import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_navigation.dart';

void main() {
  test('Approved SMIUNotes paths remain within the contributor shell', () {
    for (final path in ['/verify', '/login', '/staff', '/staff/notes/new',
      '/staff/notes/abc', '/profile', '/notifications', '/auth/callback']) {
      expect(ContributorNavigation.classify('https://smiunotes.com$path'),
          ContributorDestination.internal);
    }
  });

  test('Administrative and editing routes are unavailable in the shell', () {
    for (final path in ['/admin', '/updates', '/editor', '/staffing',
      '/api/staff', '/community']) {
      expect(ContributorNavigation.classify('https://smiunotes.com$path'),
          ContributorDestination.blocked);
    }
  });

  test('External links must be opened outside the WebView', () {
    expect(ContributorNavigation.classify('https://example.com'),
        ContributorDestination.external);
    expect(ContributorNavigation.classify('mailto:test@example.com'),
        ContributorDestination.external);
  });

  test('Unsafe URL forms are blocked', () {
    for (final url in ['http://smiunotes.com/staff',
      'javascript:alert(1)', 'https://name@smiunotes.com/staff',
      'file:///etc/passwd', 'not a uri']) {
      expect(ContributorNavigation.classify(url),
          ContributorDestination.blocked);
    }
  });
}
