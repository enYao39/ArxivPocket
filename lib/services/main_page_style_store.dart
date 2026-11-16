import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/author_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class MainPageStyleSettings {
  const MainPageStyleSettings({
    this.limitAuthors = true,
    this.maxAuthors = defaultMaxAuthors,
    this.restoreLastSession = true,
    this.restoreSearchFilter = false,
    this.restoreFeedPosition = false,
    this.excludeCrossListed = false,
  });

  static const defaultMaxAuthors = 3;

  final bool limitAuthors;
  final int maxAuthors;
  final bool restoreLastSession;
  final bool restoreSearchFilter;
  final bool restoreFeedPosition;
  final bool excludeCrossListed;

  MainPageStyleSettings copyWith({
    bool? limitAuthors,
    int? maxAuthors,
    bool? restoreLastSession,
    bool? restoreSearchFilter,
    bool? restoreFeedPosition,
    bool? excludeCrossListed,
  }) {
    return MainPageStyleSettings(
      limitAuthors: limitAuthors ?? this.limitAuthors,
      maxAuthors: maxAuthors ?? this.maxAuthors,
      restoreLastSession: restoreLastSession ?? this.restoreLastSession,
      restoreSearchFilter: restoreSearchFilter ?? this.restoreSearchFilter,
      restoreFeedPosition: restoreFeedPosition ?? this.restoreFeedPosition,
      excludeCrossListed: excludeCrossListed ?? this.excludeCrossListed,
    );
  }
}

class LastFeedState {
  const LastFeedState({
    this.query = "",
    this.categoryCode,
    this.sortOption = ArxivSortOption.newest,
    this.startPagination = 0,
    this.pageSize = 30,
    this.visibleCount = 30,
    this.scrollOffset = 0.0,
  });

  final String query;
  final String? categoryCode;
  final ArxivSortOption sortOption;
  final int startPagination;
  final int pageSize;
  final int visibleCount;
  final double scrollOffset;
}

class MainPageStyleStore {
  static const boxName = "mainPageStyleBox";
  static const limitAuthorsKey = "limitAuthors";
  static const maxAuthorsKey = "maxAuthors";
  static const restoreLastSessionKey = "restoreLastSession";
  static const restoreSearchFilterKey = "restoreSearchFilter";
  static const restoreFeedPositionKey = "restoreFeedPosition";
  static const excludeCrossListedKey = "excludeCrossListed";
  static const lastQueryKey = "lastQuery";
  static const lastCategoryCodeKey = "lastCategoryCode";
  static const lastSortOptionKey = "lastSortOption";
  static const lastStartPaginationKey = "lastStartPagination";
  static const lastPageSizeKey = "lastPageSize";
  static const lastVisibleCountKey = "lastVisibleCount";
  static const lastScrollOffsetKey = "lastScrollOffset";

  static final ValueNotifier<MainPageStyleSettings> notifier =
      ValueNotifier<MainPageStyleSettings>(const MainPageStyleSettings());

  static bool _hasLoaded = false;

  Future<MainPageStyleSettings> load() async {
    final box = await Hive.openBox(boxName);
    final storedLimit = box.get(limitAuthorsKey);
    final storedMax = box.get(maxAuthorsKey);
    final storedRestore = box.get(restoreLastSessionKey);
    final storedRestoreSearch = box.get(restoreSearchFilterKey);
    final storedRestoreFeedPos = box.get(restoreFeedPositionKey);
    final storedExcludeCross = box.get(excludeCrossListedKey);
    await box.close();

    final settings = MainPageStyleSettings(
      limitAuthors: storedLimit is bool ? storedLimit : true,
      maxAuthors: storedMax is int && storedMax > 0
          ? storedMax
          : MainPageStyleSettings.defaultMaxAuthors,
      restoreLastSession: storedRestore is bool ? storedRestore : true,
      restoreSearchFilter:
          storedRestoreSearch is bool ? storedRestoreSearch : false,
      restoreFeedPosition:
          storedRestoreFeedPos is bool ? storedRestoreFeedPos : false,
      excludeCrossListed:
          storedExcludeCross is bool ? storedExcludeCross : false,
    );
    _hasLoaded = true;
    notifier.value = settings;
    return settings;
  }

  Future<void> ensureLoaded() async {
    if (_hasLoaded) return;
    await load();
  }

  Future<void> save(MainPageStyleSettings settings) async {
    notifier.value = settings;
    _hasLoaded = true;
    final box = await Hive.openBox(boxName);
    await box.put(limitAuthorsKey, settings.limitAuthors);
    await box.put(maxAuthorsKey, settings.maxAuthors);
    await box.put(restoreLastSessionKey, settings.restoreLastSession);
    await box.put(restoreSearchFilterKey, settings.restoreSearchFilter);
    await box.put(restoreFeedPositionKey, settings.restoreFeedPosition);
    await box.put(excludeCrossListedKey, settings.excludeCrossListed);
    await box.close();
  }

  Future<LastFeedState> loadLastFeedState() async {
    final box = await Hive.openBox(boxName);
    final query = box.get(lastQueryKey)?.toString() ?? "";
    final categoryCode = box.get(lastCategoryCodeKey)?.toString();
    final sortName = box.get(lastSortOptionKey)?.toString();
    final startPagination = box.get(lastStartPaginationKey);
    final pageSize = box.get(lastPageSizeKey);
    final visibleCount = box.get(lastVisibleCountKey);
    final scrollOffset = box.get(lastScrollOffsetKey);
    await box.close();

    final sortOption = ArxivSortOption.values.firstWhere(
      (option) => option.name == sortName,
      orElse: () => ArxivSortOption.newest,
    );

    final resolvedPageSize = pageSize is int && pageSize > 0 ? pageSize : 30;
    return LastFeedState(
      query: query,
      categoryCode: categoryCode != null && categoryCode.isNotEmpty
          ? categoryCode
          : null,
      sortOption: sortOption,
      startPagination: startPagination is int && startPagination >= 0
          ? startPagination
          : 0,
      pageSize: resolvedPageSize,
      visibleCount: visibleCount is int && visibleCount > 0
          ? visibleCount
          : resolvedPageSize,
      scrollOffset: scrollOffset is num && scrollOffset >= 0
          ? scrollOffset.toDouble()
          : 0.0,
    );
  }

  Future<void> saveLastFeedState(LastFeedState state) async {
    final box = await Hive.openBox(boxName);
    await box.put(lastQueryKey, state.query);
    await box.put(lastCategoryCodeKey, state.categoryCode ?? "");
    await box.put(lastSortOptionKey, state.sortOption.name);
    await box.put(lastStartPaginationKey, state.startPagination);
    await box.put(lastPageSizeKey, state.pageSize);
    await box.put(lastVisibleCountKey, state.visibleCount);
    await box.put(lastScrollOffsetKey, state.scrollOffset);
    await box.close();
  }

  static String formatAuthors(Paper paper, MainPageStyleSettings settings) {
    if (!settings.limitAuthors) {
      return paper.authors;
    }

    final authors = AuthorParser.authorsForPaper(paper);
    if (authors.length <= settings.maxAuthors) {
      return paper.authors;
    }

    final visible = authors.take(settings.maxAuthors).join(", ");
    final remaining = authors.length - settings.maxAuthors;
    return "$visible (+$remaining more)";
  }
}
