// ignore_for_file: file_names
import 'dart:async';
import 'dart:math' as math;

import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/advanced_search_sheet.dart';
import 'package:arxiv/components/category_picker_sheet.dart';
import 'package:arxiv/components/each_paper_card.dart';
import 'package:arxiv/components/paper_card_skeleton.dart';
import 'package:arxiv/components/search_box.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/services/arxiv_category_parser.dart';
import 'package:arxiv/services/arxiv_update_schedule.dart';
import 'package:arxiv/services/bookmarks_store.dart';
import 'package:arxiv/services/feed_cache_store.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:arxiv/services/pdf_cache_store.dart';
import 'package:arxiv/services/read_papers_store.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/ai_chat_page.dart';
import 'package:arxiv/pages/bookmarks_page.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/pages/paper_notes_page.dart';
import 'package:arxiv/pages/pdf_viewer.dart';
import 'package:arxiv/pages/settings_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var sourceCodeURL = "https://github.com/enYao39/ArxivPocket";
  var scholarXivURL = "https://ScholarXIV.com";
  int startPagination = 0;
  int maxContent = 30;
  int paginationGap = 30;
  var pdfBaseURL = "https://arxiv.org/pdf";
  ArxivSortOption sortOption = ArxivSortOption.newest;
  List<ArxivCategory> selectedCategories = [];
  ArxivCategory? get selectedCategory =>
      selectedCategories.isNotEmpty ? selectedCategories.first : null;
  ArxivAdvancedQuery? _activeAdvancedQuery;
  String _lastAdvancedSummary = "";

  var isHomeScreenLoading = true;
  bool _isLoadingMore = false;
  DateTime? _lastFetchedAtUtc;
  bool _dismissedNoUpdateBanner = false;
  TextEditingController searchTermController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();
  int notesRefreshToken = 0;

  List<Paper> data = [];
  List<Paper> _cachedFeedPapers = [];
  Set<String> _newTodayPaperIds = {};
  List<int> _pageBoundaries = [];
  int _nextFetchOffset = 0;
  final ValueNotifier<double> _pullUpOverscrollNotifier = ValueNotifier<double>(
    0.0,
  );
  bool _isDraggingPullUp = false;
  bool _pullUpHapticFired = false;
  static const MethodChannel _appLinksChannel = MethodChannel(
    "com.example.arxiv/app_links",
  );
  Timer? _wheelPullUpTimer;
  static const double _pullUpTriggerDistance = 88.0;
  int? _pendingRestoreVisibleCount;
  double? _pendingRestoreScrollOffset;
  ArxivSearchResult? lastSearchResult;
  String? homeScreenError;
  int _searchRequestSerial = 0;

  bool get _hasActiveSearchOrFilter =>
      selectedCategories.isNotEmpty ||
      _activeAdvancedQuery != null ||
      searchTermController.text.trim().isNotEmpty;

  bool get _isCacheableBrowseFeed =>
      selectedCategories.isNotEmpty &&
      _activeAdvancedQuery == null &&
      searchTermController.text.trim().isEmpty;

  bool get _canLoadMore {
    if (isHomeScreenLoading || homeScreenError != null || data.isEmpty) {
      return false;
    }
    if (!_hasActiveSearchOrFilter) {
      return false;
    }
    if (_isCacheableBrowseFeed && data.length < _cachedFeedPapers.length) {
      return true;
    }
    final total = lastSearchResult?.totalResults ?? 0;
    if (total > 0) {
      return _nextFetchOffset < total;
    }
    return data.length >= maxContent;
  }

  void _scrollToTop() {
    if (!_feedScrollController.hasClients) return;
    _feedScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  int get _effectivePageSize => _isCacheableBrowseFeed
      ? ArxivWebSearch.normalizeWebPageSize(maxContent)
      : maxContent;

  void _saveCurrentFeedState({double? scrollOffset}) {
    final offset = scrollOffset ??
        (_feedScrollController.hasClients
            ? _feedScrollController.offset
            : 0.0);
    MainPageStyleStore().saveLastFeedState(
      LastFeedState(
        query: searchTermController.text.trim(),
        categoryCode: selectedCategory?.code,
        categoryCodes: selectedCategories.map((c) => c.code).toList(),
        sortOption: sortOption,
        startPagination: startPagination,
        pageSize: maxContent,
        visibleCount: data.isNotEmpty ? data.length : maxContent,
        scrollOffset: offset,
      ),
    );
  }

  void _restoreScrollIfNeeded() {
    final target = _pendingRestoreScrollOffset;
    _pendingRestoreScrollOffset = null;
    if (target == null || target <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_feedScrollController.hasClients) return;
      final maxExtent = _feedScrollController.position.maxScrollExtent;
      _feedScrollController.jumpTo(math.min(target, maxExtent));
    });
  }

  Future<ArxivSearchResult> _fetchFeedPage(int pageOffset) async {
    final rawSearchInput = searchTermController.text.trim();
    final excludeCrossListed =
        MainPageStyleStore.notifier.value.excludeCrossListed;
    final filterPrimary = excludeCrossListed && selectedCategories.isNotEmpty
        ? selectedCategories.map((c) => c.code).join(",")
        : null;

    if (_activeAdvancedQuery != null) {
      return Arxiv.advancedSearchWithMetadata(
        _activeAdvancedQuery!,
        page: pageOffset,
      );
    }
    if (selectedCategories.isNotEmpty && rawSearchInput.isEmpty) {
      return Arxiv.advancedSearchWithMetadata(
        ArxivAdvancedQuery(
          categories: selectedCategories,
          includeCrossList: !excludeCrossListed,
          sortOption: sortOption,
          pageSize: ArxivWebSearch.normalizeWebPageSize(maxContent),
        ),
        page: pageOffset,
        filterPrimaryCategory: filterPrimary,
      );
    }
    if (rawSearchInput.isNotEmpty) {
      if (selectedCategories.isNotEmpty &&
          Arxiv.extractArxivId(rawSearchInput) == null) {
        return Arxiv.advancedSearchWithMetadata(
          ArxivAdvancedQuery(
            terms: [ArxivSearchTermRow(term: rawSearchInput)],
            categories: selectedCategories,
            includeCrossList: !excludeCrossListed,
            sortOption: sortOption,
            pageSize: ArxivWebSearch.normalizeWebPageSize(maxContent),
          ),
          page: pageOffset,
          filterPrimaryCategory: filterPrimary,
        );
      }
      return Arxiv.searchWithMetadata(
        rawSearchInput,
        page: pageOffset,
        pageSize: maxContent,
        sortOption: sortOption,
        filterPrimaryCategory: filterPrimary,
      );
    }
    return const ArxivSearchResult(
      papers: [],
      feed: {},
      rawResponse: {},
      rawXml: "",
    );
  }

  List<int> _buildInitialBoundaries(int visibleCount) {
    final step = _effectivePageSize;
    if (step <= 0 || visibleCount <= step) return [];
    final boundaries = <int>[];
    for (var idx = step; idx < visibleCount; idx += step) {
      boundaries.add(idx);
    }
    return boundaries;
  }

  Future<void> search({
    bool? resetPagination,
    bool forceNetwork = false,
  }) async {
    final requestSerial = ++_searchRequestSerial;
    if (resetPagination == true) {
      startPagination = 0;
    }

    final rawSearchInput = searchTermController.text.trim();
    if (_activeAdvancedQuery != null &&
        rawSearchInput != _lastAdvancedSummary.trim()) {
      _activeAdvancedQuery = null;
      _lastAdvancedSummary = "";
    }

    if (selectedCategories.isEmpty &&
        _activeAdvancedQuery == null &&
        rawSearchInput.isEmpty) {
      _pendingRestoreVisibleCount = null;
      _pendingRestoreScrollOffset = null;
      setState(() {
        isHomeScreenLoading = false;
        _isLoadingMore = false;
        homeScreenError = null;
        data = [];
        _cachedFeedPapers = [];
        _newTodayPaperIds = {};
        _pageBoundaries = [];
        lastSearchResult = null;
      });
      _saveCurrentFeedState(scrollOffset: 0.0);
      return;
    }

    final excludeCrossListed =
        MainPageStyleStore.notifier.value.excludeCrossListed;
    final isCacheable = _isCacheableBrowseFeed && startPagination == 0;
    final cacheKey = isCacheable
        ? FeedCacheStore.buildKey(
            categoryCodes: selectedCategories.map((c) => c.code).toList(),
            sortOption: sortOption,
            excludeCrossListed: excludeCrossListed,
          )
        : null;

    if (isCacheable && !forceNetwork && cacheKey != null) {
      final cached = await FeedCacheStore().loadForCategories(
        categoryCodes: selectedCategories.map((c) => c.code).toList(),
        sortOption: sortOption,
        excludeCrossListed: excludeCrossListed,
      );
      if (!mounted || requestSerial != _searchRequestSerial) return;

      if (cached != null && cached.papers.isNotEmpty) {
        final desiredCount = _pendingRestoreVisibleCount ?? maxContent;
        _pendingRestoreVisibleCount = null;
        final visibleCount = math.min(
          math.max(desiredCount, 1),
          cached.papers.length,
        );

        setState(() {
          _cachedFeedPapers = cached.papers;
          _newTodayPaperIds = cached.newPaperIds.toSet();
          data = cached.papers.take(visibleCount).toList();
          _pageBoundaries = _buildInitialBoundaries(data.length);
          _nextFetchOffset = _effectivePageSize;
          lastSearchResult = ArxivSearchResult(
            papers: data,
            feed: {"opensearch:totalResults": cached.totalResults},
            rawResponse: const {},
            rawXml: "",
          );
          homeScreenError = null;
          isHomeScreenLoading = false;
          _lastFetchedAtUtc = cached.cachedAtUtc;
        });
        _saveCurrentFeedState();
        _restoreScrollIfNeeded();

        if (!ArxivUpdateSchedule.hasNewAnnouncementSince(cached.cachedAtUtc)) {
          return;
        }

        // New arXiv announcement available: fetch fresh page 0 + /list/<cat>/new IDs.
        final categoryCodes = selectedCategories.map((c) => c.code).toList();
        final freshFuture = _fetchFeedPage(0);
        final newIdsFuture = Arxiv.fetchNewAnnouncementIds(
          categoryCodes,
          includeCrossLists: !excludeCrossListed,
        );
        final freshResult = await freshFuture;
        final fetchedNewIds = await newIdsFuture;
        if (!mounted || requestSerial != _searchRequestSerial) return;
        if (freshResult.errorMessage == null && freshResult.papers.isNotEmpty) {
          final nowUtc = DateTime.now().toUtc();
          final merged = await FeedCacheStore().mergeFreshPage(
            cacheKey,
            freshPapers: freshResult.papers,
            totalResults: freshResult.totalResults,
            fetchedAtUtc: nowUtc,
            newPaperIds: fetchedNewIds?.toList(),
          );
          if (!mounted || requestSerial != _searchRequestSerial) return;
          final nextVisible = math.min(
            math.max(data.length, maxContent),
            merged.papers.length,
          );
          setState(() {
            _cachedFeedPapers = merged.papers;
            _newTodayPaperIds = merged.newPaperIds.toSet();
            data = merged.papers.take(nextVisible).toList();
            lastSearchResult = freshResult;
            _lastFetchedAtUtc = nowUtc;
          });
          _saveCurrentFeedState();
        }
        return;
      }
    }

    setState(() {
      isHomeScreenLoading = true;
      homeScreenError = null;
      data = [];
      _cachedFeedPapers = [];
      _newTodayPaperIds = {};
      _pageBoundaries = [];
      _isLoadingMore = false;
    });

    _saveCurrentFeedState(scrollOffset: 0.0);

    final resultFuture = _fetchFeedPage(startPagination);
    final newIdsFuture = isCacheable
        ? Arxiv.fetchNewAnnouncementIds(
            selectedCategories.map((c) => c.code).toList(),
            includeCrossLists: !excludeCrossListed,
          )
        : Future<Set<String>?>.value(null);
    final result = await resultFuture;
    final fetchedNewIds = await newIdsFuture;
    if (!mounted || requestSerial != _searchRequestSerial) {
      return;
    }

    if (isCacheable && cacheKey != null && result.errorMessage == null) {
      final nowUtc = DateTime.now().toUtc();
      final merged = await FeedCacheStore().mergeFreshPage(
        cacheKey,
        freshPapers: result.papers,
        totalResults: result.totalResults,
        fetchedAtUtc: nowUtc,
        newPaperIds: fetchedNewIds?.toList(),
      );
      if (!mounted || requestSerial != _searchRequestSerial) return;

      final desiredCount = _pendingRestoreVisibleCount ?? maxContent;
      _pendingRestoreVisibleCount = null;
      final visibleCount = math.min(
        math.max(desiredCount, 1),
        merged.papers.length,
      );
      setState(() {
        _cachedFeedPapers = merged.papers;
        _newTodayPaperIds = merged.newPaperIds.toSet();
        lastSearchResult = result;
        data = merged.papers.take(visibleCount).toList();
        _pageBoundaries = _buildInitialBoundaries(data.length);
        _nextFetchOffset = startPagination + _effectivePageSize;
        homeScreenError = null;
        isHomeScreenLoading = false;
        _lastFetchedAtUtc = nowUtc;
      });
      _saveCurrentFeedState();
      _restoreScrollIfNeeded();
      return;
    }

    _pendingRestoreVisibleCount = null;
    _pendingRestoreScrollOffset = null;
    setState(() {
      lastSearchResult = result;
      data = result.papers;
      _nextFetchOffset = startPagination + _effectivePageSize;
      homeScreenError = result.errorMessage;
      isHomeScreenLoading = false;
      _lastFetchedAtUtc =
          result.errorMessage == null ? DateTime.now().toUtc() : null;
    });
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_canLoadMore) return;

    final requestSerial = _searchRequestSerial;

    // 1. Cache-first: reveal more cached entries after a brief spinner animation.
    if (_isCacheableBrowseFeed && data.length < _cachedFeedPapers.length) {
      setState(() {
        _isLoadingMore = true;
      });
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted || requestSerial != _searchRequestSerial) {
        return;
      }

      final pageStep = _effectivePageSize;
      final nextCount = math.min(
        data.length + pageStep,
        _cachedFeedPapers.length,
      );
      setState(() {
        _isLoadingMore = false;
        if (nextCount > data.length) {
          _pageBoundaries = [..._pageBoundaries, data.length];
        }
        data = _cachedFeedPapers.take(nextCount).toList();
      });
      _saveCurrentFeedState();
      return;
    }

    // 2. No more cached entries: fetch next page from arXiv and append.
    setState(() {
      _isLoadingMore = true;
    });

    final offsetToFetch = _nextFetchOffset;
    final result = await _fetchFeedPage(offsetToFetch);
    if (!mounted || requestSerial != _searchRequestSerial) {
      return;
    }

    if (result.errorMessage != null) {
      setState(() {
        _isLoadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage!)),
      );
      return;
    }

    final existingIds = data
        .map((p) => ReadPapersStore.normalizeId(p.id))
        .toSet();
    final newPapers = result.papers
        .where((p) => existingIds.add(ReadPapersStore.normalizeId(p.id)))
        .toList();

    if (_isCacheableBrowseFeed && newPapers.isNotEmpty) {
      final excludeCrossListed =
          MainPageStyleStore.notifier.value.excludeCrossListed;
      final cacheKey = FeedCacheStore.buildKey(
        categoryCodes: selectedCategories.map((c) => c.code).toList(),
        sortOption: sortOption,
        excludeCrossListed: excludeCrossListed,
      );
      await FeedCacheStore().appendPage(
        cacheKey,
        morePapers: newPapers,
        totalResults: result.totalResults,
      );
    }

    if (!mounted || requestSerial != _searchRequestSerial) {
      return;
    }

    setState(() {
      _isLoadingMore = false;
      _nextFetchOffset = offsetToFetch + _effectivePageSize;
      lastSearchResult = result;
      if (newPapers.isNotEmpty) {
        _pageBoundaries = [..._pageBoundaries, data.length];
      }
      data = [...data, ...newPapers];
      if (_isCacheableBrowseFeed) {
        _cachedFeedPapers = [..._cachedFeedPapers, ...newPapers];
      }
    });
    _saveCurrentFeedState();
  }

  Future<void> _handlePullToRefresh() async {
    if (isHomeScreenLoading) {
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final shouldRefresh =
        homeScreenError != null ||
        data.isEmpty ||
        ArxivUpdateSchedule.hasNewAnnouncementSince(
          _lastFetchedAtUtc,
          nowUtc: nowUtc,
        );

    if (shouldRefresh) {
      await search(resetPagination: true, forceNetwork: true);
      return;
    }

    if (!mounted) return;
    final nextIn = ArxivUpdateSchedule.formatTimeUntilNextUpdate(nowUtc);
    final noUpdateReason = ArxivUpdateSchedule.noAnnouncementReason(nowUtc);
    final message = noUpdateReason != null
        ? "$noUpdateReason Next update in $nextIn."
        : "Already up to date. Next arXiv update in $nextIn.";
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: "Refresh anyway",
          onPressed: () {
            search();
          },
        ),
      ),
    );
  }

  Future<void> runFeedSearch(String query) async {
    _activeAdvancedQuery = null;
    _lastAdvancedSummary = "";
    final category = categoryFromSearchInput(query);
    if (category != null) {
      selectedCategories = [category];
      searchTermController.clear();
    } else {
      searchTermController.text = query;
    }
    await search(resetPagination: true);
    _scrollToTop();
  }

  Future<void> setCategories(List<ArxivCategory> categories) async {
    if (categoryFromSearchInput(searchTermController.text) != null) {
      searchTermController.clear();
    }
    selectedCategories = List<ArxivCategory>.from(categories);
    if (_activeAdvancedQuery != null) {
      _activeAdvancedQuery = ArxivAdvancedQuery(
        terms: _activeAdvancedQuery!.terms,
        categories: selectedCategories,
        includeCrossList: _activeAdvancedQuery!.includeCrossList,
        dateFilterMode: _activeAdvancedQuery!.dateFilterMode,
        specificYear: _activeAdvancedQuery!.specificYear,
        fromDate: _activeAdvancedQuery!.fromDate,
        toDate: _activeAdvancedQuery!.toDate,
        sortOption: _activeAdvancedQuery!.sortOption,
        pageSize: _activeAdvancedQuery!.pageSize,
      );
    }
    await search(resetPagination: true);
    _scrollToTop();
  }

  Future<void> toggleCategory(ArxivCategory category) async {
    final next = List<ArxivCategory>.from(selectedCategories);
    final idx = next.indexWhere((c) => c.code == category.code);
    if (idx >= 0) {
      next.removeAt(idx);
    } else {
      next.add(category);
    }
    await setCategories(next);
  }

  Future<void> searchCategoryByCode(String code) async {
    final category = categoryByCode(code);
    if (category != null) {
      await toggleCategory(category);
      return;
    }
    await runFeedSearch("cat:$code");
  }

  Future<void> clearCategoryFilter() async {
    selectedCategories = [];
    if (_activeAdvancedQuery != null) {
      final remaining = ArxivAdvancedQuery(
        terms: _activeAdvancedQuery!.terms,
        category: null,
        categories: const [],
        includeCrossList: _activeAdvancedQuery!.includeCrossList,
        dateFilterMode: _activeAdvancedQuery!.dateFilterMode,
        specificYear: _activeAdvancedQuery!.specificYear,
        fromDate: _activeAdvancedQuery!.fromDate,
        toDate: _activeAdvancedQuery!.toDate,
        sortOption: _activeAdvancedQuery!.sortOption,
        pageSize: _activeAdvancedQuery!.pageSize,
      );
      _activeAdvancedQuery = remaining.hasAnyCriteria ? remaining : null;
      if (_activeAdvancedQuery == null) {
        _lastAdvancedSummary = "";
        searchTermController.clear();
      }
    }
    if (categoryFromSearchInput(searchTermController.text) != null) {
      searchTermController.clear();
    }
    startPagination = 0;
    await search(resetPagination: true);
  }

  Future<void> _clearAdvancedSearch() async {
    _activeAdvancedQuery = null;
    _lastAdvancedSummary = "";
    searchTermController.clear();
    startPagination = 0;
    await search(resetPagination: true);
  }

  void _onSearchTermChanged() {
    if (!mounted) return;
    // Rebuilds SearchBox (clear button) and filter chips when the field text changes.
    setState(() {});
  }

  Future<void> changeSortOption(ArxivSortOption option) async {
    if (option == sortOption) return;
    setState(() {
      sortOption = option;
    });
    await search(resetPagination: true);
  }

  void _openAdvancedSearch() {
    showAdvancedSearchSheet(
      context,
      initialQuery: _activeAdvancedQuery,
      initialCategory: selectedCategory,
      initialSortOption: sortOption,
      initialPageSize: maxContent,
      onApply: (advancedQuery) async {
        final summary = advancedQuery.summaryLabel();
        setState(() {
          sortOption = advancedQuery.sortOption;
          maxContent = advancedQuery.pageSize;
          paginationGap = advancedQuery.pageSize;
          selectedCategories = advancedQuery.effectiveCategories;
          _activeAdvancedQuery = advancedQuery;
          _lastAdvancedSummary = summary;
          if (summary.isEmpty) {
            searchTermController.clear();
          } else {
            searchTermController.text = summary;
          }
        });
        await search(resetPagination: true);
        _scrollToTop();
      },
    );
  }

  var paperTitle = "";
  var savePath = "";
  var pdfURL = "";
  dynamic downloadPath = "";

  Future<void> parseAndLaunchURL(String currentURL, String title) async {
    paperTitle = title;

    pdfURL = pdfUrlFor(currentURL);
    final splitURL = pdfURL.split("/");
    final id = splitURL.isNotEmpty ? splitURL.last : "paper";
    final sanitizedId = id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    savePath = await PdfCacheStore().cachePathForId(sanitizedId);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewer(
          paperTitle: paperTitle,
          savePath: savePath,
          pdfURL: pdfURL,
          urlType: 2,
          downloadPaper: downloadPaper,
        ),
      ),
    );
    setState(() {});
  }

  void downloadPaper(String paperURL) async {
    await launchUrl(Uri.parse(pdfUrlFor(paperURL)));
  }

  Future<void> openPaperDetails(Paper paper) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaperDetailPage(
          paper: paper,
          downloadPaper: downloadPaper,
          parseAndLaunchURL: parseAndLaunchURL,
          onSearchQuerySelected: runFeedSearch,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      notesRefreshToken++;
    });
  }

  Future<void> openPaperNotes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaperNotesPage(
          downloadPaper: downloadPaper,
          parseAndLaunchURL: parseAndLaunchURL,
          onSearchQuerySelected: runFeedSearch,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      notesRefreshToken++;
    });
  }

  String pdfUrlFor(String paperURL) {
    var selectedURL = paperURL.trim();
    if (selectedURL.startsWith("http") && selectedURL.contains("/pdf/")) {
      return selectedURL;
    }

    var splitURL = paperURL.split("/");
    var id = splitURL[splitURL.length - 1];
    if (id.contains(".") == true) {
      selectedURL = "$pdfBaseURL/$id";
    } else {
      selectedURL = "$pdfBaseURL/cond-mat/$id";
    }
    return selectedURL;
  }

  @override
  void initState() {
    super.initState();
    searchTermController.addListener(_onSearchTermChanged);
    _appLinksChannel.setMethodCallHandler((call) async {
      if (call.method == "onLink" && call.arguments is String) {
        await _handleIncomingArxivLink(call.arguments as String);
      }
    });
    _initializeAndLoadFeed();
  }

  Future<void> _handleIncomingArxivLink(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || !mounted) return;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.length >= 2 && uri.pathSegments.first == "list") {
      final category = categoryByCode(uri.pathSegments[1]);
      if (category != null) {
        await setCategories([category]);
        return;
      }
    }

    final arxivId = Arxiv.extractArxivId(trimmed);
    if (arxivId == null) return;

    if (uri != null && uri.path.startsWith("/pdf/")) {
      await parseAndLaunchURL(trimmed, "arXiv:$arxivId");
      return;
    }

    final normTarget = ReadPapersStore.normalizeId(arxivId);
    Paper? localMatch;
    final bookmarks = await BookmarksStore().loadBookmarks();
    for (final p in [...data, ..._cachedFeedPapers, ...bookmarks]) {
      if (ReadPapersStore.normalizeId(p.id) == normTarget) {
        localMatch = p;
        break;
      }
    }
    if (localMatch != null) {
      await openPaperDetails(localMatch);
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text("Opening arXiv:$arxivId..."),
        duration: const Duration(seconds: 6),
      ),
    );

    final result = await Arxiv.searchWithMetadata(arxivId, pageSize: 1);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (result.errorMessage == null && result.papers.isNotEmpty) {
      await openPaperDetails(result.papers.first);
      return;
    }

    if (result.errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    }
    await runFeedSearch(arxivId);
  }

  Future<void> _initializeAndLoadFeed() async {
    await Future.wait([
      ReadPapersStore().ensureLoaded(),
      BookmarksStore().ensureLoaded(),
    ]);
    final store = MainPageStyleStore();
    final settings = await store.load();
    if (!mounted) return;

    if (settings.restoreLastSession) {
      final lastState = await store.loadLastFeedState();
      if (!mounted) return;
      setState(() {
        searchTermController.text =
            settings.restoreSearchFilter ? lastState.query : "";
        selectedCategories = lastState.effectiveCategoryCodes
            .map(categoryByCode)
            .whereType<ArxivCategory>()
            .toList();
        sortOption = lastState.sortOption;
        startPagination =
            settings.restoreSearchFilter ? lastState.startPagination : 0;
        maxContent = lastState.pageSize;
        paginationGap = lastState.pageSize;
        if (settings.restoreFeedPosition) {
          _pendingRestoreVisibleCount = lastState.visibleCount;
          _pendingRestoreScrollOffset = lastState.scrollOffset;
        }
      });
    }

    await search();

    try {
      final initialLink =
          await _appLinksChannel.invokeMethod<String>("getInitialLink");
      if (initialLink != null && initialLink.isNotEmpty) {
        await _handleIncomingArxivLink(initialLink);
      }
    } catch (_) {
      // Ignore when running on non-Android platforms or widget tests.
    }
  }

  @override
  void dispose() {
    _wheelPullUpTimer?.cancel();
    searchTermController.removeListener(_onSearchTermChanged);
    searchTermController.dispose();
    _feedScrollController.dispose();
    _pullUpOverscrollNotifier.dispose();
    super.dispose();
  }

  Widget _buildFeedStatusBar(ColorScheme colorScheme) {
    final total = lastSearchResult?.totalResults ?? 0;
    final topic = lastSearchResult?.topic;

    if (!_hasActiveSearchOrFilter) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 0.0, 8.0, 4.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                topic != null && topic.isNotEmpty
                    ? "Suggested: $topic"
                    : "Suggested papers",
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                search(resetPagination: true);
              },
              icon: const Icon(Icons.shuffle, size: 16.0),
              label: const Text("Shuffle"),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );
    }

    final rangeStart = startPagination + 1;
    final rangeEnd = startPagination + data.length;
    final totalSuffix = total > 0 ? " of $total" : "";

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Showing $rangeStart–$rangeEnd$totalSuffix",
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            "Sorted by ${sortOption.label}",
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool _isPaperNew(Paper paper) {
    if (!_isCacheableBrowseFeed || sortOption != ArxivSortOption.newest) {
      return false;
    }
    if (_newTodayPaperIds.isNotEmpty) {
      return _newTodayPaperIds.contains(ReadPapersStore.normalizeId(paper.id));
    }
    return ArxivUpdateSchedule.isSubmittedInLatestWindow(paper.publishedAt);
  }

  String? _latestBatchDate() {
    if (!_isCacheableBrowseFeed ||
        sortOption != ArxivSortOption.newest ||
        data.isEmpty) {
      return null;
    }
    final latestUtc = ArxivUpdateSchedule.latestAnnouncementUtc(
      DateTime.now().toUtc(),
    );
    final eastern = ArxivUpdateSchedule.toEasternWallClock(latestUtc);
    final m = eastern.month.toString().padLeft(2, "0");
    final d = eastern.day.toString().padLeft(2, "0");
    return "${eastern.year}-$m-$d";
  }

  Widget _buildNewTodayBanner(
    ColorScheme colorScheme,
    Set<String> readIds,
    String latestDate,
  ) {
    final source = _isCacheableBrowseFeed && _cachedFeedPapers.isNotEmpty
        ? _cachedFeedPapers
        : data;
    final batchPapers = source.where(_isPaperNew).toList();
    if (batchPapers.isEmpty) return const SizedBox.shrink();

    final unreadCount = batchPapers
        .where((p) => !readIds.contains(ReadPapersStore.normalizeId(p.id)))
        .length;
    final noAnnouncement =
        ArxivUpdateSchedule.noAnnouncementReason(DateTime.now().toUtc()) !=
            null;
    final label = noAnnouncement
        ? "Latest batch ($latestDate): ${batchPapers.length} papers · $unreadCount unread"
        : "New today ($latestDate): ${batchPapers.length} new · $unreadCount unread";

    return Container(
      margin: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(110),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_motion_outlined,
            size: 16.0,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastReadDivider(ColorScheme colorScheme, int unreadAbove) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 6.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colorScheme.primary.withAlpha(90),
              thickness: 1.0,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Text(
              "Last read · $unreadAbove unread above",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: colorScheme.primary.withAlpha(90),
              thickness: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageDivider(
    ColorScheme colorScheme,
    int pageNumber,
    int rangeStart,
    int rangeEnd,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 6.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colorScheme.outlineVariant.withAlpha(140),
              thickness: 1.0,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10.0),
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 3.0,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Text(
              "Page $pageNumber · $rangeStart–$rangeEnd",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: colorScheme.outlineVariant.withAlpha(140),
              thickness: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  double _pullUpVisualLift(double overscroll) {
    if (_isLoadingMore) return 64.0;
    return (overscroll * 0.65).clamp(0.0, 92.0);
  }

  Widget _buildPullUpOverlay(ColorScheme colorScheme) {
    return ValueListenableBuilder<double>(
      valueListenable: _pullUpOverscrollNotifier,
      builder: (context, overscroll, _) {
        final targetLift = _pullUpVisualLift(overscroll);
        final progress = (overscroll / _pullUpTriggerDistance).clamp(0.0, 1.0);
        final ready = overscroll >= _pullUpTriggerDistance;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: targetLift),
          duration: _isDraggingPullUp
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, lift, child) {
            if (lift <= 1.0 && !_isLoadingMore) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              height: lift.clamp(0.0, 92.0),
              child: Opacity(
                opacity: (lift / 28.0).clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: IgnorePointer(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22.0,
                    height: 22.0,
                    child: _isLoadingMore
                        ? CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colorScheme.primary,
                          )
                        : Transform.rotate(
                            angle: progress * 2.0 * math.pi,
                            child: CircularProgressIndicator(
                              value: progress.clamp(0.08, 1.0),
                              strokeWidth: 2.4,
                              color: ready
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                  ),
                  if (_isLoadingMore || ready) ...[
                    const SizedBox(width: 10.0),
                    Text(
                      _isLoadingMore ? "Loading..." : "Release to load",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: ready || _isLoadingMore
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _updatePullUpOverscroll(double nextValue) {
    _isDraggingPullUp = nextValue > 0.0;
    final clamped = nextValue.clamp(0.0, 140.0);
    if (clamped >= _pullUpTriggerDistance && !_pullUpHapticFired) {
      _pullUpHapticFired = true;
      HapticFeedback.selectionClick();
    } else if (clamped < _pullUpTriggerDistance) {
      _pullUpHapticFired = false;
    }
    if (clamped != _pullUpOverscrollNotifier.value) {
      _pullUpOverscrollNotifier.value = clamped;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_canLoadMore || _isLoadingMore || !_feedScrollController.hasClients) {
      return;
    }
    final pos = _feedScrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 2.0;

    if (!atBottom && _pullUpOverscrollNotifier.value > 0.0) {
      _updatePullUpOverscroll(0.0);
      return;
    }

    // Dragging finger down (dy > 0) pulls back and cancels the load gesture.
    if (event.delta.dy > 0 && _pullUpOverscrollNotifier.value > 0.0) {
      _updatePullUpOverscroll(
        _pullUpOverscrollNotifier.value - event.delta.dy * 1.4,
      );
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_canLoadMore || _isLoadingMore || !_feedScrollController.hasClients) {
      return;
    }
    final pos = _feedScrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 2.0;

    if (atBottom && event.scrollDelta.dy > 0) {
      _updatePullUpOverscroll(
        _pullUpOverscrollNotifier.value + event.scrollDelta.dy * 0.65,
      );
      _wheelPullUpTimer?.cancel();
      _wheelPullUpTimer = Timer(
        const Duration(milliseconds: 260),
        _finishPullUpGesture,
      );
    } else if (event.scrollDelta.dy < 0 &&
        _pullUpOverscrollNotifier.value > 0.0) {
      _wheelPullUpTimer?.cancel();
      _updatePullUpOverscroll(
        _pullUpOverscrollNotifier.value + event.scrollDelta.dy * 0.65,
      );
    }
  }

  void _finishPullUpGesture() {
    _wheelPullUpTimer?.cancel();
    _isDraggingPullUp = false;
    final shouldLoad =
        _pullUpOverscrollNotifier.value >= _pullUpTriggerDistance &&
        !_isLoadingMore &&
        _canLoadMore;
    if (_pullUpOverscrollNotifier.value != 0.0 || _pullUpHapticFired) {
      _pullUpOverscrollNotifier.value = 0.0;
      _pullUpHapticFired = false;
    }
    if (shouldLoad) {
      _loadNextPage();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 2.0 &&
        _canLoadMore &&
        !_isLoadingMore) {
      _updatePullUpOverscroll(
        _pullUpOverscrollNotifier.value + notification.overscroll,
      );
    } else if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels > notification.metrics.maxScrollExtent &&
          _canLoadMore &&
          !_isLoadingMore) {
        _updatePullUpOverscroll(
          notification.metrics.pixels - notification.metrics.maxScrollExtent,
        );
      } else if ((notification.scrollDelta ?? 0) < 0 &&
          _pullUpOverscrollNotifier.value > 0.0) {
        _updatePullUpOverscroll(0.0);
      }
    } else if (notification is ScrollEndNotification) {
      if (MainPageStyleStore.notifier.value.restoreFeedPosition &&
          _feedScrollController.hasClients) {
        _saveCurrentFeedState(scrollOffset: _feedScrollController.offset);
      }
      _finishPullUpGesture();
    }
    return false;
  }

  String? _matchedFullGroupName() {
    if (selectedCategories.length < 2) return null;
    final selectedCodes = selectedCategories.map((c) => c.code).toSet();
    final grouped = groupedArxivCategories();
    for (final entry in grouped.entries) {
      final groupCodes = entry.value.map((c) => c.code).toSet();
      if (groupCodes.length == selectedCodes.length &&
          groupCodes.containsAll(selectedCodes)) {
        return entry.key;
      }
    }
    return null;
  }

  Widget _buildActiveFilterChips(ColorScheme colorScheme, {bool isWide = false}) {
    final fullGroup = isWide ? null : _matchedFullGroupName();
    final chips = <Widget>[];

    if (fullGroup != null) {
      chips.add(
        InputChip(
          label: Text("$fullGroup (${selectedCategories.length})"),
          selected: true,
          onPressed: () {
            showCategoryPickerSheet(
              context,
              currentQuery: searchTermController.text.trim(),
              selectedCategories: selectedCategories,
              onCategoriesChanged: setCategories,
            );
          },
          onDeleted: clearCategoryFilter,
          visualDensity: VisualDensity.compact,
        ),
      );
    } else if (isWide || selectedCategories.length <= 2) {
      for (final cat in selectedCategories) {
        chips.add(
          InputChip(
            label: Text(categoryFilterLabel(cat)),
            selected: true,
            onPressed: () => toggleCategory(cat),
            onDeleted: () => toggleCategory(cat),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
    } else {
      for (final cat in selectedCategories.take(2)) {
        chips.add(
          InputChip(
            label: Text(categoryFilterLabel(cat)),
            selected: true,
            onPressed: () => toggleCategory(cat),
            onDeleted: () => toggleCategory(cat),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
      final extraCount = selectedCategories.length - 2;
      chips.add(
        InputChip(
          label: Text("+$extraCount more"),
          selected: true,
          onPressed: () {
            showCategoryPickerSheet(
              context,
              currentQuery: searchTermController.text.trim(),
              selectedCategories: selectedCategories,
              onCategoriesChanged: setCategories,
            );
          },
          onDeleted: clearCategoryFilter,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (_activeAdvancedQuery != null) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.tune_rounded, size: 16.0),
          label: const Text("Advanced search"),
          selected: true,
          onPressed: _openAdvancedSearch,
          onDeleted: _clearAdvancedSearch,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 6.0),
      child: isWide
          ? Wrap(
              spacing: 8.0,
              runSpacing: 6.0,
              children: chips,
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8.0),
                    chips[i],
                  ],
                ],
              ),
            ),
    );
  }

  static const _recommendedCategoryCodes = [
    "astro-ph.CO",
    "astro-ph.GA",
    "astro-ph.HE",
    "cs.AI",
    "cs.LG",
    "cs.CL",
    "quant-ph",
    "hep-th",
    "stat.ML",
  ];

  Widget _buildCategoryPromptView(ColorScheme colorScheme) {
    final recommended = _recommendedCategoryCodes
        .map(categoryByCode)
        .whereType<ArxivCategory>()
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 56.0, 20.0, 32.0),
      child: Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 46.0,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 14.0),
          Text(
            "Select a Category",
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            "Pick one or more arXiv categories below to load the latest papers, or browse all fields.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.center,
            children: recommended.map((category) {
              return ActionChip(
                label: Text(category.code),
                tooltip: category.label,
                onPressed: () => toggleCategory(category),
              );
            }).toList(),
          ),
          const SizedBox(height: 20.0),
          FilledButton.tonalIcon(
            onPressed: () {
              showCategoryPickerSheet(
                context,
                currentQuery: searchTermController.text.trim(),
                selectedCategories: selectedCategories,
                onCategoriesChanged: setCategories,
              );
            },
            icon: const Icon(Icons.apps_rounded, size: 18.0),
            label: const Text("Browse all categories"),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ColorScheme colorScheme) {
    return NavigationRail(
      selectedIndex: 0,
      minWidth: 76.0,
      labelType: NavigationRailLabelType.all,
      backgroundColor: colorScheme.surface,
      leading: const SizedBox(height: 8.0),
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            _scrollToTop();
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BookmarksPage(
                  downloadPaper: downloadPaper,
                  parseAndLaunchURL: parseAndLaunchURL,
                  onSearchQuerySelected: runFeedSearch,
                ),
              ),
            );
            break;
          case 2:
            openPaperNotes();
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AIChatPage(paperData: null),
              ),
            );
            break;
          case 4:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
            break;
        }
      },
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.article_outlined),
          selectedIcon: Icon(Icons.article),
          label: Text("Feed"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bookmark_border_outlined),
          label: Text("Saved"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          label: Text("Notes"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          label: Text("AI Chat"),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          label: Text("Settings"),
        ),
      ],
    );
  }

  List<Widget> _buildSliverFeedRows(
    ColorScheme colorScheme,
    Set<String> readIds,
    String? latestBatchDate,
    int columns,
  ) {
    final firstReadIndex = data.indexWhere(
      (paper) => readIds.contains(ReadPapersStore.normalizeId(paper.id)),
    );

    Widget buildCard(Paper paper) {
      return EachPaperCard(
        eachPaper: paper,
        downloadPaper: downloadPaper,
        parseAndLaunchURL: parseAndLaunchURL,
        isBookmarked: false,
        isNew: _isPaperNew(paper),
        onCardTap: () => openPaperDetails(paper),
        onCategoryTap: searchCategoryByCode,
        notesRefreshToken: notesRefreshToken,
      );
    }

    final rows = <Widget>[];
    var segmentBuffer = <Paper>[];

    int estimatedCardWeight(Paper p) =>
        p.title.length + (p.authors.length > 90 ? 90 : p.authors.length) + 120;

    void flushSegment() {
      if (segmentBuffer.isEmpty) return;
      if (columns <= 1) {
        for (final paper in segmentBuffer) {
          rows.add(buildCard(paper));
        }
      } else {
        final colWidgets = List.generate(columns, (_) => <Widget>[]);
        final colHeights = List<int>.filled(columns, 0);

        for (final paper in segmentBuffer) {
          var shortestCol = 0;
          for (var c = 1; c < columns; c++) {
            if (colHeights[c] < colHeights[shortestCol]) {
              shortestCol = c;
            }
          }
          colWidgets[shortestCol].add(buildCard(paper));
          colHeights[shortestCol] += estimatedCardWeight(paper);
        }

        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: colWidgets[c],
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      segmentBuffer.clear();
    }

    for (var i = 0; i < data.length; i++) {
      final pageBoundaryIdx =
          _isCacheableBrowseFeed ? _pageBoundaries.indexOf(i) : -1;
      final showPageDivider = pageBoundaryIdx != -1;
      final showLastReadDivider =
          _isCacheableBrowseFeed &&
          firstReadIndex > 0 &&
          i == firstReadIndex;

      if (showPageDivider || showLastReadDivider) {
        flushSegment();
        if (showPageDivider) {
          final nextBoundary =
              pageBoundaryIdx + 1 < _pageBoundaries.length
                  ? _pageBoundaries[pageBoundaryIdx + 1]
                  : data.length;
          rows.add(
            _buildPageDivider(
              colorScheme,
              pageBoundaryIdx + 2,
              i + 1,
              nextBoundary,
            ),
          );
        }
        if (showLastReadDivider) {
          rows.add(_buildLastReadDivider(colorScheme, firstReadIndex));
        }
      }

      segmentBuffer.add(data[i]);
    }
    flushSegment();
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latestBatchDate = _latestBatchDate();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useRail = screenWidth >= 760;
    final feedWidth = useRail ? screenWidth - 77.0 : screenWidth;
    final columns = feedWidth >= 1500
        ? 5
        : (feedWidth >= 1150
              ? 4
              : (feedWidth >= 820 ? 3 : (feedWidth >= 560 ? 2 : 1)));

    return Scaffold(
      appBar: AppBar(
        title: const Text("ArxivPocket"),
        actions: useRail
            ? null
            : [
          // SETTINGS
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),

          // BOOKMARKS
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookmarksPage(
                    downloadPaper: downloadPaper,
                    parseAndLaunchURL: parseAndLaunchURL,
                    onSearchQuerySelected: runFeedSearch,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bookmark_border_outlined),
          ),

          // PAPER NOTES
          IconButton(
            onPressed: () {
              openPaperNotes();
            },
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),

          // CHAT WITH AI
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AIChatPage(paperData: null),
                ),
              );
            },
            icon: const Icon(Icons.auto_awesome_outlined),
          ),

          const SizedBox(width: 10.0),
        ],
      ),
      body: Row(
        children: [
          if (useRail) ...[
            _buildNavigationRail(colorScheme),
            VerticalDivider(
              width: 1.0,
              thickness: 1.0,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ],
          Expanded(
            child: Stack(
              children: [
          Listener(
            onPointerSignal: _handlePointerSignal,
            onPointerMove: _handlePointerMove,
            onPointerUp: (_) => _finishPullUpGesture(),
            onPointerCancel: (_) => _finishPullUpGesture(),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ValueListenableBuilder<double>(
                valueListenable: _pullUpOverscrollNotifier,
                builder: (context, overscroll, child) {
                  final targetLift = _pullUpVisualLift(overscroll);
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: targetLift),
                    duration: _isDraggingPullUp
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, lift, innerChild) {
                      return Transform.translate(
                        offset: Offset(0.0, -lift),
                        child: innerChild,
                      );
                    },
                    child: child,
                  );
                },
                child: RefreshIndicator(
                  onRefresh: _handlePullToRefresh,
                  child: CustomScrollView(
                controller: _feedScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780.0),
                            child: SearchBox(
                              searchTermController: searchTermController,
                              searchFunction: search,
                              sortOption: sortOption,
                              onSortOptionChanged: changeSortOption,
                              onCategoriesChanged: setCategories,
                              onClearCategory: clearCategoryFilter,
                              onOpenAdvancedSearch: _openAdvancedSearch,
                              selectedCategories: selectedCategories,
                            ),
                          ),
                        ),
                        if (selectedCategories.isNotEmpty ||
                            _activeAdvancedQuery != null)
                          _buildActiveFilterChips(
                            colorScheme,
                            isWide: feedWidth >= 680,
                          ),
                        if (!isHomeScreenLoading &&
                            homeScreenError == null &&
                            data.isNotEmpty &&
                            latestBatchDate != null &&
                            _hasActiveSearchOrFilter)
                          ValueListenableBuilder<Set<String>>(
                            valueListenable: ReadPapersStore.notifier,
                            builder: (context, readIds, _) =>
                                _buildNewTodayBanner(
                                  colorScheme,
                                  readIds,
                                  latestBatchDate,
                                ),
                          ),
                        if (!_dismissedNoUpdateBanner)
                          Builder(
                            builder: (context) {
                              final reason =
                                  ArxivUpdateSchedule.noAnnouncementReason(
                                    DateTime.now().toUtc(),
                                  );
                              if (reason == null) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                margin: const EdgeInsets.fromLTRB(
                                  12.0,
                                  0.0,
                                  12.0,
                                  8.0,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0,
                                  vertical: 8.0,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 18.0,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: Text(
                                        reason,
                                        style: TextStyle(
                                          fontSize: 13.0,
                                          color:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.close,
                                        size: 18.0,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () =>
                                              _dismissedNoUpdateBanner = true,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        if (!isHomeScreenLoading &&
                            homeScreenError == null &&
                            data.isNotEmpty)
                          _buildFeedStatusBar(colorScheme),
                      ],
                    ),
                  ),
                  if (isHomeScreenLoading)
                    const SliverToBoxAdapter(child: PaperFeedSkeleton())
                  else if (homeScreenError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 160.0,
                          left: 24.0,
                          right: 24.0,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              color: colorScheme.onSurfaceVariant,
                              size: 42.0,
                            ),
                            const SizedBox(height: 12.0),
                            Text(
                              homeScreenError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12.0),
                            TextButton(
                              onPressed: () {
                                search(resetPagination: true);
                              },
                              child: const Text("Try Again"),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (data.isEmpty && !_hasActiveSearchOrFilter)
                    SliverToBoxAdapter(
                      child: _buildCategoryPromptView(colorScheme),
                    )
                  else if (data.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 200.0),
                        child: Center(child: Text("No Results Found!")),
                      ),
                    )
                  else
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: ReadPapersStore.notifier,
                      builder: (context, readIds, _) {
                        final rows = _buildSliverFeedRows(
                          colorScheme,
                          readIds,
                          latestBatchDate,
                          columns,
                        );
                        return SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) => rows[i],
                        );
                      },
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
                ],
              ),
            ),
          ),
          ),
          ),
          _buildPullUpOverlay(colorScheme),
        ],
      ),
          ),
        ],
      ),
    );
  }
}
