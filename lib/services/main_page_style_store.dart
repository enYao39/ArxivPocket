import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/author_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class MainPageStyleSettings {
  const MainPageStyleSettings({
    this.limitAuthors = true,
    this.maxAuthors = defaultMaxAuthors,
    this.sectorSize = defaultSectorSize,
    this.restoreLastSession = true,
    this.restoreSearchFilter = false,
    this.restoreFeedPosition = false,
    this.excludeCrossListed = false,
  });

  static const defaultMaxAuthors = 3;
  static const defaultSectorSize = 25;

  final bool limitAuthors;
  final int maxAuthors;
  final int sectorSize;
  final bool restoreLastSession;
  final bool restoreSearchFilter;
  final bool restoreFeedPosition;
  final bool excludeCrossListed;

  MainPageStyleSettings copyWith({
    bool? limitAuthors,
    int? maxAuthors,
    int? sectorSize,
    bool? restoreLastSession,
    bool? restoreSearchFilter,
    bool? restoreFeedPosition,
    bool? excludeCrossListed,
  }) {
    return MainPageStyleSettings(
      limitAuthors: limitAuthors ?? this.limitAuthors,
      maxAuthors: maxAuthors ?? this.maxAuthors,
      sectorSize: sectorSize ?? this.sectorSize,
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
    this.categoryCodes = const [],
    this.sortOption = ArxivSortOption.newest,
    this.startPagination = 0,
    this.pageSize = 25,
    this.visibleCount = 25,
    this.scrollOffset = 0.0,
  });

  final String query;
  final String? categoryCode;
  final List<String> categoryCodes;
  final ArxivSortOption sortOption;
  final int startPagination;
  final int pageSize;
  final int visibleCount;
  final double scrollOffset;

  List<String> get effectiveCategoryCodes {
    if (categoryCodes.isNotEmpty) return categoryCodes;
    if (categoryCode != null && categoryCode!.trim().isNotEmpty) {
      return [categoryCode!.trim()];
    }
    return const [];
  }
}

class MainPageStyleStore {
  static const boxName = "mainPageStyleBox";
  static const limitAuthorsKey = "limitAuthors";
  static const maxAuthorsKey = "maxAuthors";
  static const sectorSizeKey = "sectorSize";
  static const restoreLastSessionKey = "restoreLastSession";
  static const restoreSearchFilterKey = "restoreSearchFilter";
  static const restoreFeedPositionKey = "restoreFeedPosition";
  static const excludeCrossListedKey = "excludeCrossListed";
  static const lastQueryKey = "lastQuery";
  static const lastCategoryCodeKey = "lastCategoryCode";
  static const lastCategoryCodesKey = "lastCategoryCodes";
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
    final storedSectorSize = box.get(sectorSizeKey);
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
      sectorSize: storedSectorSize is int && storedSectorSize > 0
          ? storedSectorSize
          : MainPageStyleSettings.defaultSectorSize,
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
    await box.put(sectorSizeKey, settings.sectorSize);
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
    final rawCategoryCodes = box.get(lastCategoryCodesKey);
    final categoryCodes = rawCategoryCodes is List
        ? rawCategoryCodes
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : (categoryCode != null && categoryCode.isNotEmpty
              ? [categoryCode]
              : <String>[]);
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

    final resolvedPageSize = pageSize is int && pageSize > 0 ? pageSize : 25;
    return LastFeedState(
      query: query,
      categoryCode: categoryCodes.isNotEmpty ? categoryCodes.first : null,
      categoryCodes: categoryCodes,
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
    final codes = state.effectiveCategoryCodes;
    final box = await Hive.openBox(boxName);
    await box.put(lastQueryKey, state.query);
    await box.put(lastCategoryCodeKey, codes.isNotEmpty ? codes.first : "");
    await box.put(lastCategoryCodesKey, codes);
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
