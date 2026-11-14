// ignore_for_file: file_names
import 'package:arxiv/components/each_paper_card.dart';
import 'package:arxiv/components/loading_indicator.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({
    super.key,
    required this.downloadPaper,
    required this.parseAndLaunchURL,
    required this.onSearchQuerySelected,
  });

  final Function downloadPaper;
  final Function parseAndLaunchURL;
  final Future<void> Function(String query) onSearchQuerySelected;

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final CollectionStore _collectionStore = CollectionStore();

  List<Paper> bookmarks = [];
  List<CollectionFolder> folders = [];
  Map<String, List<String>> paperFolderMap = {};
  String? selectedFolderId;
  bool unsortedOnly = false;
  bool isLoading = true;
  int notesRefreshToken = 0;

  Future<void> getBookmarks() async {
    final Box bookmarksBox = await Hive.openBox("bookmarks");
    final raw = await bookmarksBox.get("bookmarks") ?? [];
    await Hive.close();

    final loadedPapers = raw is List ? raw.whereType<Paper>().toList() : <Paper>[];
    final loadedFolders = await _collectionStore.loadFolders();
    final loadedMap = await _collectionStore.loadPaperFolderMap();

    if (!mounted) return;
    setState(() {
      bookmarks = loadedPapers;
      folders = loadedFolders;
      paperFolderMap = loadedMap;
      if (selectedFolderId != null &&
          !folders.any((f) => f.id == selectedFolderId)) {
        selectedFolderId = null;
      }
      isLoading = false;
    });
  }

  Future<void> clearBookmarks() async {
    setState(() {
      isLoading = true;
    });
    final Box bookmarksBox = await Hive.openBox("bookmarks");
    await bookmarksBox.clear();
    await Hive.close();
    for (final paper in bookmarks) {
      await _collectionStore.removePaperFromAllFolders(paper.id);
    }
    if (!mounted) return;
    setState(() {
      bookmarks = [];
      paperFolderMap = {};
      isLoading = false;
    });
  }

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("New collection folder"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Folder name",
            hintText: "e.g. Diffusion, Reading List",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text("Create"),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final created = await _collectionStore.createFolder(name);
    await getBookmarks();
    if (!mounted) return;
    setState(() {
      selectedFolderId = created.id;
      unsortedOnly = false;
    });
  }

  Future<void> _renameFolderDialog(CollectionFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Rename folder"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Folder name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    await _collectionStore.renameFolder(folder.id, newName);
    await getBookmarks();
  }

  Future<void> _deleteFolder(CollectionFolder folder) async {
    await _collectionStore.deleteFolder(folder.id);
    if (selectedFolderId == folder.id) {
      selectedFolderId = null;
    }
    await getBookmarks();
  }

  Future<void> openPaperDetails(Paper paper) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaperDetailPage(
          paper: paper,
          downloadPaper: widget.downloadPaper,
          parseAndLaunchURL: widget.parseAndLaunchURL,
          onSearchQuerySelected: widget.onSearchQuerySelected,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      notesRefreshToken++;
    });
    await getBookmarks();
  }

  @override
  void initState() {
    super.initState();
    getBookmarks();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredPapers = CollectionStore.filterPapers(
      papers: bookmarks,
      paperFolderMap: paperFolderMap,
      selectedFolderId: selectedFolderId,
      unsortedOnly: unsortedOnly,
    );
    final activeFolder = selectedFolderId == null
        ? null
        : folders.where((f) => f.id == selectedFolderId).firstOrNull;
    final unsortedCount = bookmarks
        .where((p) => (paperFolderMap[p.id] ?? const []).isEmpty)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bookmarks"),
        actions: [
          IconButton(
            tooltip: "New folder",
            onPressed: _createFolderDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          if (activeFolder != null)
            PopupMenuButton<String>(
              tooltip: "Manage folder",
              onSelected: (value) {
                if (value == 'rename') {
                  _renameFolderDialog(activeFolder);
                } else if (value == 'delete') {
                  _deleteFolder(activeFolder);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text("Rename folder"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text("Delete folder"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: "Clear all bookmarks",
            onPressed: clearBookmarks,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
      body: isLoading
          ? const LoadingIndicator(topPadding: 50.0)
          : Column(
              children: [
                if (folders.isNotEmpty || bookmarks.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 4.0),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text("All (${bookmarks.length})"),
                            selected: selectedFolderId == null && !unsortedOnly,
                            onSelected: (_) {
                              setState(() {
                                selectedFolderId = null;
                                unsortedOnly = false;
                              });
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text("Unsorted ($unsortedCount)"),
                            selected: unsortedOnly,
                            onSelected: (_) {
                              setState(() {
                                selectedFolderId = null;
                                unsortedOnly = true;
                              });
                            },
                          ),
                        ),
                        for (final folder in folders)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onLongPress: () => _renameFolderDialog(folder),
                              child: ChoiceChip(
                                avatar: const Icon(
                                  Icons.folder_outlined,
                                  size: 16.0,
                                ),
                                label: Text(
                                  "${folder.name} (${bookmarks.where((p) => (paperFolderMap[p.id] ?? const []).contains(folder.id)).length})",
                                ),
                                selected: selectedFolderId == folder.id,
                                onSelected: (_) {
                                  setState(() {
                                    selectedFolderId = folder.id;
                                    unsortedOnly = false;
                                  });
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: filteredPapers.isNotEmpty
                      ? LiquidPullToRefresh(
                          onRefresh: getBookmarks,
                          backgroundColor: colorScheme.surface,
                          color: colorScheme.primary,
                          animSpeedFactor: 2.0,
                          child: ListView(
                            children: filteredPapers
                                .map(
                                  (eachPaper) => EachPaperCard(
                                    eachPaper: eachPaper,
                                    downloadPaper: widget.downloadPaper,
                                    parseAndLaunchURL: widget.parseAndLaunchURL,
                                    isBookmarked: true,
                                    onCardTap: () =>
                                        openPaperDetails(eachPaper),
                                    onCollectionChanged: getBookmarks,
                                    notesRefreshToken: notesRefreshToken,
                                  ),
                                )
                                .toList(),
                          ),
                        )
                      : Center(
                          child: Text(
                            bookmarks.isEmpty
                                ? "No Bookmarks Yet!"
                                : "No papers in this folder.",
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 16.0,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
