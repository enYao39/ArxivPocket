import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/models/paper.dart';

enum ArxivSearchOperator {
  and(value: "AND", label: "AND"),
  or(value: "OR", label: "OR"),
  not(value: "NOT", label: "NOT");

  const ArxivSearchOperator({required this.value, required this.label});

  final String value;
  final String label;
}

enum ArxivSearchField {
  all(value: "all", label: "All fields"),
  title(value: "title", label: "Title"),
  author(value: "author", label: "Author(s)"),
  abstract(value: "abstract", label: "Abstract"),
  comments(value: "comments", label: "Comments"),
  journalRef(value: "journal_ref", label: "Journal reference"),
  paperId(value: "paper_id", label: "arXiv identifier"),
  doi(value: "doi", label: "DOI"),
  orcid(value: "orcid", label: "ORCID"),
  authorId(value: "author_id", label: "arXiv author ID"),
  reportNum(value: "report_num", label: "Report number"),
  acmClass(value: "acm_class", label: "ACM classification"),
  mscClass(value: "msc_class", label: "MSC classification"),
  crossListCategory(value: "cross_list_category", label: "Cross-list category");

  const ArxivSearchField({required this.value, required this.label});

  final String value;
  final String label;
}

enum ArxivDateFilterMode {
  allDates(value: "all_dates", label: "All dates"),
  past12Months(value: "past_12", label: "Past 12 months"),
  specificYear(value: "specific_year", label: "Specific year"),
  dateRange(value: "date_range", label: "Date range");

  const ArxivDateFilterMode({required this.value, required this.label});

  final String value;
  final String label;
}

class ArxivSearchTermRow {
  const ArxivSearchTermRow({
    this.operator = ArxivSearchOperator.and,
    this.term = "",
    this.field = ArxivSearchField.all,
  });

  final ArxivSearchOperator operator;
  final String term;
  final ArxivSearchField field;

  ArxivSearchTermRow copyWith({
    ArxivSearchOperator? operator,
    String? term,
    ArxivSearchField? field,
  }) {
    return ArxivSearchTermRow(
      operator: operator ?? this.operator,
      term: term ?? this.term,
      field: field ?? this.field,
    );
  }
}

class ArxivAdvancedQuery {
  const ArxivAdvancedQuery({
    this.terms = const [ArxivSearchTermRow()],
    this.category,
    this.includeCrossList = true,
    this.dateFilterMode = ArxivDateFilterMode.allDates,
    this.specificYear,
    this.fromDate,
    this.toDate,
    this.sortOption = ArxivSortOption.newest,
    this.pageSize = 25,
  });

  final List<ArxivSearchTermRow> terms;
  final ArxivCategory? category;
  final bool includeCrossList;
  final ArxivDateFilterMode dateFilterMode;
  final int? specificYear;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ArxivSortOption sortOption;
  final int pageSize;

  List<ArxivSearchTermRow> get activeTerms =>
      terms.where((t) => t.term.trim().isNotEmpty).toList();

  bool get hasAnyCriteria =>
      activeTerms.isNotEmpty ||
      category != null ||
      dateFilterMode != ArxivDateFilterMode.allDates;

  String summaryLabel() {
    final active = activeTerms;
    if (active.isEmpty) {
      return category != null ? "" : "Advanced filter";
    }
    return active
        .asMap()
        .entries
        .map((entry) {
          final prefix = entry.key == 0 ? "" : "${entry.value.operator.label} ";
          final fieldPrefix = entry.value.field == ArxivSearchField.all
              ? ""
              : "${entry.value.field.label}: ";
          return "$prefix$fieldPrefix${entry.value.term.trim()}";
        })
        .join(" ");
  }
}

class ArxivWebSearch {
  const ArxivWebSearch._();

  static const String host = "arxiv.org";

  static int normalizeWebPageSize(int requested) {
    if (requested <= 25) return 25;
    if (requested <= 50) return 50;
    if (requested <= 100) return 100;
    return 200;
  }

  static String orderParamFor(ArxivSortOption sortOption) {
    return switch (sortOption) {
      ArxivSortOption.relevance => "",
      ArxivSortOption.newest => "-announced_date_first",
      ArxivSortOption.oldest => "announced_date_first",
      ArxivSortOption.recentlyUpdated => "-submitted_date",
    };
  }

