import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/pages/pdf_viewer.dart';
import 'package:arxiv/services/bookmarks_store.dart';
import 'package:arxiv/services/feed_cache_store.dart';
import 'package:arxiv/services/pdf_cache_store.dart';
import 'package:arxiv/services/read_papers_store.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ReadHistoryPage extends StatefulWidget {
  const ReadHistoryPage({super.key});

  @override
  State<ReadHistoryPage> createState() => _ReadHistoryPageState();
}

class _ReadHistoryPageState extends State<ReadHistoryPage> {
  bool _isLoading = true;
  List<({String id, DateTime? readAt, Paper? paper})> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final results = await Future.wait([
      ReadPapersStore().loadReadHistory(),
      FeedCacheStore().loadAllCachedPapers(),
      BookmarksStore().loadBookmarks(),
    ]);

    final history =
        results[0] as List<({String id, DateTime? readAt, Paper? paper})>;
    final cachedPapers = results[1] as List<Paper>;
    final bookmarkedPapers = results[2] as List<Paper>;

    final fallbackById = <String, Paper>{};
    for (final p in [...cachedPapers, ...bookmarkedPapers]) {
      final normId = ReadPapersStore.normalizeId(p.id);
      if (normId.isNotEmpty) {
        fallbackById.putIfAbsent(normId, () => p);
      }
    }

    final resolved = history
        .map(
          (item) => (
            id: item.id,
            readAt: item.readAt,
            paper: item.paper ?? fallbackById[item.id],
          ),
        )
        .toList();

    if (!mounted) return;
    setState(() {
      _entries = resolved;
      _isLoading = false;
    });
  }

  String _pdfUrlFor(String paperUrl) {
    final trimmed = paperUrl.trim();
    if (trimmed.startsWith("http") && trimmed.contains("/pdf/")) {
      return trimmed;
    }
    final parts = trimmed.split("/");
    final id = parts.isNotEmpty ? parts.last : trimmed;
    if (id.contains(".")) {
      return "https://arxiv.org/pdf/$id";
    }
    return "https://arxiv.org/pdf/cond-mat/$id";
  }

  Future<void> _openPdf(String url, String title) async {
    final pdfUrl = _pdfUrlFor(url);
    final split = url.split("/");
    final id = split.isNotEmpty ? split.last : url;
    final sanitizedId = id.replaceAll("/", "_");
    final savePath = await PdfCacheStore().cachePathForId(sanitizedId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewer(
          paperTitle: title,
          savePath: savePath,
          pdfURL: pdfUrl,
          urlType: 1,
          downloadPaper: (String u) => launchUrl(Uri.parse(_pdfUrlFor(u))),
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Clear Read Flags?"),
        content: Text(
          "This will reset the read status of all ${_entries.length} marked papers.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Clear"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ReadPapersStore().clearAll();
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Read History"),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: "Clear all read flags",
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 42.0,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      "No papers marked as read yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: _entries.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Text(
                      "${_entries.length} read papers stored locally",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final item = _entries[index - 1];
                final paper = item.paper;
                if (paper == null) {
                  return Card(
                    color: subtleSurfaceColor(colorScheme),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: ListTile(
                      title: Text("arXiv:${item.id}"),
                      subtitle: item.readAt != null
                          ? Text(
                              "Marked read ${item.readAt!.toLocal().toString().substring(0, 16)}",
                              style: TextStyle(
                                fontSize: 12.0,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: IconButton(
                        tooltip: "Mark as unread",
                        icon: Icon(
                          Icons.visibility_off_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () async {
                          await ReadPapersStore().markUnread(item.id);
                          _loadHistory();
                        },
                      ),
                    ),
                  );
                }

                final category = paper.primaryCategory.isNotEmpty
                    ? paper.primaryCategory
                    : (paper.categories.isNotEmpty
                          ? paper.categories.first
                          : "");

                return Card(
                  color: subtleSurfaceColor(colorScheme),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 6.0,
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaperDetailPage(
                            paper: paper,
                            downloadPaper: (String u) =>
                                launchUrl(Uri.parse(_pdfUrlFor(u))),
                            parseAndLaunchURL: _openPdf,
                            onSearchQuerySelected: (_) async {},
                          ),
                        ),
                      );
                      _loadHistory();
                    },
                    title: Text(
                      Paper.formatTitleForDisplay(paper.title),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        [
                          paper.id,
                          if (category.isNotEmpty) category,
                          if (paper.publishedAt.isNotEmpty) paper.publishedAt,
                        ].join(" • "),
                        style: TextStyle(
                          fontSize: 12.0,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: "Mark as unread",
                      icon: Icon(
                        Icons.visibility_off_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () async {
                        await ReadPapersStore().markUnread(paper.id);
                        _loadHistory();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
