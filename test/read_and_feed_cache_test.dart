import 'dart:io';

import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/arxiv_update_schedule.dart';
import 'package:arxiv/services/arxiv_web_search.dart';
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

  test('ArxivAdvancedQuery encodes multi-category OR terms and sorted cache keys',
      () {
    final uri = ArxivWebSearch.buildAdvancedSearchUri(
      const ArxivAdvancedQuery(
        categories: [
          ArxivCategory(
            code: 'astro-ph.CO',
            label: 'Cosmology',
            group: 'Astrophysics',
          ),
          ArxivCategory(
            code: 'astro-ph.HE',
            label: 'High Energy',
            group: 'Astrophysics',
          ),
        ],
      ),
    );
    expect(uri.queryParameters['terms-0-term'], 'astro-ph.CO');
    expect(uri.queryParameters['terms-0-operator'], 'AND');
    expect(uri.queryParameters['terms-1-term'], 'astro-ph.HE');
    expect(uri.queryParameters['terms-1-operator'], 'OR');

    final key1 = FeedCacheStore.buildKey(
      categoryCodes: ['astro-ph.HE', 'astro-ph.CO'],
      sortOption: ArxivSortOption.newest,
      excludeCrossListed: false,
    );
    final key2 = FeedCacheStore.buildKey(
      categoryCodes: ['astro-ph.CO', 'astro-ph.HE'],
      sortOption: ArxivSortOption.newest,
      excludeCrossListed: false,
    );
    expect(key1, key2);
  });

  test('FeedCacheStore.loadForCategories merges cached single-category feeds',
      () async {
    final store = FeedCacheStore();
    final nowUtc = DateTime.utc(2026, 11, 17, 12);

    final coPaper = Paper(
      '2611.10001v1',
      'Cosmology Paper',
      'Summary',
      '2026-11-16',
      'Author A',
    );
    final hePaper = Paper(
      '2611.10002v1',
      'High Energy Paper',
      'Summary',
      '2026-11-17',
      'Author B',
    );

    await store.save(
      FeedCacheStore.buildKey(
        categoryCode: 'astro-ph.CO',
        sortOption: ArxivSortOption.newest,
        excludeCrossListed: false,
      ),
      papers: [coPaper],
      totalResults: 10,
      cachedAtUtc: nowUtc,
    );
    await store.save(
      FeedCacheStore.buildKey(
        categoryCode: 'astro-ph.HE',
        sortOption: ArxivSortOption.newest,
        excludeCrossListed: false,
      ),
      papers: [hePaper],
      totalResults: 15,
      cachedAtUtc: nowUtc,
    );

    final merged = await store.loadForCategories(
      categoryCodes: ['astro-ph.CO', 'astro-ph.HE'],
      sortOption: ArxivSortOption.newest,
      excludeCrossListed: false,
      nowUtc: nowUtc,
    );
    expect(merged, isNotNull);
    expect(merged!.papers.map((p) => p.id).toList(), [
      '2611.10002v1',
      '2611.10001v1',
    ]);
  });

  test('Arxiv.extractArxivId handles www.arxiv.org and query/fragment URLs', () {
    expect(
      Arxiv.extractArxivId('https://www.arxiv.org/abs/2611.18337v1?context=astro-ph'),
      '2611.18337v1',
    );
    expect(
      Arxiv.extractArxivId('https://arxiv.org/abs/2611.18337#abstract'),
      '2611.18337',
    );
    expect(
      Arxiv.extractArxivId('https://arxiv.org/pdf/2611.18337.pdf?download=1'),
      '2611.18337',
    );
  });

  test('parseNewListIdsHtml excludes replacements and respects includeCrossLists',
      () {
    const html = '''
      <h3>New submissions</h3>
      <a href="/abs/2611.18337">arXiv:2611.18337</a>
      <h3>Cross submissions</h3>
      <a href="/abs/2611.18338">arXiv:2611.18338</a>
      <h3>Replacement submissions</h3>
      <a href="/abs/2401.00001">arXiv:2401.00001</a>
    ''';
    expect(
      ArxivWebSearch.parseNewListIdsHtml(html, includeCrossLists: true),
      {'2611.18337', '2611.18338'},
    );
    expect(
      ArxivWebSearch.parseNewListIdsHtml(html, includeCrossLists: false),
      {'2611.18337'},
    );
  });

  test('ArxivUpdateSchedule.isSubmittedInLatestWindow spans multi-day window',
      () {
    // Thursday 2026-11-19 21:00 ET -> Friday 2026-11-20 02:00 UTC
    final nowUtc = DateTime.utc(2026, 11, 20, 2, 0);
    expect(
      ArxivUpdateSchedule.isSubmittedInLatestWindow('2026-11-19', nowUtc: nowUtc),
      isTrue,
    );
    expect(
      ArxivUpdateSchedule.isSubmittedInLatestWindow('2026-11-18', nowUtc: nowUtc),
      isTrue,
    );
    expect(
      ArxivUpdateSchedule.isSubmittedInLatestWindow('2026-11-16', nowUtc: nowUtc),
      isFalse,
    );
  });

  test('parseNewListPapersHtml extracts papers and mailing date', () {
    const html = '''
      <p>Showing new listings for Friday, 20 November 2026</p>
      <dl id='articles'>
      <h3>New submissions</h3>
      <dt><a href="/abs/2611.25036" id="2611.25036">arXiv:2611.25036</a></dt>
      <dd>
        <div class='meta'>
          <div class='list-title mathjax'><span class='descriptor'>Title:</span> Test Title</div>
          <div class='list-authors'><a href="/a">Alice</a>, <a href="/b">Bob</a></div>
          <div class='list-subjects'><span class='descriptor'>Subjects:</span> <span class="primary-subject">Cosmology (astro-ph.CO)</span>; High Energy (hep-ph)</div>
          <p class='mathjax'>Sample abstract text.</p>
        </div>
      </dd>
      <h3>Replacement submissions</h3>
      <dt><a href="/abs/2401.00001" id="2401.00001">arXiv:2401.00001</a></dt>
      <dd><div class='meta'><div class='list-title mathjax'>Old</div></div></dd>
      </dl>
    ''';
    final parsed = ArxivWebSearch.parseNewListPapersHtml(html);
    expect(parsed.announcementDate, '2026-11-20');
    expect(parsed.papers.length, 1);
    expect(parsed.papers.first.id, '2611.25036');
    expect(parsed.papers.first.title, 'Test Title');
    expect(parsed.papers.first.authors, 'Alice, Bob');
    expect(parsed.papers.first.primaryCategory, 'astro-ph.CO');
    expect(parsed.papers.first.categories, ['astro-ph.CO', 'hep-ph']);
    expect(parsed.papers.first.summary, 'Sample abstract text.');
  });
}
