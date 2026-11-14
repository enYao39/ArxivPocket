// ignore_for_file: file_names
import 'dart:convert';

import 'package:arxiv/components/app_bottom_sheet.dart';
import 'package:arxiv/components/id_and_date.dart';
import 'package:arxiv/components/summary_bottom_sheet.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/ai_chat_page.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:arxiv/services/paper_notes_store.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'package:share_plus/share_plus.dart';

class EachPaperCard extends StatefulWidget {
  const EachPaperCard({
    super.key,
    required this.parseAndLaunchURL,
    required this.eachPaper,
    required this.downloadPaper,
    required this.isBookmarked,
    this.onCardTap,
    this.onCategoryTap,
    this.onCollectionChanged,
    this.notesRefreshToken = 0,
  });

  final Paper eachPaper;
  final Function downloadPaper;
  final Function parseAndLaunchURL;
  final bool isBookmarked;
  final VoidCallback? onCardTap;
  final ValueChanged<String>? onCategoryTap;
  final VoidCallback? onCollectionChanged;
  final int notesRefreshToken;

  @override
  State<EachPaperCard> createState() => _EachPaperCardState();
}

class _EachPaperCardState extends State<EachPaperCard> {
  var pdfBaseURL = "https://arxiv.org/pdf";
  final PaperNotesStore _notesStore = PaperNotesStore();
  bool hasNote = false;

  String paperPdfUrl() {
    return widget.eachPaper.pdfUrl.isNotEmpty
        ? widget.eachPaper.pdfUrl
        : widget.eachPaper.id;
  }

  String primaryCategory() {
    if (widget.eachPaper.primaryCategory.isNotEmpty) {
      return widget.eachPaper.primaryCategory;
    }
    if (widget.eachPaper.categories.isNotEmpty) {
      return widget.eachPaper.categories.first;
    }
    return "";
  }

  void shareLink(shareURL) {
    if (shareURL.toString().startsWith("http") &&
        shareURL.toString().contains("/pdf/")) {
      Share.share(shareURL);
      return;
    }

    var splitURL = shareURL.split("/");
    var id = splitURL[splitURL.length - 1];
    var selectedURL = "";
    if (id.contains(".") == true) {
      selectedURL = "$pdfBaseURL/$id";
    } else {
      selectedURL = "$pdfBaseURL/cond-mat/$id";
    }
    Share.share(selectedURL);
  }

  void showSummary(dynamic paperData) {
    showAppBottomSheet(
      context,
      child: SummaryBottomSheet(
        paperData: paperData,
        parseAndLaunchURL: widget.parseAndLaunchURL,
      ),
    );
  }

  void showMetadata() {
    final metadata = const JsonEncoder.withIndent(
      "  ",
    ).convert(widget.eachPaper.retainedMetadata);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20.0),
              topRight: Radius.circular(20.0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "arXiv Metadata",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12.0),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    metadata,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: "monospace",
                      fontSize: 12.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool isBookmarked = false;

  void bookmarkToggle() async {
    await checkIfBookmarked();
    if (isBookmarked == false) {
      Box bookmarksBox = await Hive.openBox("bookmarks");
      List bookmarks = await bookmarksBox.get("bookmarks") ?? [];
      bookmarks.add(widget.eachPaper);
      await bookmarksBox.put("bookmarks", bookmarks);
      await Hive.close();
    } else {
      Box bookmarksBox = await Hive.openBox("bookmarks");
      List bookmarks = await bookmarksBox.get("bookmarks") ?? [];
      List newBookmarks = [];
      for (var eachBookmark in bookmarks) {
        if (eachBookmark.id != widget.eachPaper.id) {
          newBookmarks.add(eachBookmark);
        }
      }
      await bookmarksBox.put("bookmarks", newBookmarks);
      await Hive.close();
      await CollectionStore().removePaperFromAllFolders(widget.eachPaper.id);
    }
    await checkIfBookmarked();
    widget.onCollectionChanged?.call();
    setState(() {});
  }

