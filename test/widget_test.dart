import 'dart:io';

import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/advanced_search_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/arxiv_update_schedule.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('Arxiv.queryUriFor builds an encoded HTTPS query', () {
    final uri = Arxiv.queryUriFor('machine learning', page: 30, pageSize: 10);

    expect(uri.scheme, 'https');
    expect(uri.host, 'export.arxiv.org');
    expect(uri.path, '/api/query');
    expect(uri.queryParameters['search_query'], 'all:machine learning');
    expect(uri.queryParameters['start'], '30');
    expect(uri.queryParameters['max_results'], '10');
  });

  test('Arxiv.queryUriFor passes arXiv field queries through', () {
    final categoryUri = Arxiv.queryUriFor('cat:cs.AI');
    final authorUri = Arxiv.queryUriFor('au:"Ada Lovelace"');

    expect(categoryUri.queryParameters['search_query'], 'cat:cs.AI');
    expect(authorUri.queryParameters['search_query'], 'au:"Ada Lovelace"');
  });

  test('Arxiv.queryUriFor includes sortBy and sortOrder parameters', () {
    final uri = Arxiv.queryUriFor(
      'cat:cs.LG',
      sortOption: ArxivSortOption.newest,
    );

    expect(uri.queryParameters['sortBy'], 'submittedDate');
    expect(uri.queryParameters['sortOrder'], 'descending');
  });

  test('Arxiv.extractArxivId and queryUriFor normalize arXiv IDs and URLs', () {
    expect(Arxiv.extractArxivId('2301.07041'), '2301.07041');
    expect(Arxiv.extractArxivId('arXiv:2301.07041v2'), '2301.07041v2');
    expect(
      Arxiv.extractArxivId('https://arxiv.org/abs/2301.07041'),
      '2301.07041',
    );
    expect(
      Arxiv.extractArxivId('https://arxiv.org/pdf/2301.07041v1.pdf'),
      '2301.07041v1',
    );
    expect(Arxiv.extractArxivId('hep-th/9901001'), 'hep-th/9901001');
    expect(Arxiv.extractArxivId('machine learning'), isNull);

    final idUri = Arxiv.queryUriFor('https://arxiv.org/abs/2301.07041');
    expect(idUri.queryParameters['id_list'], '2301.07041');
    expect(idUri.queryParameters.containsKey('search_query'), isFalse);
  });

  test('Paper.fromJson retains arXiv entry metadata', () {
    final paper = Paper.fromJson(
      {
        "id": "http://arxiv.org/abs/1234.56789v1",
        "title": "A retained metadata example",
        "summary": "A sample abstract.",
        "published": "2026-01-02T03:04:05Z",
        "updated": "2026-01-03T03:04:05Z",
        "author": {"name": "Ada Lovelace"},
      },
      rawEntry: {
        "id": {r"$": "http://arxiv.org/abs/1234.56789v1"},
        "title": {r"$": "A retained metadata example"},
        "updated": {r"$": "2026-01-03T03:04:05Z"},
        "link": [
          {
            "@href": "https://arxiv.org/abs/1234.56789v1",
            "@rel": "alternate",
            "@type": "text/html",
          },
          {
            "@href": "https://arxiv.org/pdf/1234.56789v1",
            "@rel": "related",
            "@type": "application/pdf",
            "@title": "pdf",
          },
        ],
        "summary": {r"$": "A sample abstract."},
        "category": {
          "@term": "cs.AI",
          "@scheme": "http://arxiv.org/schemas/atom",
        },
        "published": {r"$": "2026-01-02T03:04:05Z"},
        "arxiv:primary_category": {
          "@term": "cs.AI",
          "@scheme": "http://arxiv.org/schemas/atom",
        },
        "author": {
          "name": {r"$": "Ada Lovelace"},
        },
      },
    );

    expect(paper.id, "1234.56789v1");
    expect(paper.publishedAt, "2026-01-02");
    expect(paper.updatedAt, "2026-01-03T03:04:05Z");
    expect(paper.abstractUrl, "https://arxiv.org/abs/1234.56789v1");
    expect(paper.pdfUrl, "https://arxiv.org/pdf/1234.56789v1");
    expect(paper.categories, ["cs.AI"]);
    expect(paper.primaryCategory, "cs.AI");
    expect(paper.rawEntry["link"], isA<List>());
    expect(paper.retainedMetadata["rawEntry"], paper.rawEntry);
  });

  test('ArxivWebSearch.buildAdvancedSearchUri builds official web query', () {
    final query = ArxivAdvancedQuery(
      terms: const [
        ArxivSearchTermRow(
          term: 'attention is all you need',
          field: ArxivSearchField.title,
        ),
        ArxivSearchTermRow(
          operator: ArxivSearchOperator.and,
          term: 'Vaswani',
          field: ArxivSearchField.author,
        ),
        ArxivSearchTermRow(
          operator: ArxivSearchOperator.not,
          term: 'survey',
          field: ArxivSearchField.abstract,
        ),
      ],
      category: const ArxivCategory(
        code: 'cs.CL',
        label: 'Computation and Language',
        group: 'Computer Science',
      ),
      includeCrossList: false,
      dateFilterMode: ArxivDateFilterMode.dateRange,
      fromDate: DateTime(2024, 1, 15),
      toDate: DateTime(2024, 12, 31),
      pageSize: 50,
    );

    final uri = ArxivWebSearch.buildAdvancedSearchUri(query, start: 50);
    expect(uri.scheme, 'https');
    expect(uri.host, 'arxiv.org');
    expect(uri.path, '/search/advanced');
    expect(uri.queryParameters['terms-0-term'], 'attention is all you need');
    expect(uri.queryParameters['terms-0-field'], 'title');
    expect(uri.queryParameters['terms-1-operator'], 'AND');
    expect(uri.queryParameters['terms-1-term'], 'Vaswani');
    expect(uri.queryParameters['terms-1-field'], 'author');
    expect(uri.queryParameters['terms-2-operator'], 'NOT');
    expect(uri.queryParameters['terms-2-term'], 'survey');
    expect(uri.queryParameters['terms-2-field'], 'abstract');
    expect(uri.queryParameters['terms-3-operator'], 'AND');
    expect(uri.queryParameters['terms-3-term'], 'cs.CL');
    expect(uri.queryParameters['terms-3-field'], 'cross_list_category');
    expect(uri.queryParameters['classification-include_cross_list'], 'exclude');
    expect(uri.queryParameters['date-filter_by'], 'date_range');
    expect(uri.queryParameters['date-from_date'], '2024-01-15');
    expect(uri.queryParameters['date-to_date'], '2024-12-31');
    expect(uri.queryParameters['size'], '50');
    expect(uri.queryParameters['start'], '50');
  });

  test('ArxivWebSearch.parseSearchHtml parses results and filters cross-lists', () {
    const sampleHtml = '''
      <h1 class="title is-clearfix">Showing 1&ndash;2 of 2 results</h1>
      <ol class="breathe-horizontal">
        <li class="arxiv-result">
          <div class="is-marginless">
            <p class="list-title is-inline-block">
              <a href="https://arxiv.org/abs/2006.06236v2">arXiv:2006.06236v2</a>
            </p>
            <div class="tags is-inline-block">
              <span class="tag is-small is-link tooltip">cs.CV</span>
              <span class="tag is-small is-grey tooltip">cs.LG</span>
            </div>
          </div>
          <p class="title is-5 mathjax">Primary CV Paper</p>
          <p class="authors"><span class="has-text-black-bis has-text-weight-semibold">Authors:</span><a href="#">Alice</a>, <a href="#">Bob</a></p>
          <p class="abstract mathjax"><span class="abstract-full has-text-grey-dark mathjax">Full abstract text here.</span></p>
          <p class="is-size-7"><span class="has-text-black-bis has-text-weight-semibold">Submitted</span> 10 June, 2020;</p>
        </li>
        <li class="arxiv-result">
          <div class="is-marginless">
            <p class="list-title is-inline-block">
              <a href="https://arxiv.org/abs/2401.00001">arXiv:2401.00001</a>
            </p>
            <div class="tags is-inline-block">
              <span class="tag is-small is-link tooltip">cs.LG</span>
              <span class="tag is-small is-grey tooltip">cs.CV</span>
            </div>
          </div>
          <p class="title is-5 mathjax">Cross-Listed Paper</p>
          <p class="authors"><span class="has-text-black-bis has-text-weight-semibold">Authors:</span><a href="#">Carol</a></p>
          <p class="abstract mathjax"><span class="abstract-full has-text-grey-dark mathjax">Another abstract.</span></p>
          <p class="is-size-7"><span class="has-text-black-bis has-text-weight-semibold">Submitted</span> 1 January, 2024;</p>
        </li>
      </ol>
    ''';

    final allResults = ArxivWebSearch.parseSearchHtml(sampleHtml);
    expect(allResults.totalResults, 2);
    expect(allResults.papers.length, 2);
    expect(allResults.papers.first.id, '2006.06236v2');
    expect(allResults.papers.first.primaryCategory, 'cs.CV');

    final primaryOnly = ArxivWebSearch.parseSearchHtml(
      sampleHtml,
      filterPrimaryCategory: 'cs.CV',
    );
    expect(primaryOnly.papers.length, 1);
    expect(primaryOnly.papers.first.id, '2006.06236v2');
  });

  test('CollectionStore creates, assigns, filters, renames, and deletes folders', () async {
    final tempDir = await Directory.systemTemp.createTemp('collection_store_test');
    Hive.init(tempDir.path);
    try {
      final store = CollectionStore();

      final folder = await store.createFolder('Diffusion');
      expect((await store.loadFolders()).length, 1);

      await store.togglePaperInFolder('2006.06236v2', folder.id);
      final map = await store.loadPaperFolderMap();
      expect(map['2006.06236v2'], [folder.id]);

      final p1 = Paper('2006.06236v2', 'P1', 'Abs', '2020-06-10', 'Alice');
      final p2 = Paper('2401.00001', 'P2', 'Abs', '2024-01-01', 'Bob');
      expect(
        CollectionStore.filterPapers(
          papers: [p1, p2],
          paperFolderMap: map,
          selectedFolderId: folder.id,
        ).map((p) => p.id),
        ['2006.06236v2'],
      );
      expect(
        CollectionStore.filterPapers(
          papers: [p1, p2],
          paperFolderMap: map,
          unsortedOnly: true,
        ).map((p) => p.id),
        ['2401.00001'],
      );

      await store.renameFolder(folder.id, 'Generative Models');
      expect((await store.loadFolders()).first.name, 'Generative Models');

      await store.deleteFolder(folder.id);
      expect(await store.loadFolders(), isEmpty);
      expect(await store.loadPaperFolderMap(), isEmpty);
    } finally {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('MainPageStyleStore.formatAuthors truncates long author lists when enabled', () {
    final paper = Paper(
      '2401.00001',
      'Test Paper',
      'Abstract',
      '2024-01-01',
      'Alice Smith, Bob Jones, Carol Lee, Dave Kim, Eve Chen',
    );

    expect(
      MainPageStyleStore.formatAuthors(
        paper,
        const MainPageStyleSettings(limitAuthors: true, maxAuthors: 3),
      ),
      'Alice Smith, Bob Jones, Carol Lee (+2 more)',
    );

    expect(
      MainPageStyleStore.formatAuthors(
        paper,
        const MainPageStyleSettings(limitAuthors: false, maxAuthors: 3),
      ),
      'Alice Smith, Bob Jones, Carol Lee, Dave Kim, Eve Chen',
    );
  });

  test('Paper.fromJson preserves LaTeX commands and converts inline dollar math', () {
    final paper = Paper.fromJson({
      "id": "http://arxiv.org/abs/2611.17299v1",
      "title": r"Lyman-$\alpha$ Forest",
      "summary":
          r"Spanning $2 \leq z \leq 4$ to $\sim 5\%$ down to $k \simeq 1$-$1.5\,h\,{\rm Mpc}^{-1}$.",
      "published": "2026-11-12T18:55:10Z",
      "author": {"name": "Divij Sharma"},
    });

    expect(paper.title, r"Lyman-\(\alpha\) Forest");
    expect(Paper.formatTitleForDisplay(paper.title), "Lyman-α Forest");
    expect(
      Paper.formatTitleForDisplay(r"Galaxy Redshift Distribution for 3\(\times\)2pt Cosmology"),
      "Galaxy Redshift Distribution for 3×2pt Cosmology",
    );
    expect(
      paper.summary,
      r"Spanning \(2 \leq z \leq 4\) to \(\sim 5\%\) down to \(k \simeq 1\)-\(1.5\,h\,{\rm Mpc}^{-1}\).",
    );
  });

  test('ArxivUpdateSchedule detects weekday 20:00 ET announcement windows', () {
    // 2026-11-12 is Thursday (EST, UTC-5 -> 20:00 EST = 01:00 UTC next day).
    final beforeThuAnnouncement = DateTime.utc(2026, 11, 12, 23, 0);
    final afterWedAnnouncement = DateTime.utc(2026, 11, 12, 2, 0);
    final afterThuAnnouncement = DateTime.utc(2026, 11, 13, 1, 5);
    final saturdayUtc = DateTime.utc(2026, 11, 14, 12, 0);
    final afterSunAnnouncement = DateTime.utc(2026, 11, 16, 1, 5);

    expect(
      ArxivUpdateSchedule.hasNewAnnouncementSince(
        afterWedAnnouncement,
        nowUtc: beforeThuAnnouncement,
      ),
      isFalse,
    );
    expect(
      ArxivUpdateSchedule.hasNewAnnouncementSince(
        beforeThuAnnouncement,
        nowUtc: afterThuAnnouncement,
      ),
      isTrue,
    );
    expect(
      ArxivUpdateSchedule.hasNewAnnouncementSince(
        afterThuAnnouncement,
        nowUtc: saturdayUtc,
      ),
      isFalse,
    );
    expect(
      ArxivUpdateSchedule.hasNewAnnouncementSince(
        saturdayUtc,
        nowUtc: afterSunAnnouncement,
      ),
      isTrue,
    );
    expect(
      ArxivUpdateSchedule.noAnnouncementReason(saturdayUtc),
      contains("weekend"),
    );
    expect(
      ArxivUpdateSchedule.noAnnouncementReason(DateTime.utc(2026, 11, 26, 16, 0)),
      contains("Thanksgiving break"),
    );
    expect(
      ArxivUpdateSchedule.noAnnouncementReason(afterThuAnnouncement),
      isNull,
    );
  });
}
