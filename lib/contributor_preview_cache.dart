import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'contributor_api.dart';

/// Keeps a small window of protected preview images in memory so revisiting a
/// page never needs another signed URL. All data is discarded when the viewer
/// closes; the private pages are never written to public device storage.
class ContributorPreviewCache {
  ContributorPreviewCache(this.api, this.noteId,
      {this.capacity = 5, this.pageLoader});
  final ContributorApi api;
  final String noteId;
  final int capacity;
  final Future<Uint8List> Function(int page)? pageLoader;
  final Map<int, Uint8List> _pages = {};
  final Map<int, Future<Uint8List>> _pending = {};
  bool _disposed = false;

  bool contains(int page) => _pages.containsKey(page);

  Future<Uint8List> load(int page) {
    if (_disposed) return Future.error(StateError('Preview closed.'));
    if (page < 1) return Future.error(const FormatException('Invalid page.'));
    final cached = _pages.remove(page);
    if (cached != null) {
      _pages[page] = cached;
      return Future.value(cached);
    }
    final existing = _pending[page];
    if (existing != null) return existing;
    final work = _fetch(page);
    _pending[page] = work;
    return work.whenComplete(() => _pending.remove(page));
  }

  /// Prefetch only the immediate neighbors; do not download the whole PDF.
  void prefetchAdjacent(int page, int pageCount) {
    if (_disposed) return;
    for (final next in [page + 1, page - 1]) {
      if (next < 1 || next > pageCount ||
          _pages.containsKey(next) || _pending.containsKey(next)) continue;
      unawaited(load(next).catchError((Object _) =>
          Uint8List(0)));
    }
  }

  Future<Uint8List> _fetch(int page) async {
    if (pageLoader != null) {
      final image = await pageLoader!(page);
      if (!_disposed) { _remember(page, image); }
      return image;
    }
    final response = await api.request('/api/mobile/v1/contributor-render',
      body: {'op': 'preview', 'id': noteId, 'page': page});
    final raw = response['url'];
    final uri = Uri.tryParse(raw is String ? raw : '');
    if (uri == null || uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      throw const FormatException('Invalid protected image URL.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final result = await request.close().timeout(const Duration(seconds: 20));
      if (result.statusCode != 200 || result.contentLength > 5 * 1024 * 1024) {
        throw const HttpException('Protected preview page unavailable.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in result.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > 5 * 1024 * 1024) {
          throw const FormatException('Preview page exceeds size limit.');
        }
      }
      final image = bytes.takeBytes();
      if (image.length < 16) throw const FormatException('Empty preview image.');
      if (!_disposed) { _remember(page, image); }
      return image;
    } finally {
      client.close(force: true);
    }
  }

  void _remember(int page, Uint8List image) {
    _pages.remove(page);
    _pages[page] = image;
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.first);
    }
  }

  void clear() {
    _pages.clear();
    // In-flight fetches may finish but _disposed prevents re-populating.
    _disposed = true;
  }
}
