/// App-level navigation policy. This is NOT an authorization boundary.
/// The website must authenticate and authorize every contributor operation.
enum ContributorDestination { internal, external, blocked }

class ContributorNavigation {
  static const host = 'smiunotes.com';

  static ContributorDestination classify(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return ContributorDestination.blocked;
    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      return ContributorDestination.external;
    }
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return ContributorDestination.blocked;
    }
    final hostname = uri.host.toLowerCase();
    if (hostname != host && hostname != 'www.$host') {
      return ContributorDestination.external;
    }
    final path = uri.path;
    for (final prefix in const [
      '/staff', '/verify', '/login', '/auth',
      '/account-recovery', '/forgot-password',
      '/profile', '/notifications', '/privacy',
    ]) {
      if (path == prefix || path.startsWith('$prefix/')) {
        return ContributorDestination.internal;
      }
    }
    // Website can briefly redirect signed-in users to home. Keep it
    // reachable without exposing admin/editor navigation.
    if (path == '/') return ContributorDestination.internal;
    return ContributorDestination.blocked;
  }
}
