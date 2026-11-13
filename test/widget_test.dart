import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/advanced_search_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/arxiv_update_schedule.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('ArxivAdvancedQuery.buildSearchQuery builds compound arXiv query', () {
    final query = ArxivAdvancedQuery(
      title: 'attention is all you need',
      author: 'Vaswani',
      comments: 'NeurIPS 2017',
      category: const ArxivCategory(
        code: 'cs.CL',
        label: 'Computation and Language',
        group: 'Computer Science',
      ),
      fromDate: DateTime(2024, 1, 15),
      toDate: DateTime(2024, 12, 31),
    );

    expect(
      query.buildSearchQuery(),
      'ti:"attention is all you need" AND au:Vaswani AND co:"NeurIPS 2017" AND cat:cs.CL AND submittedDate:[202401150000 TO 202412312359]',
    );
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
