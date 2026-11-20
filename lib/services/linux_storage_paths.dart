import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves Linux Hive storage under `getApplicationSupportDirectory()`
/// (`~/.local/share/com.example.arxiv/hive`) so all app data (`hive/`,
/// `pdf_cache/`, and preferences) stays in one directory instead of `~/Documents/`.
class LinuxStoragePaths {
  const LinuxStoragePaths._();

  static const _legacyHiveNames = {
    "apibox",
    "bookmarks",
    "chatthreads",
    "collectionbox",
    "feedcachebox",
    "mainpagestylebox",
    "papernotes",
    "pdfcachebox",
    "readpapersbox",
    "speechratebox",
    "toolsbox",
  };

  static Future<Directory> hiveDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory("${supportDir.path}/hive");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Moves known legacy Hive `.hive`/`.lock` files out of `~/Documents` into
  /// `~/.local/share/com.example.arxiv/hive` if they don't already exist there.
  static Future<void> migrateLegacyData() async {
    if (kIsWeb || !Platform.isLinux) return;

    try {
      final targetHive = await hiveDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      if (!docsDir.existsSync() || docsDir.path == targetHive.path) return;

      for (final entity in docsDir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : "";
        final dotIdx = name.lastIndexOf(".");
        if (dotIdx <= 0) continue;
        final stem = name.substring(0, dotIdx).toLowerCase();
        final ext = name.substring(dotIdx).toLowerCase();
        if ((ext == ".hive" || ext == ".lock") &&
            _legacyHiveNames.contains(stem)) {
          final dest = File("${targetHive.path}/$name");
          if (!dest.existsSync()) {
            entity.renameSync(dest.path);
          }
        }
      }
    } catch (_) {
      // Best-effort migration; continue even if a file is locked or missing.
    }
  }
}