  static Uri buildSimpleSearchUri(
    String query, {
    int start = 0,
    int pageSize = 25,
    ArxivSortOption sortOption = ArxivSortOption.newest,
  }) {
    return Uri.https(host, "/search/", {
      "query": query.trim(),
      "searchtype": "all",
      "abstracts": "show",
      "order": orderParamFor(sortOption),
      "size": normalizeWebPageSize(pageSize).toString(),
      "start": start.toString(),
    });
  }

  static Uri buildAdvancedSearchUri(
    ArxivAdvancedQuery query, {
    int start = 0,
  }) {
    final params = <String, String>{"advanced": ""};

    final effectiveTerms = <ArxivSearchTermRow>[...query.activeTerms];
    if (query.category != null) {
      effectiveTerms.add(
        ArxivSearchTermRow(
          operator: ArxivSearchOperator.and,
          term: query.category!.code,
          field: ArxivSearchField.crossListCategory,
        ),
      );
    }
    if (effectiveTerms.isEmpty) {
      effectiveTerms.add(const ArxivSearchTermRow(term: ""));
    }

    for (var i = 0; i < effectiveTerms.length; i++) {
      final row = effectiveTerms[i];
      params["terms-$i-operator"] = row.operator.value;
      params["terms-$i-term"] = row.term.trim();
      params["terms-$i-field"] = row.field.value;
    }

    params["classification-physics_archives"] = "all";
    params["classification-include_cross_list"] = query.includeCrossList
        ? "include"
        : "exclude";

    params["date-filter_by"] = query.dateFilterMode.value;
    if (query.dateFilterMode == ArxivDateFilterMode.specificYear &&
        query.specificYear != null) {
      params["date-year"] = query.specificYear.toString();
    } else if (query.dateFilterMode == ArxivDateFilterMode.dateRange) {
      if (query.fromDate != null) {
        params["date-from_date"] = _formatIsoDate(query.fromDate!);
      }
      if (query.toDate != null) {
        params["date-to_date"] = _formatIsoDate(query.toDate!);
      }
      params["date-date_type"] = "submitted_date";
    }

    params["abstracts"] = "show";
    params["size"] = normalizeWebPageSize(query.pageSize).toString();
    params["order"] = orderParamFor(query.sortOption);
    params["start"] = start.toString();

    return Uri.https(host, "/search/advanced", params);
  }

  static ArxivSearchResult parseSearchHtml(
    String html, {
    int start = 0,
    int pageSize = 25,
    String? filterPrimaryCategory,
    String? topic,
    int? statusCode,
  }) {
    final totalResults = _parseTotalResults(html);
    final blocks = html.split('<li class="arxiv-result">');
    final papers = <Paper>[];

    for (var i = 1; i < blocks.length; i++) {
      final endIndex = blocks[i].indexOf('</li>');
      final block = endIndex >= 0 ? blocks[i].substring(0, endIndex) : blocks[i];
      final paper = _parseResultBlock(block);
      if (paper == null) continue;

      if (filterPrimaryCategory != null &&
          filterPrimaryCategory.trim().isNotEmpty &&
          paper.primaryCategory.toLowerCase() !=
              filterPrimaryCategory.trim().toLowerCase()) {
        continue;
      }
      papers.add(paper);
    }

    return ArxivSearchResult(
      papers: papers,
      feed: {
        "opensearch:totalResults": totalResults.toString(),
        "opensearch:startIndex": start.toString(),
        "opensearch:itemsPerPage": pageSize.toString(),
      },
      rawResponse: const {},
      rawXml: "",
      statusCode: statusCode,
      topic: topic,
    );
  }

