import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/app_bottom_sheet.dart';
import 'package:arxiv/components/category_picker_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/services/arxiv_category_parser.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ArxivAdvancedQuery {
  const ArxivAdvancedQuery({
    this.all = '',
    this.title = '',
    this.author = '',
    this.abstractText = '',
    this.comments = '',
    this.journalRef = '',
    this.category,
    this.fromDate,
    this.toDate,
    this.sortOption = ArxivSortOption.newest,
    this.pageSize = 30,
  });

  final String all;
  final String title;
  final String author;
  final String abstractText;
  final String comments;
  final String journalRef;
  final ArxivCategory? category;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ArxivSortOption sortOption;
  final int pageSize;

  String buildSearchQuery() {
    final parts = <String>[];

    void addField(String prefix, String rawValue) {
      final trimmed = rawValue.trim();
      if (trimmed.isEmpty) return;
      final needsQuotes =
          trimmed.contains(' ') &&
          !(trimmed.startsWith('"') && trimmed.endsWith('"'));
      final formatted = needsQuotes ? '"$trimmed"' : trimmed;
      parts.add('$prefix:$formatted');
    }

    addField('all', all);
    addField('ti', title);
    addField('au', author);
    addField('abs', abstractText);
    addField('co', comments);
    addField('jr', journalRef);

    if (category != null) {
      parts.add(category!.query);
    }

    if (fromDate != null || toDate != null) {
      final start = fromDate != null
          ? '${_formatYmd(fromDate!)}0000'
          : '199101010000';
      final end = toDate != null ? '${_formatYmd(toDate!)}2359' : '209912312359';
      parts.add('submittedDate:[$start TO $end]');
    }

    return parts.join(' AND ');
  }

  static String _formatYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}

Future<void> showAdvancedSearchSheet(
  BuildContext context, {
  ArxivCategory? initialCategory,
  required ArxivSortOption initialSortOption,
  required int initialPageSize,
  required Future<void> Function(ArxivAdvancedQuery query) onApply,
}) {
  return showAppBottomSheet<void>(
    context,
    child: Builder(
      builder: (sheetContext) {
        return AdvancedSearchSheet(
          initialCategory: initialCategory,
          initialSortOption: initialSortOption,
          initialPageSize: initialPageSize,
          onApply: (query) async {
            Navigator.pop(sheetContext);
            await onApply(query);
          },
        );
      },
    ),
  );
}

class AdvancedSearchSheet extends StatefulWidget {
  const AdvancedSearchSheet({
    super.key,
    this.initialCategory,
    required this.initialSortOption,
    required this.initialPageSize,
    required this.onApply,
  });

  final ArxivCategory? initialCategory;
  final ArxivSortOption initialSortOption;
  final int initialPageSize;
  final Future<void> Function(ArxivAdvancedQuery query) onApply;

  @override
  State<AdvancedSearchSheet> createState() => _AdvancedSearchSheetState();
}

class _AdvancedSearchSheetState extends State<AdvancedSearchSheet> {
  final _allController = TextEditingController();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _abstractController = TextEditingController();
  final _commentsController = TextEditingController();
  final _journalController = TextEditingController();

