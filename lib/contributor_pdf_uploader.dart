import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'contributor_api.dart';

/// Uploads only PDFs to short-lived server-issued R2 capabilities.
/// The mobile API and Edge function both recheck role, ownership and draft.
class ContributorPdfUploader {
  const ContributorPdfUploader(this.api);
  final ContributorApi api;

  Future<void> chooseAndUpload(String noteId) async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
    );
    if (selected == null || selected.files.isEmpty) return;
    final picked = selected.files.single;
    final path = picked.path;
    if (path == null) throw const FormatException('Unable to open selected file.');
    final file = File(path);
    final size = await file.length();
    if (size < 20 || size > 20 * 1024 * 1024) {
      throw const FormatException('PDF must be 20 MiB or smaller.');
    }
    final head = await file.open();
    try {
      final magic = await head.read(5);
      if (ascii.decode(magic, allowInvalid: true) != '%PDF-') {
        throw const FormatException('This is not a valid PDF.');
      }
    } finally {
      await head.close();
    }
    final result = await api.request('/api/mobile/v1/contributor-media',
      body: {'op': 'prepare', 'id': noteId, 'bytes': size});
    final ticket = result['ticket'];
    if (ticket is! Map<String, dynamic> || ticket['provider'] != 'r2') {
      throw const FormatException('Private R2 upload unavailable.');
    }
    final uri = Uri.tryParse(ticket['url']?.toString() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid upload capability.');
    }
    final headers = ticket['headers'];
    if (headers is! Map<String, dynamic>) {
      throw const FormatException('Invalid upload headers.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.putUrl(uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      for (final entry in headers.entries) {
        if (entry.value is! String) {
          throw const FormatException('Invalid signed upload header.');
        }
        request.headers.set(entry.key, entry.value as String);
      }
      request.contentLength = size;
      await request.addStream(file.openRead()).timeout(const Duration(minutes: 2));
      final response = await request.close().timeout(const Duration(seconds: 30));
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const HttpException('Private PDF upload was not accepted.');
      }
    } finally {
      client.close(force: true);
    }
    final verified = await api.request('/api/mobile/v1/contributor-media',
        body: {'op': 'verify', 'id': noteId});
    if (verified['ok'] != true) {
      throw const FormatException('PDF verification failed.');
    }
  }
}
