/// UI navigation rules for the contributor-only shell.
///
/// This is a UX restriction, NOT authorization. The SMIUNotes server must
/// independently enforce active approved-contributor permissions.
enum ContributorDestination { internal, external, blocked }

class ContributorNavigation {
  static const String host = 'smiunotes.com';

  static ContributorDestination classify(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return ContributorDestination.blocked;
    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      return ContributorDestination.external;
    }
    if (uri.scheme != 'https') return ContributorDestination.blocked;

    final normalizedHost = uri.host.toLowerCase();
    if (normalizedHost != host && normalizedHost != 'www.$host') {
      return ContributorDestination.external;
    }

    final path = uri.path;
    if (_matches(path, '/staff') ||
        _matches(path, '/login') ||
        _matches(path, '/auth') ||
        _matches(path, '/account-recovery') ||
        _matches(path, '/forgot-password') ||
        _matches(path, '/profile') ||
        _matches(path, '/privacy')) {
      return ContributorDestination.internal;
    }

    // Never navigate to /admin, /updates, /editor, or arbitrary website pages
    // inside this focused app. Does not grant or revoke permissions.
    return ContributorDestination.blocked;
  }

  static bool _matches(String path, String prefix) =>
      path == prefix || path.startsWith('$prefix/');
}
