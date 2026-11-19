import 'dart:convert';
import 'dart:math';

import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/arxiv_web_search.dart';
import 'package:dio/dio.dart';
import 'package:xml2json/xml2json.dart';

enum ArxivSortOption {
  relevance(sortBy: "relevance", sortOrder: "descending", label: "Relevance"),
  newest(sortBy: "submittedDate", sortOrder: "descending", label: "Newest"),
  oldest(sortBy: "submittedDate", sortOrder: "ascending", label: "Oldest"),
  recentlyUpdated(
    sortBy: "lastUpdatedDate",
    sortOrder: "descending",
    label: "Recently Updated",
  );

  const ArxivSortOption({
    required this.sortBy,
    required this.sortOrder,
    required this.label,
  });

  final String sortBy;
  final String sortOrder;
  final String label;
}

class ArxivSearchResult {
  const ArxivSearchResult({
    required this.papers,
    required this.feed,
    required this.rawResponse,
    required this.rawXml,
    this.errorMessage,
    this.statusCode,
    this.topic,
  });

  final List<Paper> papers;
  final Map<String, dynamic> feed;
  final Map<String, dynamic> rawResponse;
  final String rawXml;
  final String? errorMessage;
  final int? statusCode;
  final String? topic;

  bool get hasError => errorMessage?.isNotEmpty == true;

  int get totalResults => _readInt(feed["opensearch:totalResults"]);
  int get startIndex => _readInt(feed["opensearch:startIndex"]);
  int get itemsPerPage => _readInt(feed["opensearch:itemsPerPage"]);

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }
}