  ArxivCategory? _selectedCategory;
  DateTime? _fromDate;
  DateTime? _toDate;
  late ArxivSortOption _sortOption;
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _sortOption = widget.initialSortOption;
    _pageSize = widget.initialPageSize;
  }

  @override
  void dispose() {
    _allController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _abstractController.dispose();
    _commentsController.dispose();
    _journalController.dispose();
    super.dispose();
  }

  void _resetAll() {
    _allController.clear();
    _titleController.clear();
    _authorController.clear();
    _abstractController.clear();
    _commentsController.clear();
    _journalController.clear();
    setState(() {
      _selectedCategory = null;
      _fromDate = null;
      _toDate = null;
      _sortOption = ArxivSortOption.relevance;
      _pageSize = 30;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_fromDate ?? DateTime(now.year, now.month, 1))
        : (_toDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1991, 1, 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(picked)) {
          _toDate = picked;
        }
      } else {
        _toDate = picked;
        if (_fromDate != null && _fromDate!.isAfter(picked)) {
          _fromDate = picked;
        }
      }
    });
  }

  String _formatDateLabel(DateTime? date, String fallback) {
    if (date == null) return fallback;
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _buildField(
    TextEditingController controller, {
    required String label,
    required String hint,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: subtleSurfaceColor(colorScheme),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBottomSheetShell(
      title: "Advanced arXiv Search",
      maxHeightFactor: 0.88,
      titleTextStyle: TextStyle(
        fontSize: 20.0,
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
        height: 1.2,
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 16.0),
              children: [
                _buildField(
                  _allController,
                  label: "All fields",
                  hint: "e.g. diffusion models",
                ),
                _buildField(
                  _titleController,
                  label: "Title (ti:)",
                  hint: "e.g. attention is all you need",
                ),
                _buildField(
                  _authorController,
                  label: "Author (au:)",
                  hint: "e.g. Vaswani",
                ),
                _buildField(
                  _abstractController,
                  label: "Abstract (abs:)",
                  hint: "Keywords in abstract",
                ),
                _buildField(
                  _commentsController,
                  label: "Comments (co:)",
                  hint: "e.g. ICLR 2025, 12 pages",
                ),
                _buildField(
                  _journalController,
                  label: "Journal reference (jr:)",
                  hint: "e.g. Nature, Phys. Rev. Lett.",
                ),
                const SizedBox(height: 4.0),
                Text(
                  "Subject / Category",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6.0),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showCategoryPickerSheet(
                            context,
                            currentQuery: '',
                            selectedCategory: _selectedCategory,
                            onClearCategory: () {
                              setState(() {
                                _selectedCategory = null;
                              });
                            },
                            onCategorySelected: (category) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                          );
                        },
                        icon: const Icon(Icons.category_outlined, size: 18.0),
                        label: Text(
                          _selectedCategory == null
                              ? "All categories"
                              : categoryFilterLabel(_selectedCategory!),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_selectedCategory != null) ...[
                      const SizedBox(width: 8.0),
                      IconButton(
                        tooltip: "Clear category",
                        onPressed: () {
                          setState(() {
                            _selectedCategory = null;
                          });
                        },
                        icon: const Icon(Icons.close, size: 18.0),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12.0),
                Text(
                  "Submitted Date Range",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6.0),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: true),
                        icon: const Icon(Icons.calendar_today, size: 16.0),
                        label: Text(_formatDateLabel(_fromDate, "From date")),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: false),
                        icon: const Icon(Icons.calendar_today, size: 16.0),
                        label: Text(_formatDateLabel(_toDate, "To date")),
                      ),
                    ),
                    if (_fromDate != null || _toDate != null)
                      IconButton(
                        tooltip: "Clear dates",
                        onPressed: () {
                          setState(() {
                            _fromDate = null;
                            _toDate = null;
                          });
                        },
                        icon: const Icon(Icons.close, size: 18.0),
                      ),
                  ],
                ),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ArxivSortOption>(
                        initialValue: _sortOption,
                        decoration: InputDecoration(
                          labelText: "Sort by",
                          isDense: true,
                          filled: true,
                          fillColor: subtleSurfaceColor(colorScheme),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: ArxivSortOption.values
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _sortOption = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    SizedBox(
                      width: 115.0,
                      child: DropdownButtonFormField<int>(
                        initialValue: _pageSize,
                        decoration: InputDecoration(
                          labelText: "Per page",
                          isDense: true,
                          filled: true,
                          fillColor: subtleSurfaceColor(colorScheme),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: const [15, 30, 50]
                            .map(
                              (count) => DropdownMenuItem(
                                value: count,
                                child: Text("$count"),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _pageSize = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
            child: Row(
              children: [
                TextButton(
                  onPressed: _resetAll,
                  child: const Text("Reset"),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    widget.onApply(
                      ArxivAdvancedQuery(
                        all: _allController.text,
                        title: _titleController.text,
                        author: _authorController.text,
                        abstractText: _abstractController.text,
                        comments: _commentsController.text,
                        journalRef: _journalController.text,
                        category: _selectedCategory,
                        fromDate: _fromDate,
                        toDate: _toDate,
                        sortOption: _sortOption,
                        pageSize: _pageSize,
                      ),
                    );
                  },
                  icon: const Icon(Icons.search, size: 18.0),
                  label: const Text("Search arXiv"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
