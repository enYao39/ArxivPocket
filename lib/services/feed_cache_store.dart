import 'dart:io';

import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/services/read_papers_store.dart';
import 'package:hive/hive.dart';

class CachedFeed {
  const CachedFeed({
    required this.key,
    required this.cachedAtUtc,
    required this.totalResults,
    required this.papers,
  });

  final String key;
  final DateTime cachedAtUtc;
  final int totalResults;
  final List<Paper> papers;
}

/// Caches category and home browse feeds locally for up to 7 days so
/// repeated opens between arXiv announcements load instantaneously.
class FeedCacheStore {
  FeedCacheStore._();

  static final FeedCacheStore _instance = FeedCacheStore._();
  factory FeedCacheStore() => _instance;

  static const boxName = "feedCacheBox";
  static const retention = Duration(days: 7);
  static const maxPapersPerFeed = 250;

  static String buildKey({
    String? categoryCode,
    List<String> categoryCodes = const [],
    required ArxivSortOption sortOption,
    required bool excludeCrossListed,
  }) {
    final normalized = categoryCodes
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final category = normalized.isNotEmpty
        ? normalized.join(",")
        : (categoryCode?.trim().isNotEmpty == true
              ? categoryCode!.trim()
              : "all");
    return "cat:$category|sort:${sortOption.name}|excl:$excludeCrossListed";
  }

  Future<Box> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  static DateTime? _parsePublishedDate(String publishedAt) {
    final trimmed = publishedAt.trim();
    if (trimmed.isEmpty) return null;
    final datePart = trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
    return DateTime.tryParse(datePart);
  }

  static List<Paper> _pruneOldPapers(
    List<Paper> papers, {
    DateTime? nowUtc,
    Set<String> keepIds = const <String>{},
  }) {
    final cutoff = (nowUtc ?? DateTime.now().toUtc()).subtract(retention);
    final cutoffDay = DateTime.utc(cutoff.year, cutoff.month, cutoff.day);

    final filtered = <Paper>[];
    final seen = <String>{};

    for (final paper in papers) {
      final normId = ReadPapersStore.normalizeId(paper.id);
      if (normId.isEmpty || !seen.add(normId)) continue;

      if (!keepIds.contains(normId)) {
        final published = _parsePublishedDate(paper.publishedAt);
        if (published != null && published.isBefore(cutoffDay)) {
          continue;
        }
      }
      filtered.add(paper);
      if (filtered.length >= maxPapersPerFeed) break;
    }

    return filtered;
  }

