import 'dart:io';

import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/feed_cache_store.dart';
import 'package:arxiv/services/read_papers_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDirectory;

  setUpAll(() {
    tempDirectory = Directory.systemTemp.createTempSync(
      'read_and_feed_cache_test_',
    );
    Hive.init(tempDirectory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PaperAdapter());
    }
  });

  tearDown(() async {
    for (final boxName in [ReadPapersStore.boxName, FeedCacheStore.boxName]) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } catch (_) {}
    }
  });

  tearDownAll(() async {
    await Hive.close();
    tempDirectory.deleteSync(recursive: true);
  });

  test('ReadPapersStore tracks read state across paper revisions', () async {
    final store = ReadPapersStore();
    await store.ensureLoaded();

    expect(store.isRead('2611.18337v1'), isFalse);

    await store.markRead('2611.18337v1');
    expect(store.isRead('2611.18337v1'), isTrue);
    expect(store.isRead('2611.18337v2'), isTrue);
    expect(store.isRead('2611.18337'), isTrue);

    final toggled = await store.toggleRead('2611.18337v2');
    expect(toggled, isFalse);
    expect(store.isRead('2611.18337v1'), isFalse);

    final samplePaper = Paper(
      '2611.99999v1',
      'Stored Read History Paper',
      'Abstract',
      '2026-11-16',
      'Jane Doe',
    );
    await store.markRead(samplePaper.id, paper: samplePaper);
    final history = await store.loadReadHistory();
    expect(history.length, 1);
    expect(history.first.id, '2611.99999');
    expect(history.first.paper?.title, 'Stored Read History Paper');
  });

  test('FeedCacheStore merges fresh pages and prunes entries older than 7 days',
      () async {
    final store = FeedCacheStore();
    final key = FeedCacheStore.buildKey(
      categoryCode: 'astro-ph.CO',
      sortOption: ArxivSortOption.newest,
      excludeCrossListed: false,
    );
    final nowUtc = DateTime.utc(2026, 11, 16, 12);

    final oldPaper = Paper(
      '2611.00001v1',
      'Old paper',
      'Old summary',
      '2026-11-01',
      'Author Old',
    );
    final recentPaper = Paper(
      '2611.18000v1',
      'Recent paper',
      'Recent summary',
      '2026-11-13',
      'Author Recent',
    );
    final freshPaper = Paper(
      '2611.19000v1',
      'Fresh paper',
      'Fresh summary',
      '2026-11-16',
      'Author Fresh',
    );

    await store.save(
      key,
      papers: [recentPaper, oldPaper],
      totalResults: 100,
      cachedAtUtc: nowUtc.subtract(const Duration(days: 1)),
    );

    final merged = await store.mergeFreshPage(
      key,
      freshPapers: [freshPaper, recentPaper],
      totalResults: 105,
      fetchedAtUtc: nowUtc,
    );

    expect(merged.papers.map((p) => p.id).toList(), [
      '2611.19000v1',
      '2611.18000v1',
    ]);
    expect(merged.totalResults, 105);

    final loaded = await store.load(key, nowUtc: nowUtc);
    expect(loaded, isNotNull);
    expect(loaded!.papers.length, 2);
  });
}
