// ignore_for_file: file_names
import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/advanced_search_sheet.dart';
import 'package:arxiv/components/each_paper_card.dart';
import 'package:arxiv/components/paper_card_skeleton.dart';
import 'package:arxiv/components/search_box.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/services/arxiv_category_parser.dart';
import 'package:arxiv/services/arxiv_update_schedule.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/ai_chat_page.dart';
import 'package:arxiv/pages/bookmarks_page.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/pages/paper_notes_page.dart';
import 'package:arxiv/pages/pdf_viewer.dart';
import 'package:arxiv/pages/settings_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ionicons_plus/ionicons_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var sourceCodeURL = "https://github.com/ScholarXIV/OpenScholarXIV";
  var scholarXivURL = "https://ScholarXIV.com";
  int startPagination = 0;
  int maxContent = 30;
  int paginationGap = 30;
  var pdfBaseURL = "https://arxiv.org/pdf";
  ArxivSortOption sortOption = ArxivSortOption.newest;
  ArxivCategory? selectedCategory;

  var isHomeScreenLoading = true;
  DateTime? _lastFetchedAtUtc;
  bool _dismissedNoUpdateBanner = false;
  TextEditingController searchTermController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();
  int notesRefreshToken = 0;

  var dio = Dio();
  List<Paper> data = [];
  ArxivSearchResult? lastSearchResult;
  String? homeScreenError;
  int _searchRequestSerial = 0;

  bool get _hasActiveSearchOrFilter =>
      selectedCategory != null || searchTermController.text.trim().isNotEmpty;

  void _scrollToTop() {
    if (!_feedScrollController.hasClients) return;
    _feedScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> search({bool? resetPagination}) async {
    final requestSerial = ++_searchRequestSerial;
    if (resetPagination == true) {
      startPagination = 0;
    }
    setState(() {
      isHomeScreenLoading = true;
      homeScreenError = null;
      data = [];
    });

    final rawSearchInput = searchTermController.text.trim();
    MainPageStyleStore().saveLastFeedState(
      LastFeedState(
        query: rawSearchInput,
        categoryCode: selectedCategory?.code,
        sortOption: sortOption,
        startPagination: startPagination,
        pageSize: maxContent,
      ),
    );
    final searchTerm = combineCategoryAndQuery(
      category: selectedCategory,
      query: rawSearchInput,
    );
    late final ArxivSearchResult result;
    if (searchTerm.isEmpty) {
      result = await suggestedPapers();
    } else {
      result = await Arxiv.searchWithMetadata(
        searchTerm,
        page: startPagination,
        pageSize: maxContent,
        sortOption: sortOption,
      );
    }

    if (!mounted || requestSerial != _searchRequestSerial) {
      return;
    }

    setState(() {
      lastSearchResult = result;
      data = result.papers;
      homeScreenError = result.errorMessage;
      isHomeScreenLoading = false;
      _lastFetchedAtUtc =
          result.errorMessage == null ? DateTime.now().toUtc() : null;
    });
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
      await search();
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
    final category = categoryFromSearchInput(query);
    if (category != null) {
      selectedCategory = category;
      searchTermController.clear();
    } else {
      selectedCategory = null;
      searchTermController.text = query;
    }
    await search(resetPagination: true);
    _scrollToTop();
  }

  Future<void> searchCategory(ArxivCategory category) async {
    if (categoryFromSearchInput(searchTermController.text) != null) {
      searchTermController.clear();
    }
    selectedCategory = category;
    await search(resetPagination: true);
    _scrollToTop();
  }

  Future<void> searchCategoryByCode(String code) async {
    final category = categoryByCode(code);
    if (category != null) {
      await searchCategory(category);
      return;
    }
    await runFeedSearch("cat:$code");
  }

  Future<void> clearCategoryFilter() async {
    selectedCategory = null;
    if (categoryFromSearchInput(searchTermController.text) != null) {
      searchTermController.clear();
    }
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
      initialCategory: selectedCategory,
      initialSortOption: sortOption,
      initialPageSize: maxContent,
      onApply: (advancedQuery) async {
        final built = advancedQuery.buildSearchQuery();
        setState(() {
          sortOption = advancedQuery.sortOption;
          maxContent = advancedQuery.pageSize;
          paginationGap = advancedQuery.pageSize;
        });

        final onlyCategory =
            advancedQuery.category != null &&
            built == advancedQuery.category!.query;
        if (onlyCategory) {
          selectedCategory = advancedQuery.category;
          searchTermController.clear();
        } else {
          selectedCategory = null;
          searchTermController.text = built;
        }
        await search(resetPagination: true);
        _scrollToTop();
      },
    );
  }

  Future<ArxivSearchResult> suggestedPapers() async {
    return Arxiv.suggestWithMetadata(
      pageSize: maxContent,
      sortOption: sortOption,
    );
  }

  var paperTitle = "";
  var savePath = "";
  var pdfURL = "";
  dynamic downloadPath = "";

  Future<void> parseAndLaunchURL(String currentURL, String title) async {
    paperTitle = title;

    pdfURL = pdfUrlFor(currentURL);
    var splitURL = pdfURL.split("/");
    var id = splitURL[splitURL.length - 1];
    var urlType = 0;
    if (id.contains(".") == true) {
      urlType = 1;
    } else {
      urlType = 2;
    }

    final Uri parsedURL = Uri.parse(pdfURL);
    savePath = '${(await getTemporaryDirectory()).path}/paper3.pdf';

    if (urlType == 2) {
      var result = await dio.downloadUri(parsedURL, savePath);
      if (result.statusCode != 200) {}
    }

    Navigator.push(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewer(
          paperTitle: paperTitle,
          savePath: savePath,
          pdfURL: pdfURL,
          urlType: urlType,
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
    _initializeAndLoadFeed();
  }

  Future<void> _initializeAndLoadFeed() async {
    final store = MainPageStyleStore();
    final settings = await store.load();
    if (!mounted) return;

    if (settings.restoreLastSession) {
      final lastState = await store.loadLastFeedState();
      if (!mounted) return;
      setState(() {
        searchTermController.text =
            settings.restoreSearchFilter ? lastState.query : "";
        selectedCategory = lastState.categoryCode != null
            ? categoryByCode(lastState.categoryCode!)
            : null;
        sortOption = lastState.sortOption;
        startPagination =
            settings.restoreSearchFilter ? lastState.startPagination : 0;
        maxContent = lastState.pageSize;
        paginationGap = lastState.pageSize;
      });
    }

    await search();
  }

  @override
  void dispose() {
    searchTermController.removeListener(_onSearchTermChanged);
    searchTermController.dispose();
    _feedScrollController.dispose();
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

  Widget _buildPaginationBar(ColorScheme colorScheme) {
    final total = lastSearchResult?.totalResults ?? 0;
    final canGoBack = startPagination >= paginationGap;
    final canGoForward = total > 0
        ? startPagination + data.length < total
        : data.length >= maxContent;

    final rangeStart = startPagination + 1;
    final rangeEnd = startPagination + data.length;
    final totalSuffix = total > 0 ? " of $total" : "";

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: canGoBack
              ? () {
                  startPagination -= paginationGap;
                  search();
                  _scrollToTop();
                }
              : null,
          icon: Icon(
            Ionicons.arrow_back,
            color: canGoBack
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface.withAlpha(64),
            size: 20.0,
          ),
        ),
        Text(
          "$rangeStart–$rangeEnd$totalSuffix",
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        IconButton(
          onPressed: canGoForward
              ? () {
                  startPagination += paginationGap;
                  search();
                  _scrollToTop();
                }
              : null,
          icon: Icon(
            Ionicons.arrow_forward,
            color: canGoForward
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface.withAlpha(64),
            size: 20.0,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("OpenScholarXIV"),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: _handlePullToRefresh,
        child: ListView(
          controller: _feedScrollController,
          children: [
            SearchBox(
              searchTermController: searchTermController,
              searchFunction: search,
              sortOption: sortOption,
              onSortOptionChanged: changeSortOption,
              onCategorySelected: searchCategory,
              onClearCategory: clearCategoryFilter,
              onOpenAdvancedSearch: _openAdvancedSearch,
              selectedCategory: selectedCategory,
            ),
            if (selectedCategory != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 6.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(categoryFilterLabel(selectedCategory!)),
                    selected: true,
                    onDeleted: clearCategoryFilter,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),

            if (!_dismissedNoUpdateBanner)
              Builder(
                builder: (context) {
                  final reason = ArxivUpdateSchedule.noAnnouncementReason(
                    DateTime.now().toUtc(),
                  );
                  if (reason == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 8.0),
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
                              color: colorScheme.onSecondaryContainer,
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
                            setState(() => _dismissedNoUpdateBanner = true);
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

            // Data or Loading
            isHomeScreenLoading == true
                ? const PaperFeedSkeleton()
                : homeScreenError != null
                ? Padding(
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
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
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
                  )
                : data.isNotEmpty
                ? Column(
                    children: data.map((eachPaper) {
                      return EachPaperCard(
                        eachPaper: eachPaper,
                        downloadPaper: downloadPaper,
                        parseAndLaunchURL: parseAndLaunchURL,
                        isBookmarked: false,
                        onCardTap: () => openPaperDetails(eachPaper),
                        onCategoryTap: searchCategoryByCode,
                        notesRefreshToken: notesRefreshToken,
                      );
                    }).toList(),
                  )
                : const Padding(
                    padding: EdgeInsets.only(top: 200.0),
                    child: Center(child: Text("No Results Found!")),
                  ),

            const SizedBox(height: 20.0),

            // Pagination
            if (data.isNotEmpty && _hasActiveSearchOrFilter)
              _buildPaginationBar(colorScheme),

            Container(
              width: 100.0,
              padding: const EdgeInsets.only(top: 200.0, bottom: 40.0),
              child: Center(
                child: Text(
                  "Thank you to arXiv for use of its \nopen access interoperability.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12.0,
                  ),
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: () {
                  launchUrl(Uri.parse(sourceCodeURL));
                },
                child: Text(
                  "View Source Code on GitHub",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.primary, fontSize: 12.0),
                ),
              ),
            ),

            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 5.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Made with 🤍 by ",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12.0,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        launchUrl(Uri.parse(scholarXivURL));
                      },
                      child: Text(
                        "ScholarXIV",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20.0),
          ],
        ),
      ),
    );
  }
}