  Future<CachedFeed?> load(String key, {DateTime? nowUtc}) async {
    try {
      final box = await _openBox();
      final raw = box.get(key);
      if (raw is! Map) return null;

      final cachedAt = DateTime.tryParse(
        raw["cachedAtUtc"]?.toString() ?? "",
      );
      if (cachedAt == null) return null;

      final currentUtc = nowUtc ?? DateTime.now().toUtc();
      if (currentUtc.difference(cachedAt.toUtc()) > retention) {
        await box.delete(key);
        return null;
      }

      final rawPapers = raw["papers"];
      if (rawPapers is! List) return null;

      final papers = rawPapers.whereType<Paper>().toList();
      final pruned = _pruneOldPapers(papers, nowUtc: currentUtc);
      if (pruned.isEmpty) {
        await box.delete(key);
        return null;
      }

      final totalResults = raw["totalResults"] is int
          ? raw["totalResults"] as int
          : int.tryParse(raw["totalResults"]?.toString() ?? "") ??
                pruned.length;

      return CachedFeed(
        key: key,
        cachedAtUtc: cachedAt.toUtc(),
        totalResults: totalResults,
        papers: pruned,
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads a cached feed for [categoryCodes]. If the exact combined key is
  /// missing and multiple categories are selected, merges cached single-category
  /// feeds when all of them are locally available.
  Future<CachedFeed?> loadForCategories({
    required List<String> categoryCodes,
    required ArxivSortOption sortOption,
    required bool excludeCrossListed,
    DateTime? nowUtc,
  }) async {
    final normalized = categoryCodes
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalized.isEmpty) return null;

    final exactKey = buildKey(
      categoryCodes: normalized,
      sortOption: sortOption,
      excludeCrossListed: excludeCrossListed,
    );
    final exact = await load(exactKey, nowUtc: nowUtc);
    if (exact != null) return exact;

    if (normalized.length > 1) {
      final parts = <CachedFeed>[];
      for (final code in normalized) {
        final singleKey = buildKey(
          categoryCode: code,
          sortOption: sortOption,
          excludeCrossListed: excludeCrossListed,
        );
        final single = await load(singleKey, nowUtc: nowUtc);
        if (single == null) return null;
        parts.add(single);
      }

      final mergedPapers = <Paper>[];
      final seen = <String>{};
      var oldestCachedAt = parts.first.cachedAtUtc;
      var totalResults = 0;

      for (final part in parts) {
        if (part.cachedAtUtc.isBefore(oldestCachedAt)) {
          oldestCachedAt = part.cachedAtUtc;
        }
        totalResults += part.totalResults;
        for (final paper in part.papers) {
          final normId = ReadPapersStore.normalizeId(paper.id);
          if (normId.isNotEmpty && seen.add(normId)) {
            mergedPapers.add(paper);
          }
        }
      }

      mergedPapers.sort((a, b) {
        switch (sortOption) {
          case ArxivSortOption.oldest:
            final dateCmp = a.publishedAt.compareTo(b.publishedAt);
            return dateCmp != 0 ? dateCmp : a.id.compareTo(b.id);
          case ArxivSortOption.recentlyUpdated:
            final updCmp = b.updatedAt.compareTo(a.updatedAt);
            return updCmp != 0 ? updCmp : b.id.compareTo(a.id);
          case ArxivSortOption.newest:
          case ArxivSortOption.relevance:
            final dateCmp = b.publishedAt.compareTo(a.publishedAt);
            return dateCmp != 0 ? dateCmp : b.id.compareTo(a.id);
        }
      });

      final pruned = _pruneOldPapers(mergedPapers, nowUtc: nowUtc);
      if (pruned.isEmpty) return null;

      return CachedFeed(
        key: exactKey,
        cachedAtUtc: oldestCachedAt,
        totalResults: totalResults,
        papers: pruned,
      );
    }

    return null;
  }

  Future<void> save(
    String key, {
    required List<Paper> papers,
    required int totalResults,
    required DateTime cachedAtUtc,
  }) async {
    try {
      final box = await _openBox();
      final keepIds = papers
          .map((p) => ReadPapersStore.normalizeId(p.id))
          .where((id) => id.isNotEmpty)
          .toSet();
      final pruned = _pruneOldPapers(
        papers,
        nowUtc: cachedAtUtc,
        keepIds: keepIds,
      );

      await box.put(key, {
        "cachedAtUtc": cachedAtUtc.toUtc().toIso8601String(),
        "totalResults": totalResults,
        "papers": pruned,
      });
    } catch (_) {
      // Ignore cache write errors so feed remains usable.
    }
  }

  Future<CachedFeed> mergeFreshPage(
    String key, {
    required List<Paper> freshPapers,
    required int totalResults,
    required DateTime fetchedAtUtc,
  }) async {
    final existing = await load(key, nowUtc: fetchedAtUtc);
    final freshIds = freshPapers
        .map((p) => ReadPapersStore.normalizeId(p.id))
        .where((id) => id.isNotEmpty)
        .toSet();

    final combined = <Paper>[
      ...freshPapers,
      if (existing != null) ...existing.papers,
    ];
    final pruned = _pruneOldPapers(
      combined,
      nowUtc: fetchedAtUtc,
      keepIds: freshIds,
    );

    await save(
      key,
      papers: pruned,
      totalResults: totalResults,
      cachedAtUtc: fetchedAtUtc,
    );

    return CachedFeed(
      key: key,
      cachedAtUtc: fetchedAtUtc,
      totalResults: totalResults,
      papers: pruned,
    );
  }

  Future<void> appendPage(
    String key, {
    required List<Paper> morePapers,
    required int totalResults,
  }) async {
    if (morePapers.isEmpty) return;
    final nowUtc = DateTime.now().toUtc();
    final existing = await load(key, nowUtc: nowUtc);
    if (existing == null) {
      await save(
        key,
        papers: morePapers,
        totalResults: totalResults,
        cachedAtUtc: nowUtc,
      );
      return;
    }

    final combined = <Paper>[...existing.papers, ...morePapers];
    final pruned = _pruneOldPapers(combined, nowUtc: nowUtc);
    await save(
      key,
      papers: pruned,
      totalResults: totalResults > 0 ? totalResults : existing.totalResults,
      cachedAtUtc: existing.cachedAtUtc,
    );
  }

  /// Returns all unique papers currently stored across 7-day feed caches.
  Future<List<Paper>> loadAllCachedPapers({DateTime? nowUtc}) async {
    try {
      final box = await _openBox();
      final currentUtc = nowUtc ?? DateTime.now().toUtc();
      final seen = <String>{};
      final papers = <Paper>[];

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final cachedAt = DateTime.tryParse(
          raw["cachedAtUtc"]?.toString() ?? "",
        );
        if (cachedAt == null ||
            currentUtc.difference(cachedAt.toUtc()) > retention) {
          continue;
        }
        final rawPapers = raw["papers"];
        if (rawPapers is! List) continue;
        for (final paper in _pruneOldPapers(
          rawPapers.whereType<Paper>().toList(),
          nowUtc: currentUtc,
        )) {
          final normId = ReadPapersStore.normalizeId(paper.id);
          if (normId.isNotEmpty && seen.add(normId)) {
            papers.add(paper);
          }
        }
      }
      return papers;
    } catch (_) {
      return const [];
    }
  }

  Future<({int feedCount, int bytes})> getStorageStats() async {
    try {
      final box = await _openBox();
      final path = box.path;
      final bytes = path != null && File(path).existsSync()
          ? File(path).lengthSync()
          : 0;
      return (feedCount: box.length, bytes: bytes);
    } catch (_) {
      return (feedCount: 0, bytes: 0);
    }
  }

  Future<void> clearAll() async {
    final box = await _openBox();
    await box.clear();
  }
}
