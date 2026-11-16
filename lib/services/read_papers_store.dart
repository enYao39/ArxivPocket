import 'dart:io';

import 'package:arxiv/models/paper.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Persists which arXiv paper IDs have been marked as read.
class ReadPapersStore {
  ReadPapersStore._();

  static final ReadPapersStore _instance = ReadPapersStore._();
  factory ReadPapersStore() => _instance;

  static const boxName = "readPapersBox";

  static final ValueNotifier<Set<String>> notifier =
      ValueNotifier<Set<String>>(<String>{});

  static bool _loaded = false;
  static Future<void>? _loadFuture;

  /// Strips trailing version suffixes (e.g. `v1`, `v2`) so read state
  /// persists across minor arXiv paper revisions.
  static String normalizeId(String paperId) {
    final trimmed = paperId.trim();
    return trimmed.replaceFirst(RegExp(r'v\d+$'), '');
  }

  Future<Box> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loadFuture ??= _loadFromBox();
    await _loadFuture;
  }

  Future<void> _loadFromBox() async {
    try {
      final box = await _openBox();
      final keysToDelete = <dynamic>[];
      final loadedIds = <String>{};

      for (final key in box.keys) {
        final id = normalizeId(key.toString());
        if (id.isEmpty) {
          keysToDelete.add(key);
          continue;
        }
        loadedIds.add(id);
      }

      if (keysToDelete.isNotEmpty) {
        await box.deleteAll(keysToDelete);
      }

      notifier.value = Set<String>.unmodifiable(loadedIds);
      _loaded = true;
    } catch (_) {
      _loaded = true;
    } finally {
      _loadFuture = null;
    }
  }

  bool isRead(String paperId) {
    final normalized = normalizeId(paperId);
    if (normalized.isEmpty) return false;
    return notifier.value.contains(normalized);
  }

  Future<void> setRead(String paperId, bool read, {Paper? paper}) async {
    await ensureLoaded();
    final normalized = normalizeId(paperId);
    if (normalized.isEmpty) return;

    final current = notifier.value;
    final alreadyRead = current.contains(normalized);
    if (!read && !alreadyRead) return;

    final next = Set<String>.from(current);
    final box = await _openBox();
    if (read) {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (alreadyRead && paper == null) {
        return;
      }
      final existing = box.get(normalized);
      final existingPaper = existing is Map ? existing["paper"] : null;
      final resolvedPaper = paper ?? (existingPaper is Paper ? existingPaper : null);
      if (alreadyRead && resolvedPaper == existingPaper) {
        return;
      }
      next.add(normalized);
      await box.put(normalized, {
        "readAt": nowIso,
        if (resolvedPaper != null) "paper": resolvedPaper,
      });
    } else {
      next.remove(normalized);
      await box.delete(normalized);
    }
    notifier.value = Set<String>.unmodifiable(next);
  }

  Future<void> markRead(String paperId, {Paper? paper}) =>
      setRead(paperId, true, paper: paper);

  Future<void> markUnread(String paperId) => setRead(paperId, false);

  Future<bool> toggleRead(String paperId, {Paper? paper}) async {
    await ensureLoaded();
    final nextRead = !isRead(paperId);
    await setRead(paperId, nextRead, paper: paper);
    return nextRead;
  }

  Future<List<({String id, DateTime? readAt, Paper? paper})>>
  loadReadHistory() async {
    await ensureLoaded();
    final box = await _openBox();
    final entries = <({String id, DateTime? readAt, Paper? paper})>[];
    for (final key in box.keys) {
      final id = normalizeId(key.toString());
      if (id.isEmpty) continue;
      final raw = box.get(key);
      DateTime? readAt;
      Paper? paper;
      if (raw is String) {
        readAt = DateTime.tryParse(raw)?.toUtc();
      } else if (raw is Map) {
        readAt = DateTime.tryParse(raw["readAt"]?.toString() ?? "")?.toUtc();
        final rawPaper = raw["paper"];
        if (rawPaper is Paper) {
          paper = rawPaper;
        }
      }
      entries.add((id: id, readAt: readAt, paper: paper));
    }
    entries.sort((a, b) {
      final aTime = a.readAt;
      final bTime = b.readAt;
      if (aTime != null && bTime != null) {
        return bTime.compareTo(aTime);
      }
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return b.id.compareTo(a.id);
    });
    return entries;
  }

  Future<Map<String, DateTime>> loadReadTimestamps() async {
    final history = await loadReadHistory();
    return {
      for (final item in history)
        if (item.readAt != null) item.id: item.readAt!,
    };
  }

  Future<({int count, int bytes})> getStorageStats() async {
    await ensureLoaded();
    try {
      final box = await _openBox();
      final count = box.length;
      final path = box.path;
      final bytes = path != null && File(path).existsSync()
          ? File(path).lengthSync()
          : 0;
      return (count: count, bytes: bytes);
    } catch (_) {
      return (count: notifier.value.length, bytes: 0);
    }
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    final box = await _openBox();
    await box.clear();
    notifier.value = const <String>{};
  }
}
