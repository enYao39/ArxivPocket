// ignore_for_file: file_names
import 'dart:convert';

import 'package:arxiv/components/app_bottom_sheet.dart';
import 'package:arxiv/components/id_and_date.dart';
import 'package:arxiv/components/summary_bottom_sheet.dart';
import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/ai_chat_page.dart';
import 'package:arxiv/services/bookmarks_store.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:arxiv/services/paper_notes_store.dart';
import 'package:arxiv/services/read_papers_store.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';
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
    this.isNew = false,
    this.dimWhenRead = true,
  });

  final Paper eachPaper;
  final Function downloadPaper;
  final Function parseAndLaunchURL;
  final bool isBookmarked;
  final VoidCallback? onCardTap;
  final ValueChanged<String>? onCategoryTap;
  final VoidCallback? onCollectionChanged;
  final int notesRefreshToken;
  final bool isNew;
  final bool dimWhenRead;

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

  Future<void> _ensureBookmarked() async {
    await BookmarksStore().ensureBookmarked(widget.eachPaper);
  }

  Future<void> _removeBookmark() async {
    await BookmarksStore().removeBookmark(widget.eachPaper.id);
    await CollectionStore().removePaperFromAllFolders(widget.eachPaper.id);
  }

  void bookmarkToggle() async {
    await checkIfBookmarked();
    if (isBookmarked == false) {
      await _ensureBookmarked();
      await CollectionStore().setPaperFolders(widget.eachPaper.id, [
        CollectionStore.defaultFolderId,
      ]);
    } else {
      await _removeBookmark();
    }
    await checkIfBookmarked();
    widget.onCollectionChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _openFolderPicker() async {
    await checkIfBookmarked();
    final store = CollectionStore();
    var folders = await store.loadFolders();
    var assigned = (await store.foldersForPaper(widget.eachPaper.id)).toSet();
    if (isBookmarked && assigned.isEmpty) {
      assigned = {CollectionStore.defaultFolderId};
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text("Collect to folder"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280.0),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final checked = assigned.contains(folder.id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          title: Text(folder.name),
                          secondary: Icon(
                            folder.isDefault
                                ? Icons.folder_special_outlined
                                : Icons.folder_outlined,
                          ),
                          onChanged: (value) async {
                            if (value == true) {
                              assigned.add(folder.id);
                              await _ensureBookmarked();
                              await store.setPaperFolders(
                                widget.eachPaper.id,
                                assigned.toList(),
                              );
                            } else {
                              assigned.remove(folder.id);
                              if (assigned.isEmpty) {
                                await _removeBookmark();
                              } else {
                                await store.setPaperFolders(
                                  widget.eachPaper.id,
                                  assigned.toList(),
                                );
                              }
                            }
                            await checkIfBookmarked();
                            setDialogState(() {});
                            widget.onCollectionChanged?.call();
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final createdName = await showDialog<String>(
                          context: dialogContext,
                          builder: (nameDialogContext) => AlertDialog(
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
                                onPressed: () =>
                                    Navigator.pop(nameDialogContext),
                                child: const Text("Cancel"),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  nameDialogContext,
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
                        assigned.add(folder.id);
                        await _ensureBookmarked();
                        await store.setPaperFolders(
                          widget.eachPaper.id,
                          assigned.toList(),
                        );
                        folders = await store.loadFolders();
                        await checkIfBookmarked();
                        setDialogState(() {});
                        widget.onCollectionChanged?.call();
                      },
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18.0,
                      ),
                      label: const Text("New folder"),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Done"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> checkIfBookmarked() async {
    await BookmarksStore().ensureLoaded();
    if (!mounted) return;
    setState(() {
      isBookmarked = BookmarksStore().isBookmarked(widget.eachPaper.id);
    });
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

    final normalizedId = ReadPapersStore.normalizeId(widget.eachPaper.id);

    Widget buildCard(bool isRead) {
      final card = AnimatedOpacity(
        opacity: widget.dimWhenRead && isRead ? 0.56 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
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
                  // ID, Category, NEW badge, and Read toggle
                  IDAndDate(
                    id: widget.eachPaper.id,
                    date: widget.eachPaper.publishedAt,
                    primaryCategory: primaryCategory(),
                    onCategoryTap: widget.onCategoryTap,
                    isNew: widget.isNew,
                    isRead: isRead,
                    onToggleRead: () {
                      ReadPapersStore().toggleRead(
                        widget.eachPaper.id,
                        paper: widget.eachPaper,
                      );
                    },
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
                  Semantics(
                    button: true,
                    label: "Collect paper. Long press to choose folder.",
                    child: InkResponse(
                      onTap: bookmarkToggle,
                      onLongPress: _openFolderPicker,
                      radius: 20.0,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          isBookmarked == false
                              ? Icons.bookmark_border
                              : Icons.bookmark,
                          color: isBookmarked
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
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
            top: 10.0,
            right: 11.0,
            child: Container(
              width: 7.0,
              height: 7.0,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          ],
        ),
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

    return ValueListenableBuilder<Set<String>>(
      valueListenable: ReadPapersStore.notifier,
      builder: (context, readIds, _) {
        final isRead = readIds.contains(normalizedId);
        return buildCard(isRead);
      },
    );
  }
}
