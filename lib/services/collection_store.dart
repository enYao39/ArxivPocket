import 'dart:convert';

import 'package:arxiv/models/paper.dart';
import 'package:arxiv/models/paper_note.dart';
import 'package:hive/hive.dart';

class CollectionFolder {
  const CollectionFolder({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {"id": id, "name": name};

  factory CollectionFolder.fromJson(Map<String, dynamic> json) {
    return CollectionFolder(
      id: (json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
    );
  }

  CollectionFolder copyWith({String? id, String? name}) {
    return CollectionFolder(id: id ?? this.id, name: name ?? this.name);
  }
}

class CollectionStore {
  static const String _boxName = "bookmark_collections";
  static const String _foldersKey = "collection_folders_v1";
  static const String _paperFoldersKey = "collection_paper_folders_v1";

  Future<Box> _openBox() => Hive.openBox(_boxName);

  Future<List<CollectionFolder>> loadFolders() async {
    final box = await _openBox();
    final raw = box.get(_foldersKey);
    if (raw is! String || raw.trim().isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => CollectionFolder.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((folder) => folder.id.isNotEmpty && folder.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveFolders(List<CollectionFolder> folders) async {
    final box = await _openBox();
    await box.put(
      _foldersKey,
      json.encode(folders.map((f) => f.toJson()).toList()),
    );
  }

  Future<CollectionFolder> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError("Folder name cannot be empty.");
    }
    final folders = await loadFolders();
    final id = "folder_${DateTime.now().microsecondsSinceEpoch}";
    final created = CollectionFolder(id: id, name: trimmed);
    folders.add(created);
    await _saveFolders(folders);
    return created;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final folders = await loadFolders();
    final updated = folders
        .map(
          (folder) =>
              folder.id == folderId ? folder.copyWith(name: trimmed) : folder,
        )
        .toList();
    await _saveFolders(updated);
  }

  Future<void> deleteFolder(String folderId) async {
    final folders = await loadFolders();
    folders.removeWhere((folder) => folder.id == folderId);
    await _saveFolders(folders);

    final map = await loadPaperFolderMap();
    var changed = false;
    final updatedMap = <String, List<String>>{};
    for (final entry in map.entries) {
      final next = entry.value.where((id) => id != folderId).toList();
      if (next.length != entry.value.length) {
        changed = true;
      }
      if (next.isNotEmpty) {
        updatedMap[entry.key] = next;
      }
    }
    if (changed) {
      await _savePaperFolderMap(updatedMap);
    }
  }

  Future<Map<String, List<String>>> loadPaperFolderMap() async {
    final box = await _openBox();
    final raw = box.get(_paperFoldersKey);
    if (raw is! String || raw.trim().isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          final ids = value
              .map((e) => e.toString())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          if (ids.isNotEmpty) {
            result[key] = ids;
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePaperFolderMap(Map<String, List<String>> map) async {
    final box = await _openBox();
    await box.put(_paperFoldersKey, json.encode(map));
  }

  Future<List<String>> foldersForPaper(String paperId) async {
    final map = await loadPaperFolderMap();
    return map[paperId] ?? const [];
  }

  Future<void> setPaperFolders(String paperId, List<String> folderIds) async {
    final map = await loadPaperFolderMap();
    final cleaned = folderIds.where((id) => id.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) {
      map.remove(paperId);
    } else {
      map[paperId] = cleaned;
    }
    await _savePaperFolderMap(map);
  }

  Future<void> togglePaperInFolder(String paperId, String folderId) async {
    final map = await loadPaperFolderMap();
    final current = List<String>.from(map[paperId] ?? const []);
    if (current.contains(folderId)) {
      current.remove(folderId);
    } else {
      current.add(folderId);
    }
    if (current.isEmpty) {
      map.remove(paperId);
    } else {
      map[paperId] = current;
    }
    await _savePaperFolderMap(map);
  }

  Future<void> removePaperFromAllFolders(String paperId) async {
    final map = await loadPaperFolderMap();
    if (map.remove(paperId) != null) {
      await _savePaperFolderMap(map);
    }
  }

  static List<Paper> filterPapers({
    required List<Paper> papers,
    required Map<String, List<String>> paperFolderMap,
    String? selectedFolderId,
    bool unsortedOnly = false,
  }) {
    if (unsortedOnly) {
      return papers
          .where((p) => (paperFolderMap[p.id] ?? const []).isEmpty)
          .toList();
    }
    if (selectedFolderId != null) {
      return papers
          .where(
            (p) => (paperFolderMap[p.id] ?? const []).contains(selectedFolderId),
          )
          .toList();
    }
    return papers;
  }

  static List<PaperNote> filterNotes({
    required List<PaperNote> notes,
    required Map<String, List<String>> paperFolderMap,
    String? selectedFolderId,
    bool unsortedOnly = false,
  }) {
    if (unsortedOnly) {
      return notes
          .where((n) => (paperFolderMap[n.paperId] ?? const []).isEmpty)
          .toList();
    }
    if (selectedFolderId != null) {
      return notes
          .where(
            (n) => (paperFolderMap[n.paperId] ?? const []).contains(
              selectedFolderId,
            ),
          )
          .toList();
    }
    return notes;
  }
}
