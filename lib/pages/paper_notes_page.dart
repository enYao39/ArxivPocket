import 'package:arxiv/components/paper_note_card.dart';
import 'package:arxiv/models/paper_note.dart';
import 'package:arxiv/pages/paper_detail_page.dart';
import 'package:arxiv/services/collection_store.dart';
import 'package:arxiv/services/paper_notes_store.dart';
import 'package:flutter/material.dart';

class PaperNotesPage extends StatefulWidget {
  const PaperNotesPage({
    super.key,
    required this.downloadPaper,
    required this.parseAndLaunchURL,
    required this.onSearchQuerySelected,
  });

  final Function downloadPaper;
  final Function parseAndLaunchURL;
  final Future<void> Function(String query) onSearchQuerySelected;

  @override
  State<PaperNotesPage> createState() => _PaperNotesPageState();
}

class _PaperNotesPageState extends State<PaperNotesPage> {
  final PaperNotesStore _notesStore = PaperNotesStore();
  final CollectionStore _collectionStore = CollectionStore();

  List<PaperNote> _notes = [];
  List<CollectionFolder> _folders = [];
  Map<String, List<String>> _paperFolderMap = {};
  String? _openedFolderId;
  bool _isLoadingNotes = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final notes = await _notesStore.loadNotes();
    final folders = await _collectionStore.loadFolders();
    final paperFolderMap = await _collectionStore.loadPaperFolderMap();
    if (!mounted) return;

    setState(() {
      _notes = notes;
      _folders = folders;
      _paperFolderMap = paperFolderMap;
      if (_openedFolderId != null &&
          !_folders.any((f) => f.id == _openedFolderId)) {
        _openedFolderId = null;
      }
      _isLoadingNotes = false;
    });
  }

  Future<void> _confirmDeleteNote(PaperNote note) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete note?"),
        content: Text(
          "This will permanently delete the note for \"${note.paperTitle}\".",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    await _notesStore.deleteNote(note.paperId);
    await _loadNotes();
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Note deleted")));
  }

  Future<PaperNote?> _saveInlineNote(PaperNote note, String body) async {
    final updatedNote = await _notesStore.updateNote(note, body);
    await _loadNotes();
    if (!mounted) return updatedNote;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updatedNote == null ? "Note cleared" : "Note saved"),
      ),
    );
    return updatedNote;
  }

  Future<void> _openPaperDetails(PaperNote note) async {
    final paper = note.paper;
    if (paper == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Paper details are unavailable for this older note."),
        ),
      );
      return;
    }

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
    await _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final openedFolder = _openedFolderId == null
        ? null
        : _folders.where((f) => f.id == _openedFolderId).firstOrNull;
    final folderNotes = openedFolder == null
        ? const <PaperNote>[]
        : CollectionStore.filterNotes(
            notes: _notes,
            paperFolderMap: _paperFolderMap,
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
          title: Text(
            openedFolder == null
                ? "Paper Notes"
                : "${openedFolder.name} Notes",
          ),
        ),
        body: _isLoadingNotes
            ? const Center(child: CircularProgressIndicator())
            : openedFolder == null
            ? RefreshIndicator(
                onRefresh: _loadNotes,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: _folders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8.0),
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    final count = CollectionStore.filterNotes(
                      notes: _notes,
                      paperFolderMap: _paperFolderMap,
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
                          count == 1 ? "1 note" : "$count notes",
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
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
            : folderNotes.isEmpty
            ? Center(
                child: Text(
                  "No paper notes in ${openedFolder.name} yet.",
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16.0,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadNotes,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: folderNotes.length,
                  itemBuilder: (context, index) {
                    final note = folderNotes[index];

                    return PaperNoteCard(
                      note: note,
                      onPaperTap: () => _openPaperDetails(note),
                      allowInlineView: true,
                      allowInlineEdit: true,
                      onSave: (body) => _saveInlineNote(note, body),
                      onDelete: () => _confirmDeleteNote(note),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
