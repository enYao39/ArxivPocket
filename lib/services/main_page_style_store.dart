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
  });

  static const defaultMaxAuthors = 3;

  final bool limitAuthors;
  final int maxAuthors;
  final bool restoreLastSession;
  final bool restoreSearchFilter;

  MainPageStyleSettings copyWith({
    bool? limitAuthors,
    int? maxAuthors,
    bool? restoreLastSession,
    bool? restoreSearchFilter,
  }) {
    return MainPageStyleSettings(
      limitAuthors: limitAuthors ?? this.limitAuthors,
      maxAuthors: maxAuthors ?? this.maxAuthors,
      restoreLastSession: restoreLastSession ?? this.restoreLastSession,
      restoreSearchFilter: restoreSearchFilter ?? this.restoreSearchFilter,
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
  });

  final String query;
  final String? categoryCode;
  final ArxivSortOption sortOption;
  final int startPagination;
  final int pageSize;
}

class MainPageStyleStore {
  static const boxName = "mainPageStyleBox";
  static const limitAuthorsKey = "limitAuthors";
  static const maxAuthorsKey = "maxAuthors";
  static const restoreLastSessionKey = "restoreLastSession";
  static const restoreSearchFilterKey = "restoreSearchFilter";
  static const lastQueryKey = "lastQuery";
  static const lastCategoryCodeKey = "lastCategoryCode";
  static const lastSortOptionKey = "lastSortOption";
  static const lastStartPaginationKey = "lastStartPagination";
  static const lastPageSizeKey = "lastPageSize";

  static final ValueNotifier<MainPageStyleSettings> notifier =
      ValueNotifier<MainPageStyleSettings>(const MainPageStyleSettings());

  static bool _hasLoaded = false;

  Future<MainPageStyleSettings> load() async {
    final box = await Hive.openBox(boxName);
    final storedLimit = box.get(limitAuthorsKey);
    final storedMax = box.get(maxAuthorsKey);
    final storedRestore = box.get(restoreLastSessionKey);
    final storedRestoreSearch = box.get(restoreSearchFilterKey);
    await box.close();

    final settings = MainPageStyleSettings(
      limitAuthors: storedLimit is bool ? storedLimit : true,
      maxAuthors: storedMax is int && storedMax > 0
          ? storedMax
          : MainPageStyleSettings.defaultMaxAuthors,
      restoreLastSession: storedRestore is bool ? storedRestore : true,
      restoreSearchFilter:
          storedRestoreSearch is bool ? storedRestoreSearch : false,
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
    await box.close();
  }

  Future<LastFeedState> loadLastFeedState() async {
    final box = await Hive.openBox(boxName);
    final query = box.get(lastQueryKey)?.toString() ?? "";
    final categoryCode = box.get(lastCategoryCodeKey)?.toString();
    final sortName = box.get(lastSortOptionKey)?.toString();
    final startPagination = box.get(lastStartPaginationKey);
    final pageSize = box.get(lastPageSizeKey);
    await box.close();

    final sortOption = ArxivSortOption.values.firstWhere(
      (option) => option.name == sortName,
      orElse: () => ArxivSortOption.newest,
    );

    return LastFeedState(
      query: query,
      categoryCode: categoryCode != null && categoryCode.isNotEmpty
          ? categoryCode
          : null,
      sortOption: sortOption,
      startPagination: startPagination is int && startPagination >= 0
          ? startPagination
          : 0,
      pageSize: pageSize is int && pageSize > 0 ? pageSize : 30,
    );
  }

  Future<void> saveLastFeedState(LastFeedState state) async {
    final box = await Hive.openBox(boxName);
    await box.put(lastQueryKey, state.query);
    await box.put(lastCategoryCodeKey, state.categoryCode ?? "");
    await box.put(lastSortOptionKey, state.sortOption.name);
    await box.put(lastStartPaginationKey, state.startPagination);
    await box.put(lastPageSizeKey, state.pageSize);
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
