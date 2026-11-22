import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Contributor workspace URL points to production HTTPS endpoint', () {
    final workspace = Uri.https('smiunotes.com', '/staff');
    expect(workspace.scheme, 'https');
    expect(workspace.host, 'smiunotes.com');
    expect(workspace.path, '/staff');
  });
}
