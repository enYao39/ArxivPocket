// ignore_for_file: file_names
import 'package:arxiv/components/each_paper_card.dart';
import 'package:arxiv/components/loading_indicator.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/services/bookmarks_store.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:flutter/material.dart';
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
  String? _openedFolderId;
  bool isLoading = true;
  int notesRefreshToken = 0;

  Future<void> getBookmarks() async {
    final loadedPapers = await BookmarksStore().loadBookmarks();
    final loadedFolders = await _collectionStore.loadFolders();
    final loadedMap = await _collectionStore.loadPaperFolderMap();

    if (!mounted) return;
    setState(() {
      bookmarks = loadedPapers;
      folders = loadedFolders;
      paperFolderMap = loadedMap;
      if (_openedFolderId != null &&
          !folders.any((f) => f.id == _openedFolderId)) {
        _openedFolderId = null;
      }
      isLoading = false;
    });
  }

  Future<void> clearBookmarks() async {
    setState(() {
      isLoading = true;
    });
    await BookmarksStore().clearAll();
    for (final paper in bookmarks) {
      await _collectionStore.removePaperFromAllFolders(paper.id);
    }
    if (!mounted) return;
    setState(() {
      bookmarks = [];
      paperFolderMap = {};
      _openedFolderId = null;
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

    await _collectionStore.createFolder(name);
    await getBookmarks();
  }

  Future<void> _renameFolderDialog(CollectionFolder folder) async {
    if (folder.isDefault) return;
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
    if (folder.isDefault) return;
    await _collectionStore.deleteFolder(folder.id);
    if (_openedFolderId == folder.id) {
      _openedFolderId = null;
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
    final openedFolder = _openedFolderId == null
        ? null
        : folders.where((f) => f.id == _openedFolderId).firstOrNull;
    final folderPapers = openedFolder == null
        ? const <Paper>[]
        : CollectionStore.filterPapers(
            papers: bookmarks,
            paperFolderMap: paperFolderMap,
            selectedFolderId: openedFolder.id,
          );

    return PopScope(
      canPop: openedFolder == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && openedFolder != null) {
          setState(() {
            _openedFolderId = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: openedFolder != null
              ? BackButton(
                  onPressed: () {
                    setState(() {
                      _openedFolderId = null;
                    });
                  },
                )
              : null,
          title: Text(openedFolder?.name ?? "Collections"),
          actions: [
            if (openedFolder == null)
              IconButton(
                tooltip: "New folder",
                onPressed: _createFolderDialog,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            if (openedFolder != null && !openedFolder.isDefault)
              PopupMenuButton<String>(
                tooltip: "Manage folder",
                onSelected: (value) {
                  if (value == 'rename') {
                    _renameFolderDialog(openedFolder);
                  } else if (value == 'delete') {
                    _deleteFolder(openedFolder);
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
            if (openedFolder == null && bookmarks.isNotEmpty)
              IconButton(
                tooltip: "Clear all collections",
                onPressed: clearBookmarks,
                icon: const Icon(Icons.delete_forever_outlined),
              ),
          ],
        ),
        body: isLoading
            ? const LoadingIndicator(topPadding: 50.0)
            : openedFolder == null
            ? RefreshIndicator(
                onRefresh: getBookmarks,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: folders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8.0),
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final count = CollectionStore.filterPapers(
                      papers: bookmarks,
                      paperFolderMap: paperFolderMap,
                      selectedFolderId: folder.id,
                    ).length;

                    return Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          folder.isDefault
                              ? Icons.folder_special_outlined
                              : Icons.folder_outlined,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          folder.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          count == 1 ? "1 paper" : "$count papers",
                        ),
                        trailing: folder.isDefault
                            ? const Icon(Icons.chevron_right_rounded)
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _renameFolderDialog(folder);
                                  } else if (value == 'delete') {
                                    _deleteFolder(folder);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text("Rename"),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text("Delete"),
                                  ),
                                ],
                              ),
                        onTap: () {
                          setState(() {
                            _openedFolderId = folder.id;
                          });
                        },
                      ),
                    );
                  },
                ),
              )
            : folderPapers.isNotEmpty
            ? LiquidPullToRefresh(
                onRefresh: getBookmarks,
                backgroundColor: colorScheme.surface,
                color: colorScheme.primary,
                animSpeedFactor: 2.0,
                child: ListView(
                  children: folderPapers
                      .map(
                        (eachPaper) => EachPaperCard(
                          eachPaper: eachPaper,
                          downloadPaper: widget.downloadPaper,
                          parseAndLaunchURL: widget.parseAndLaunchURL,
                          isBookmarked: true,
                          onCardTap: () => openPaperDetails(eachPaper),
                          onCollectionChanged: getBookmarks,
                          notesRefreshToken: notesRefreshToken,
                        ),
                      )
                      .toList(),
                ),
              )
            : Center(
                child: Text(
                  "No papers in ${openedFolder.name} yet.",
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16.0,
                  ),
                ),
              ),
      ),
    );
  }
}