  Future<void> _openFolderPicker() async {
    await checkIfBookmarked();
    if (!isBookmarked) {
      Box bookmarksBox = await Hive.openBox("bookmarks");
      List bookmarks = await bookmarksBox.get("bookmarks") ?? [];
      bookmarks.add(widget.eachPaper);
      await bookmarksBox.put("bookmarks", bookmarks);
      await Hive.close();
      await checkIfBookmarked();
      widget.onCollectionChanged?.call();
    }

    if (!mounted) return;
    final store = CollectionStore();
    var folders = await store.loadFolders();
    var assigned = (await store.foldersForPaper(widget.eachPaper.id)).toSet();

    if (!mounted) return;
    await showAppBottomSheet<void>(
      context,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18.0, 4.0, 18.0, 18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Save to collection folder",
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final createdName = await showDialog<String>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text("New folder"),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: "Folder name",
                                hintText: "e.g. Diffusion, To Read",
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text("Cancel"),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  dialogContext,
                                  controller.text.trim(),
                                ),
                                child: const Text("Create"),
                              ),
                            ],
                          ),
                        );
                        controller.dispose();
                        if (createdName == null || createdName.isEmpty) return;
                        final folder = await store.createFolder(createdName);
                        await store.togglePaperInFolder(
                          widget.eachPaper.id,
                          folder.id,
                        );
                        folders = await store.loadFolders();
                        assigned = (await store.foldersForPaper(
                          widget.eachPaper.id,
                        )).toSet();
                        setSheetState(() {});
                        widget.onCollectionChanged?.call();
                      },
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18.0),
                      label: const Text("New folder"),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                if (folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      "No folders yet. Tap \"New folder\" to organize this paper.",
                      style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280.0),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final checked = assigned.contains(folder.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(folder.name),
                          secondary: const Icon(Icons.folder_outlined),
                          onChanged: (_) async {
                            await store.togglePaperInFolder(
                              widget.eachPaper.id,
                              folder.id,
                            );
                            assigned = (await store.foldersForPaper(
                              widget.eachPaper.id,
                            )).toSet();
                            setSheetState(() {});
                            widget.onCollectionChanged?.call();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> checkIfBookmarked() async {
    Box bookmarksBox = await Hive.openBox("bookmarks");
    List bookmarks = await bookmarksBox.get("bookmarks") ?? [];
    await Hive.close();

    isBookmarked = bookmarks
        .where((bookmark) => bookmark.id == widget.eachPaper.id)
        .isNotEmpty;
    setState(() {});
  }

  Future<void> checkIfHasNote() async {
    final noteExists = await _notesStore.hasNote(widget.eachPaper.id);
    if (!mounted) return;

    setState(() {
      hasNote = noteExists;
    });
  }

  @override
  void initState() {
    super.initState();
    checkIfBookmarked();
    checkIfHasNote();
  }

  @override
  void didUpdateWidget(covariant EachPaperCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eachPaper.id != widget.eachPaper.id ||
        oldWidget.notesRefreshToken != widget.notesRefreshToken) {
      checkIfHasNote();
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.eachPaper.title;
    final colorScheme = Theme.of(context).colorScheme;
    final cardColor = subtleSurfaceColor(colorScheme);

    final card = Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            bottom: 6.0,
            top: 6.0,
          ),
          padding: const EdgeInsets.only(
            left: 10.0,
            right: 10.0,
            top: 6.0,
            bottom: 6.0,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ID and Published Date
              IDAndDate(
                id: widget.eachPaper.id,
                date: widget.eachPaper.publishedAt,
                primaryCategory: primaryCategory(),
                onCategoryTap: widget.onCategoryTap,
              ),

              // TITLE
              GestureDetector(
                onTap: () => widget.parseAndLaunchURL(
                  paperPdfUrl(),
                  widget.eachPaper.title,
                ),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 5.0),
                  child: Text(
                    Paper.formatTitleForDisplay(title),
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Text(
                  "Published: ${widget.eachPaper.publishedAt}",
                  style: const TextStyle(fontSize: 12.0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: ValueListenableBuilder<MainPageStyleSettings>(
                  valueListenable: MainPageStyleStore.notifier,
                  builder: (context, styleSettings, _) {
                    final displayAuthors = MainPageStyleStore.formatAuthors(
                      widget.eachPaper,
                      styleSettings,
                    );
                    return Text(
                      "Authors: $displayAuthors",
                      style: const TextStyle(fontSize: 13.0),
                    );
                  },
                ),
              ),

              // SUMMARY, DOWNLOAD and SHARE
              // Actions
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        showSummary(widget.eachPaper);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 8.0,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          border: Border.all(
                            color: colorScheme.primaryContainer,
                          ),
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                        child: Text(
                          "Abstract",
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  IconButton(
                    tooltip: "Bookmark",
                    onPressed: () {
                      bookmarkToggle();
                    },
                    icon: Icon(
                      isBookmarked == false
                          ? Icons.bookmark_border
                          : Icons.bookmark,
                      color: isBookmarked
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: "Save to folder",
                    onPressed: _openFolderPicker,
                    icon: Icon(
                      Icons.folder_open_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      shareLink(paperPdfUrl());
                    },
                    icon: Icon(
                      Ionicons.share_outline,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      widget.downloadPaper(paperPdfUrl());
                    },
                    icon: Icon(
                      Icons.downloading_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AIChatPage(paperData: widget.eachPaper),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.auto_awesome_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasNote)
          Positioned(
            top: 13.0,
            right: 16.0,
            child: Container(
              width: 9.0,
              height: 9.0,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );

    if (widget.onCardTap == null) {
      return card;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onCardTap,
      child: card,
    );
  }
}
