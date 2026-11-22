import 'dart:io';
import 'dart:typed_data';
import 'contributor_api.dart';

/// Fetch the signed-in contributor's existing SMIUNotes avatar in memory.
/// Never persist the image or expose the bearer token in a public URL.
class ContributorAvatar {
  const ContributorAvatar(this.api);
  final ContributorApi api;

  Future<Uint8List?> load() async {
    final token = api.session?.accessToken;
    if (token == null || !RegExp(r'^[A-Za-z0-9._-]{30,4096}$').hasMatch(token)) {
      throw const FormatException('Login required.');
    }
    final uri = Uri.https('smiunotes.com', '/api/mobile/v1/avatar');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'image/webp') {
        throw const HttpException('Avatar unavailable.');
      }
      final result = BytesBuilder(copy: false);
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes += chunk.length;
        if (bytes > 500000) throw const FormatException('Invalid avatar size.');
        result.add(chunk);
      }
      return result.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}
