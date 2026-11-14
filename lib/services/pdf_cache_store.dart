import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

class PdfCacheStore {
  static const String _boxName = "pdf_cache_settings";
  static const String _maxCacheMbKey = "max_cache_mb";
  static const int defaultMaxCacheMb = 500;
  static const List<int> limitOptionsMb = [100, 250, 500, 1000, 2000, 0];

  Future<Box> _openBox() => Hive.openBox(_boxName);

  Future<int> loadMaxCacheMb() async {
    final box = await _openBox();
    final value = box.get(_maxCacheMbKey);
    if (value is int && value >= 0) {
      return value;
    }
    return defaultMaxCacheMb;
  }

  Future<void> saveMaxCacheMb(int maxMb) async {
    final box = await _openBox();
    await box.put(_maxCacheMbKey, maxMb < 0 ? 0 : maxMb);
    await enforceLimit(maxBytes: maxMb <= 0 ? 0 : maxMb * 1024 * 1024);
  }

  Future<Directory> getCacheDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/pdf_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<String> cachePathForId(String sanitizedId) async {
    final dir = await getCacheDirectory();
    return '${dir.path}/$sanitizedId.pdf';
  }

  Future<void> touchCachedFile(File file) async {
    try {
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      }
    } catch (_) {}
  }

  Future<({int fileCount, int totalBytes})> getCacheStats({
    Directory? cacheDir,
  }) async {
    final dir = cacheDir ?? await getCacheDirectory();
    if (!await dir.exists()) {
      return (fileCount: 0, totalBytes: 0);
    }

    var count = 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.pdf')) {
        count++;
        total += await entity.length();
      }
    }
    return (fileCount: count, totalBytes: total);
  }

  Future<void> clearCache({Directory? cacheDir}) async {
    final dir = cacheDir ?? await getCacheDirectory();
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> enforceLimit({
    int? maxBytes,
    Directory? cacheDir,
    String? protectedPath,
  }) async {
    final int resolvedLimit;
    if (maxBytes != null) {
      resolvedLimit = maxBytes;
    } else {
      final mb = await loadMaxCacheMb();
      resolvedLimit = mb <= 0 ? 0 : mb * 1024 * 1024;
    }
    if (resolvedLimit <= 0) return;

    final dir = cacheDir ?? await getCacheDirectory();
    if (!await dir.exists()) return;

    final entries = <({File file, int size, DateTime modified})>[];
    var totalBytes = 0;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.pdf')) {
        final stat = await entity.stat();
        totalBytes += stat.size;
        entries.add((file: entity, size: stat.size, modified: stat.modified));
      }
    }

    if (totalBytes <= resolvedLimit) return;

    // Evict oldest files first (least recently cached/opened).
    entries.sort((a, b) => a.modified.compareTo(b.modified));

    for (final entry in entries) {
      if (totalBytes <= resolvedLimit) break;
      if (protectedPath != null && entry.file.path == protectedPath) {
        continue;
      }
      try {
        await entry.file.delete();
        totalBytes -= entry.size;
      } catch (_) {}
    }
  }

  static String formatLimitLabel(int mb) {
    if (mb <= 0) return "Unlimited";
    if (mb >= 1000 && mb % 1000 == 0) {
      return "${mb ~/ 1000} GB";
    }
    return "$mb MB";
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB";
    }
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }
}
