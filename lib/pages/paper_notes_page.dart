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
  String? _selectedFolderId;
  bool _unsortedOnly = false;
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
      if (_selectedFolderId != null &&
          !_folders.any((f) => f.id == _selectedFolderId)) {
        _selectedFolderId = null;
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

  Widget _buildNotesList() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notes.isEmpty) {
      return Center(
        child: Text(
          "No paper notes yet",
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16.0),
        ),
      );
    }

    final filteredNotes = CollectionStore.filterNotes(
      notes: _notes,
      paperFolderMap: _paperFolderMap,
      selectedFolderId: _selectedFolderId,
      unsortedOnly: _unsortedOnly,
    );
    final unsortedCount = _notes
        .where((n) => (_paperFolderMap[n.paperId] ?? const []).isEmpty)
        .length;

    return Column(
      children: [
        if (_folders.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 4.0),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text("All (${_notes.length})"),
                    selected: _selectedFolderId == null && !_unsortedOnly,
                    onSelected: (_) {
                      setState(() {
                        _selectedFolderId = null;
                        _unsortedOnly = false;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text("Unsorted ($unsortedCount)"),
                    selected: _unsortedOnly,
                    onSelected: (_) {
                      setState(() {
                        _selectedFolderId = null;
                        _unsortedOnly = true;
                      });
                    },
                  ),
                ),
                for (final folder in _folders)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      avatar: const Icon(Icons.folder_outlined, size: 16.0),
                      label: Text(
                        "${folder.name} (${_notes.where((n) => (_paperFolderMap[n.paperId] ?? const []).contains(folder.id)).length})",
                      ),
                      selected: _selectedFolderId == folder.id,
                      onSelected: (_) {
                        setState(() {
                          _selectedFolderId = folder.id;
                          _unsortedOnly = false;
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: filteredNotes.isEmpty
              ? Center(
                  child: Text(
                    "No paper notes in this folder.",
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
                    itemCount: filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = filteredNotes[index];

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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Paper Notes")),
      body: _buildNotesList(),
    );
  }
}
