import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_api.dart';
import 'package:smiunotes_contributers_app/contributor_preview_cache.dart';

void main() {
  test('adjacent pages are prefetched and revisited without another fetch',
      () async {
    final calls = <int>[];
    final cache = ContributorPreviewCache(ContributorApi(), 'draft',
      pageLoader: (page) async {
        calls.add(page);
        return Uint8List.fromList(List<int>.filled(25, page));
      });
    final current = await cache.load(2);
    expect(current[0], 2);
    cache.prefetchAdjacent(2, 4);
    // Allow pending prefetch requests to settle.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(cache.contains(1), isTrue);
    expect(cache.contains(3), isTrue);
    await cache.load(3);
    await cache.load(2);
    expect(calls.where((number) => number == 2).length, 1);
    expect(calls.where((number) => number == 3).length, 1);
    cache.clear();
  });

  test('in-flight page requests are deduplicated', () async {
    final response = Completer<Uint8List>();
    var calls = 0;
    final cache = ContributorPreviewCache(ContributorApi(), 'draft',
      pageLoader: (page) {
        calls++;
        return response.future;
      });
    final first = cache.load(1);
    final second = cache.load(1);
    expect(calls, 1);
    response.complete(Uint8List(32));
    await Future.wait([first, second]);
    expect(cache.contains(1), isTrue);
    cache.clear();
  });

  test('bounded cache evicts oldest page and clears on close', () async {
    final cache = ContributorPreviewCache(ContributorApi(), 'draft',
      capacity: 2,
      pageLoader: (page) async => Uint8List.fromList(List<int>.filled(32, page)));
    await cache.load(1);
    await cache.load(2);
    await cache.load(3);
    expect(cache.contains(1), isFalse);
    expect(cache.contains(2), isTrue);
    expect(cache.contains(3), isTrue);
    cache.clear();
    expect(cache.contains(2), isFalse);
  });
}