  static int _parseTotalResults(String html) {
    final rangeMatch = RegExp(
      r'Showing\s+[\d,]+\s*(?:&ndash;|–|-)\s*[\d,]+\s+of\s+([\d,]+)\s+results',
      caseSensitive: false,
    ).firstMatch(html);
    if (rangeMatch != null) {
      return int.tryParse(rangeMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
    final singleMatch = RegExp(
      r'Showing\s+([\d,]+)\s+results?',
      caseSensitive: false,
    ).firstMatch(html);
    if (singleMatch != null) {
      return int.tryParse(singleMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
    return 0;
  }

  static Paper? _parseResultBlock(String block) {
    final absMatch = RegExp(
      r'href="(https?://arxiv\.org/abs/([^"]+))"',
    ).firstMatch(block);
    if (absMatch == null) return null;

    final abstractUrl = absMatch.group(1)!;
    final baseId = absMatch.group(2)!;
    final versionedMatch = RegExp(
      r'id="([^"]+)-abstract-full"',
    ).firstMatch(block);
    final id = versionedMatch?.group(1) ?? baseId;
    final pdfUrl = "https://arxiv.org/pdf/$id";

    final categories = <String>[];
    final tagsSection = RegExp(
      r'<div class="tags[^"]*">([\s\S]*?)</div>',
    ).firstMatch(block);
    if (tagsSection != null) {
      for (final tagMatch in RegExp(
        r'<span class="tag[^"]*"[^>]*>([\s\S]*?)</span>',
      ).allMatches(tagsSection.group(1)!)) {
        final code = _cleanHtmlText(tagMatch.group(1)!);
        if (code.isNotEmpty) {
          categories.add(code);
        }
      }
    }
    final primaryCategory = categories.isNotEmpty ? categories.first : "";

    final titleMatch = RegExp(
      r'<p class="title[^"]*">([\s\S]*?)</p>',
    ).firstMatch(block);
    final rawTitle = titleMatch != null ? _cleanHtmlText(titleMatch.group(1)!) : "";
    final title = Paper.parseLatex(rawTitle);

    final authorNames = <String>[];
    final authorsSection = RegExp(
      r'<p class="authors">([\s\S]*?)</p>',
    ).firstMatch(block);
    if (authorsSection != null) {
      for (final authorMatch in RegExp(
        r'<a [^>]*>([\s\S]*?)</a>',
      ).allMatches(authorsSection.group(1)!)) {
        final name = _cleanHtmlText(authorMatch.group(1)!);
        if (name.isNotEmpty) {
          authorNames.add(name);
        }
      }
    }

    var rawSummary =
        _extractBalancedSpanByClass(block, "abstract-full") ?? "";
    if (rawSummary.isEmpty) {
      final absParaMatch = RegExp(
        r'<p class="abstract[^"]*">([\s\S]*?)</p>',
      ).firstMatch(block);
      rawSummary = absParaMatch?.group(1) ?? "";
    }
    rawSummary = rawSummary.replaceAll(
      RegExp(r'<a\b[^>]*>[\s\S]*?</a>', caseSensitive: false),
      '',
    );
    final summary = Paper.parseLatex(_cleanHtmlText(rawSummary));

    var publishedAt = "";
    final submittedMatch = RegExp(
      r'Submitted</span>\s*(\d{1,2})\s+([A-Za-z]+),\s*(\d{4})',
    ).firstMatch(block);
    if (submittedMatch != null) {
      final day = submittedMatch.group(1)!.padLeft(2, '0');
      final month = _monthNumber(submittedMatch.group(2)!);
      final year = submittedMatch.group(3)!;
      if (month != null) {
        publishedAt = "$year-$month-$day";
      }
    }

    return Paper(
      id,
      title,
      summary,
      publishedAt,
      authorNames.join(", "),
      abstractUrl: abstractUrl,
      pdfUrl: pdfUrl,
      categories: categories,
      primaryCategory: primaryCategory,
      rawEntry: {
        "author": authorNames
            .map((name) => {"name": {r"$": name}})
            .toList(),
      },
    );
  }

  static String? _extractBalancedSpanByClass(String html, String classPrefix) {
    final openMatch = RegExp(
      '<span class="$classPrefix[^"]*"[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (openMatch == null) return null;

    final start = openMatch.end;
    var depth = 1;
    final tagRegex = RegExp(r'<span\b[^>]*>|</span>', caseSensitive: false);
    for (final match in tagRegex.allMatches(html, start)) {
      final tag = match.group(0)!.toLowerCase();
      if (tag.startsWith('</span')) {
        depth--;
        if (depth == 0) {
          return html.substring(start, match.start);
        }
      } else {
        depth++;
      }
    }
    return html.substring(start);
  }

  static String _cleanHtmlText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '...')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _monthNumber(String name) {
    const months = {
      "january": "01",
      "february": "02",
      "march": "03",
      "april": "04",
      "may": "05",
      "june": "06",
      "july": "07",
      "august": "08",
      "september": "09",
      "october": "10",
      "november": "11",
      "december": "12",
    };
    return months[name.toLowerCase()];
  }

  static String _formatIsoDate(DateTime date) {
    final m = date.month.toString().padLeft(2, "0");
    final d = date.day.toString().padLeft(2, "0");
    return "${date.year}-$m-$d";
  }
}
