import 'package:arxiv/models/paper.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Singleton store for bookmarked papers, backed by a [ValueNotifier] so
/// cards read bookmark state synchronously without per-card Hive I/O.
class BookmarksStore {
  BookmarksStore._();

  static final BookmarksStore _instance = BookmarksStore._();
  factory BookmarksStore() => _instance;

  static const boxName = "bookmarks";
  static const _listKey = "bookmarks";

  static final ValueNotifier<Set<String>> notifier =
      ValueNotifier<Set<String>>(<String>{});

  static bool _loaded = false;
  static Future<void>? _loadFuture;

  Future<Box> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loadFuture ??= _loadIds();
    await _loadFuture;
  }

  Future<void> _loadIds() async {
    try {
      final box = await _openBox();
      final raw = box.get(_listKey);
      final papers =
          raw is List ? raw.whereType<Paper>().toList() : <Paper>[];
      notifier.value = Set<String>.unmodifiable(papers.map((p) => p.id));
      _loaded = true;
    } catch (_) {
      _loaded = true;
    } finally {
      _loadFuture = null;
    }
  }

  bool isBookmarked(String paperId) => notifier.value.contains(paperId);

  Future<List<Paper>> loadBookmarks() async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    final papers =
        raw is List ? raw.whereType<Paper>().toList() : <Paper>[];
    notifier.value = Set<String>.unmodifiable(papers.map((p) => p.id));
    _loaded = true;
    return papers;
  }

  Future<void> ensureBookmarked(Paper paper) async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    final bookmarks =
        raw is List ? raw.whereType<Paper>().toList() : <Paper>[];
    if (!bookmarks.any((b) => b.id == paper.id)) {
      bookmarks.add(paper);
      await box.put(_listKey, bookmarks);
    }
    notifier.value = Set<String>.unmodifiable(bookmarks.map((p) => p.id));
    _loaded = true;
  }

  Future<void> removeBookmark(String paperId) async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    final bookmarks =
        raw is List ? raw.whereType<Paper>().toList() : <Paper>[];
    final next = bookmarks.where((b) => b.id != paperId).toList();
    await box.put(_listKey, next);
    notifier.value = Set<String>.unmodifiable(next.map((p) => p.id));
    _loaded = true;
  }

  Future<void> clearAll() async {
    final box = await _openBox();
    await box.clear();
    notifier.value = const <String>{};
    _loaded = true;
  }
}
