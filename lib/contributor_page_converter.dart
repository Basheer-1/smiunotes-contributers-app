import 'dart:io';
import 'package:flutter/services.dart';

import 'contributor_api.dart';
import 'contributor_pdf_uploader.dart';

/// Native Android PDF -> watermarked WebP pipeline.
/// Uses the existing note-media server verification and short-lived R2 URLs.
/// A render is NOT marked ready until the Edge function independently verifies
/// all uploaded pages, their size/dimensions and original SHA-256.
class ContributorPageConverter {
  const ContributorPageConverter(this.api);
  final ContributorApi api;
  static const _channel = MethodChannel('com.smiunotes.contributors/pdf_renderer');

  Future<Map<String, dynamic>> status(String id) => api.request(
    '/api/mobile/v1/contributor-render',
    body: {'op': 'status', 'id': id},
  );

  Future<void> reset(String id) async {
    final response = await api.request('/api/mobile/v1/contributor-render',
      body: {'op': 'reset', 'id': id});
    if (response['ok'] != true) throw const FormatException('Render reset failed.');
  }

  /// Obtain the already-verified original through the owner-only API.
  /// The signed URL is short-lived; bytes remain in a temporary file until
  /// conversion finishes and are never saved to public or gallery storage.
  Future<File> _fetchOriginal(String noteId) async {
    final ticket = await api.request('/api/mobile/v1/contributor-media',
      body: {'op': 'original', 'id': noteId});
    final raw = ticket['url'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      throw const FormatException('Invalid private PDF read link.');
    }
    final directory = await Directory.systemTemp.createTemp('smiunotes-pdf-');
    final result = File('${directory.path}/original.pdf');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          (response.contentLength > 20 * 1024 * 1024)) {
        throw const HttpException('Private PDF download was not accepted.');
      }
      var count = 0;
      final sink = result.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 40))) {
          count += chunk.length;
          if (count > 20 * 1024 * 1024) {
            throw const FormatException('Original PDF exceeds the file size limit.');
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (count < 20) throw const FormatException('Original PDF is empty.');
      final header = await result.openRead(0, 5).first;
      if (header.length < 5 ||
          String.fromCharCodes(header.take(5)) != '%PDF-') {
        throw const FormatException('Original file is not a valid PDF.');
      }
      return result;
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> convert(
    String noteId,
    void Function(int done, int total, String stage) onProgress,
  ) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Native PDF preparation requires Android.');
    }
    final state = await status(noteId);
    if (state['render'] != null) {
      throw StateError('This draft already has conversion data. Reset it before retrying.');
    }
    if (!await ContributorPdfUploader(api).originalExists(noteId)) {
      throw StateError('Upload the original PDF before preparing pages.');
    }
    onProgress(0, 0, 'Downloading your already-uploaded private PDF');
    final original = await _fetchOriginal(noteId);
    try {
    final path = original.path;
    final inspection = await _channel.invokeMapMethod<String, dynamic>(
      'inspect', {'path': path});
    if (inspection == null) throw const FormatException('PDF inspection failed.');
    final count = inspection['pageCount'], fingerprint = inspection['sha256'];
    if (count is! int || count < 1 || count > 60 ||
        fingerprint is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Invalid PDF conversion metadata.');
    }
    onProgress(0, count, 'Starting protected conversion');
    final created = await api.request('/api/mobile/v1/contributor-render', body: {
      'op': 'begin', 'id': noteId, 'count': count, 'sha': fingerprint,
    });
    final renderId = created['renderId'];
    if (renderId is! String) throw const FormatException('Render could not begin.');
    var totalBytes = 0;
    for (var page = 1; page <= count; page++) {
      onProgress(page - 1, count, 'Rendering page $page of $count');
      final pagePath = await _channel.invokeMethod<String>('renderPage', {
        'path': path, 'index': page - 1,
      });
      if (pagePath == null) throw const FormatException('Page renderer failed.');
      final file = File(pagePath);
      try {
        final size = await file.length();
        if (size < 1 || size > 1048576) {
          throw const FormatException('WebP page exceeds size limit.');
        }
        totalBytes += size;
        if (totalBytes > 24 * 1024 * 1024) {
          throw const FormatException('Converted pages exceed 24 MiB.');
        }
        final ticketResponse = await api.request(
          '/api/mobile/v1/contributor-render',
          body: {
            'op': 'ticket', 'id': noteId,
            'renderId': renderId, 'page': page, 'bytes': size,
          },
        );
        final ticket = ticketResponse['ticket'];
        if (ticket is! Map<String, dynamic> || ticket['provider'] != 'r2') {
          throw const FormatException('Signed page upload unavailable.');
        }
        final uri = Uri.tryParse(ticket['url']?.toString() ?? '');
        if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          throw const FormatException('Invalid page upload URL.');
        }
        final headers = ticket['headers'];
        if (headers is! Map<String, dynamic>) {
          throw const FormatException('Invalid signed upload headers.');
        }
        onProgress(page - 1, count, 'Uploading page $page of $count');
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        try {
          final upload = await client.putUrl(uri).timeout(const Duration(seconds: 15));
          upload.followRedirects = false;
          for (final item in headers.entries) {
            if (item.value is! String) {
              throw const FormatException('Invalid signed header.');
            }
            upload.headers.set(item.key, item.value as String);
          }
          upload.contentLength = size;
          await upload.addStream(file.openRead()).timeout(const Duration(minutes: 2));
          final response = await upload.close().timeout(const Duration(seconds: 30));
          await response.drain<void>();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw const HttpException('Private page upload failed.');
          }
        } finally {
          client.close(force: true);
        }
      } finally {
        await _channel.invokeMethod<void>('deleteTemporary', {'path': pagePath});
      }
      onProgress(page, count, 'Page $page uploaded');
    }
    onProgress(count, count, 'Verifying pages with SMIUNotes');
    final finalized = await api.request('/api/mobile/v1/contributor-render',
      body: {'op': 'finalize', 'id': noteId, 'renderId': renderId});
    if (finalized['ok'] != true || finalized['state'] != 'ready') {
      throw const FormatException('Page verification was not completed.');
    }
    onProgress(count, count, 'Ready for admin review');
    } finally {
      final directory = original.parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