class Arxiv {
  static const _host = "export.arxiv.org";
  static const _path = "/api/query";
  static const _minimumRequestInterval = Duration(seconds: 3);
  static const _minimumWebRequestInterval = Duration(milliseconds: 800);

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: const {
        "User-Agent":
            "ArxivPocket/3.0.5 (Android; +https://github.com/enYao39/ArxivPocket)",
      },
    ),
  );
  static Future<void> _requestQueue = Future.value();
  static DateTime? _lastRequestStartedAt;

  static const _topics = [
    "acid",
    "a theory of justice",
    "attention is all you need",
    "augmented",
    "behavioral",
    "books",
    "black hole",
    "brain",
    "cats",
    "computer",
    "creative",
    "dog",
    "dna sequencing",
    "dyson sphere",
    "ecg",
    "emotional",
    "entanglement",
    "fear",
    "fuzzy sets",
    "fidgeting",
    "glucose",
    "garbage",
    "gonad",
    "hands",
    "heart",
    "higgs boson",
    "hydron",
    "identity",
    "industrial",
    "isolation",
    "laptop",
    "love",
    "laboratory",
    "machine learning",
    "mathematical theory of communication",
    "mental state",
    "micro",
    "microchip",
    "mobile",
    "molecular cloning",
    "neural network",
    "negative",
    "numbers",
    "pc",
    "planet",
    "protein measurement",
    "psychology",
    "quantum",
    "quasar",
    "qubit",
    "reading",
    "relationship",
    "relativity",
    "robotics",
    "rocket",
    "sitting",
    "spider",
    "spiritual",
    "sulphur",
    "television",
    "tiered reward",
    "transport",
    "virtual reality",
    "volcano",
    "vision",
  ];

  /// Fetches papers for the requested [term].
  /// [page] and [pageSize] are optional. If missing, 0 and 30 are used as defaults respectively.
  static Future<ArxivSearchResult> searchWithMetadata(
    String term, {
    int page = 0,
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
    String? filterPrimaryCategory,
    bool useWebSearch = true,
  }) async {
    if (useWebSearch && extractArxivId(term) == null) {
      return searchWeb(
        term,
        page: page,
        pageSize: pageSize,
        sortOption: sortOption,
        filterPrimaryCategory: filterPrimaryCategory,
      );
    }
    return _runRateLimitedRequest(
      () => _searchWithMetadata(
        term,
        page: page,
        pageSize: pageSize,
        sortOption: sortOption,
      ),
    );
  }

  /// Searches arXiv using the official `arxiv.org/search/` web interface
  /// (backed by `arXiv/arxiv-search`).
  static Future<ArxivSearchResult> searchWeb(
    String query, {
    int page = 0,
    int pageSize = 25,
    ArxivSortOption sortOption = ArxivSortOption.newest,
    String? filterPrimaryCategory,
    String? topic,
  }) async {
    return _runRateLimitedRequest(
      () => _searchWebUri(
        ArxivWebSearch.buildSimpleSearchUri(
          query,
          start: page,
          pageSize: pageSize,
          sortOption: sortOption,
        ),
        start: page,
        pageSize: pageSize,
        filterPrimaryCategory: filterPrimaryCategory,
        topic: topic,
      ),
      minInterval: _minimumWebRequestInterval,
    );
  }

  /// Searches arXiv using the official `arxiv.org/search/advanced` endpoint.
  static Future<ArxivSearchResult> advancedSearchWithMetadata(
    ArxivAdvancedQuery query, {
    int page = 0,
    String? filterPrimaryCategory,
    String? topic,
  }) async {
    return _runRateLimitedRequest(
      () => _searchWebUri(
        ArxivWebSearch.buildAdvancedSearchUri(query, start: page),
        start: page,
        pageSize: query.pageSize,
        filterPrimaryCategory:
            filterPrimaryCategory ??
            (query.includeCrossList ? null : query.category?.code),
        topic: topic,
      ),
      minInterval: _minimumWebRequestInterval,
    );
  }

  static Future<ArxivSearchResult> _searchWebUri(
    Uri uri, {
    required int start,
    required int pageSize,
    String? filterPrimaryCategory,
    String? topic,
  }) async {
    try {
      final response = await _getUriWithRetry(
        uri,
        options: Options(
          headers: const {
            "Accept":
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          },
        ),
      );
      final html = response.data?.toString() ?? "";
      if (html.trim().isEmpty) {
        return _failure(
          "arXiv returned an empty response. Please try again.",
          statusCode: response.statusCode,
        );
      }

      return ArxivWebSearch.parseSearchHtml(
        html,
        start: start,
        pageSize: pageSize,
        filterPrimaryCategory: filterPrimaryCategory,
        topic: topic,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return _failure(
        _messageForDioException(e),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return _failure("Could not read the arXiv response. Please try again.");
    }
  }

  static Future<ArxivSearchResult> _searchWithMetadata(
    String term, {
    int page = 0,
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
    String? topic,
  }) async {
    final parkerXml = Xml2Json();
    final rawXml = Xml2Json();

    try {
      final response = await _getUriWithRetry(
        queryUriFor(
          term,
          page: page,
          pageSize: pageSize,
          sortOption: sortOption,
        ),
      );
      final responseXml = response.data?.toString() ?? "";
      if (responseXml.trim().isEmpty) {
        return _failure(
          "arXiv returned an empty response. Please try again.",
          statusCode: response.statusCode,
        );
      }

      parkerXml.parse(responseXml);
      rawXml.parse(responseXml);

      final jsonData = _asMap(json.decode(parkerXml.toParker()));
      final rawData = _asMap(json.decode(rawXml.toBadgerfish()));
      final feed = _asMap(jsonData["feed"]);
      final rawFeed = _asMap(rawData["feed"]);
      final entries = _asList(feed["entry"]);
      final rawEntries = _asList(rawFeed["entry"]);

      final papers = <Paper>[];
      for (var index = 0; index < entries.length; index++) {
        papers.add(
          Paper.fromJson(
            _asMap(entries[index]),
            rawEntry: index < rawEntries.length
                ? _asMap(rawEntries[index])
                : const {},
          ),
        );
      }

      return ArxivSearchResult(
        papers: papers,
        feed: feed,
        rawResponse: rawData,
        rawXml: responseXml,
        statusCode: response.statusCode,
        topic: topic,
      );
    } on DioException catch (e) {
      return _failure(
        _messageForDioException(e),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return _failure("Could not read the arXiv response. Please try again.");
    }
  }

  static Uri queryUriFor(
    String term, {
    int page = 0,
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
  }) {
    final arxivId = extractArxivId(term);
    if (arxivId != null) {
      return Uri.https(_host, _path, {
        "id_list": arxivId,
        "start": page.toString(),
        "max_results": pageSize.toString(),
      });
    }

    return Uri.https(_host, _path, {
      "search_query": searchQueryFor(term),
      "start": page.toString(),
      "max_results": pageSize.toString(),
      "sortBy": sortOption.sortBy,
      "sortOrder": sortOption.sortOrder,
    });
  }

  /// Extracts a normalized arXiv paper ID from a bare ID, `arXiv:` prefix, or arXiv URL.
  static String? extractArxivId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Match arXiv URLs like https://arxiv.org/abs/2301.07041v1 or /pdf/2301.07041.pdf?foo=bar
    final urlMatch = RegExp(
      r'^(?:https?:\/\/)?(?:www\.|export\.)?arxiv\.org\/(?:abs|pdf|html)\/([^\s?#]+?)(?:\.pdf)?\/?(?:[?#].*)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final candidate = (urlMatch?.group(1) ?? trimmed)
        .replaceFirst(RegExp(r'^arxiv:', caseSensitive: false), '')
        .trim();

    final newIdPattern = RegExp(r'^\d{4}\.\d{4,5}(?:v\d+)?$');
    final oldIdPattern = RegExp(
      r'^[a-z-]+(?:\.[a-z-]+)?\/\d{7}(?:v\d+)?$',
      caseSensitive: false,
    );
    if (newIdPattern.hasMatch(candidate) || oldIdPattern.hasMatch(candidate)) {
      return candidate;
    }
    return null;
  }

  static String searchQueryFor(String term) {
    final trimmedTerm = term.trim();
    if (_isArxivFieldQuery(trimmedTerm)) {
      return trimmedTerm;
    }
    final arxivId = extractArxivId(trimmedTerm);
    if (arxivId != null) {
      return "id:$arxivId";
    }
    return "all:$trimmedTerm";
  }

  static bool _isArxivFieldQuery(String term) {
    return RegExp(
      r'^(all|ti|au|abs|co|jr|cat|rn|id|submittedDate|lastUpdatedDate):',
      caseSensitive: false,
    ).hasMatch(term);
  }

  static Future<List<Paper>> search(
    String term, {
    int page = 0,
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
  }) async {
    final result = await searchWithMetadata(
      term,
      page: page,
      pageSize: pageSize,
      sortOption: sortOption,
    );
    return result.papers;
  }

  /// Fetches papers for a random topic.
  static Future<ArxivSearchResult> suggestWithMetadata({
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
  }) {
    Random random = Random();
    int randomIndex = random.nextInt(_topics.length);
    String topic = _topics[randomIndex];

    return _runRateLimitedRequest(
      () => _searchWithMetadata(
        topic,
        pageSize: pageSize,
        sortOption: sortOption,
        topic: topic,
      ),
    );
  }

  static Future<List<Paper>> suggest({
    int pageSize = 30,
    ArxivSortOption sortOption = ArxivSortOption.relevance,
  }) {
    return suggestWithMetadata(
      pageSize: pageSize,
      sortOption: sortOption,
    ).then((result) => result.papers);
  }

  static Future<Response<String>> _getUriWithRetry(
    Uri uri, {
    Options? options,
    int maxRetries = 2,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _dio.getUri<String>(uri, options: options);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final isTransientStatus =
            status == 429 ||
            status == 500 ||
            status == 502 ||
            status == 503 ||
            status == 504;
        final isTransientType =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError;

        if (attempt >= maxRetries || (!isTransientStatus && !isTransientType)) {
          rethrow;
        }
        attempt++;
        final delaySeconds = attempt;
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
  }

  static Future<T> _runRateLimitedRequest<T>(
    Future<T> Function() request, {
    Duration minInterval = _minimumRequestInterval,
  }) {
    final queuedRequest = _requestQueue.then((_) async {
      final lastRequestStartedAt = _lastRequestStartedAt;
      if (lastRequestStartedAt != null) {
        final nextAllowedStart = lastRequestStartedAt.add(minInterval);
        final wait = nextAllowedStart.difference(DateTime.now());
        if (!wait.isNegative) {
          await Future.delayed(wait);
        }
      }

      _lastRequestStartedAt = DateTime.now();
      return request();
    });

    _requestQueue = queuedRequest.then((_) {}, onError: (_) {});
    return queuedRequest;
  }

  static ArxivSearchResult _failure(String message, {int? statusCode}) {
    return ArxivSearchResult(
      papers: const [],
      feed: const {},
      rawResponse: const {},
      rawXml: "",
      errorMessage: message,
      statusCode: statusCode,
    );
  }

  static String _messageForDioException(DioException exception) {
    final statusCode = exception.response?.statusCode;
    if (statusCode == 429) {
      return "arXiv is rate limiting requests. Please wait a few seconds and try again.";
    }
    if (statusCode != null) {
      return "arXiv returned HTTP $statusCode. Please try again.";
    }

    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return "arXiv took too long to respond. Please try again.";
      case DioExceptionType.connectionError:
        return "Could not reach arXiv. Check your connection and try again.";
      case DioExceptionType.cancel:
        return "The arXiv request was cancelled. Please try again.";
      case DioExceptionType.badCertificate:
        return "Could not verify arXiv's secure connection.";
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return "Could not fetch papers from arXiv. Please try again.";
    }
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

List<dynamic> _asList(dynamic value) {
  if (value == null) {
    return [];
  }
  if (value is List) {
    return value;
  }
  return [value];
}
