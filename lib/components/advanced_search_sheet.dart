import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/app_bottom_sheet.dart';
import 'package:arxiv/components/category_picker_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/services/arxiv_category_parser.dart';
import 'package:arxiv/services/arxiv_web_search.dart';
import 'package:arxiv/services/main_page_style_store.dart';
import 'package:flutter/material.dart';

export 'package:arxiv/services/arxiv_web_search.dart';

Future<void> showAdvancedSearchSheet(
  BuildContext context, {
  ArxivAdvancedQuery? initialQuery,
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
          initialQuery: initialQuery,
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

class _TermRowState {
  _TermRowState({
    this.operator = ArxivSearchOperator.and,
    String term = '',
    this.field = ArxivSearchField.all,
  }) : controller = TextEditingController(text: term);

  ArxivSearchOperator operator;
  final TextEditingController controller;
  ArxivSearchField field;

  void dispose() {
    controller.dispose();
  }
}

class AdvancedSearchSheet extends StatefulWidget {
  const AdvancedSearchSheet({
    super.key,
    this.initialQuery,
    this.initialCategory,
    required this.initialSortOption,
    required this.initialPageSize,
    required this.onApply,
  });

  final ArxivAdvancedQuery? initialQuery;
  final ArxivCategory? initialCategory;
  final ArxivSortOption initialSortOption;
  final int initialPageSize;
  final Future<void> Function(ArxivAdvancedQuery query) onApply;

  @override
  State<AdvancedSearchSheet> createState() => _AdvancedSearchSheetState();
}

class _AdvancedSearchSheetState extends State<AdvancedSearchSheet> {
  final List<_TermRowState> _rows = [];
  final _yearController = TextEditingController();

  ArxivCategory? _selectedCategory;
  bool _includeCrossList = true;
  ArxivDateFilterMode _dateFilterMode = ArxivDateFilterMode.allDates;
  DateTime? _fromDate;
  DateTime? _toDate;
  late ArxivSortOption _sortOption;
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery;
    if (initial != null && initial.terms.isNotEmpty) {
      for (final row in initial.terms) {
        _rows.add(
          _TermRowState(
            operator: row.operator,
            term: row.term,
            field: row.field,
          ),
        );
      }
    } else {
      _rows.add(_TermRowState());
    }

    _selectedCategory = widget.initialCategory ?? initial?.category;
    _includeCrossList =
        initial?.includeCrossList ??
        !MainPageStyleStore.notifier.value.excludeCrossListed;
    _dateFilterMode = initial?.dateFilterMode ?? ArxivDateFilterMode.allDates;
    _yearController.text = initial?.specificYear?.toString() ?? '';
    _fromDate = initial?.fromDate;
    _toDate = initial?.toDate;
    _sortOption = initial?.sortOption ?? widget.initialSortOption;
    _pageSize = ArxivWebSearch.normalizeWebPageSize(
      initial?.pageSize ?? widget.initialPageSize,
    );
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _yearController.dispose();
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_TermRowState());
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      final removed = _rows.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_fromDate ?? DateTime(now.year - 1, now.month, now.day))
        : (_toDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1991, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
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

  void _resetAll() {
    setState(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..add(_TermRowState());
      _yearController.clear();
      _selectedCategory = null;
      _includeCrossList = !MainPageStyleStore.notifier.value.excludeCrossListed;
      _dateFilterMode = ArxivDateFilterMode.allDates;
      _fromDate = null;
      _toDate = null;
      _sortOption = ArxivSortOption.newest;
      _pageSize = 25;
    });
  }

  Future<void> _submit() async {
    final parsedYear = int.tryParse(_yearController.text.trim());
    final query = ArxivAdvancedQuery(
      terms: _rows
          .map(
            (row) => ArxivSearchTermRow(
              operator: row.operator,
              term: row.controller.text,
              field: row.field,
            ),
          )
          .toList(),
      category: _selectedCategory,
      includeCrossList: _includeCrossList,
      dateFilterMode: _dateFilterMode,
      specificYear: _dateFilterMode == ArxivDateFilterMode.specificYear
          ? parsedYear
          : null,
      fromDate: _dateFilterMode == ArxivDateFilterMode.dateRange
          ? _fromDate
          : null,
      toDate: _dateFilterMode == ArxivDateFilterMode.dateRange ? _toDate : null,
      sortOption: _sortOption,
      pageSize: _pageSize,
    );

    if (!query.hasAnyCriteria) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Enter at least one search term, category, or date filter.",
          ),
        ),
      );
      return;
    }

    await widget.onApply(query);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18.0, 4.0, 18.0, 18.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Advanced Search",
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          "Aligned with arxiv.org/search/advanced",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _resetAll, child: const Text("Reset")),
                ],
              ),
              const SizedBox(height: 10.0),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Search terms",
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8.0),
                      for (var i = 0; i < _rows.length; i++) ...[
                        _buildTermRow(i, colorScheme),
                        const SizedBox(height: 10.0),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _addRow,
                          icon: const Icon(Icons.add_rounded, size: 18.0),
                          label: const Text("Add another term"),
                        ),
                      ),
                      const SizedBox(height: 14.0),
                      Text(
                        "Subject / Category",
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
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
                              icon: const Icon(
                                Icons.category_outlined,
                                size: 18.0,
                              ),
                              label: Text(
                                _selectedCategory == null
                                    ? "All classifications"
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
                      const SizedBox(height: 8.0),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Include cross-listed papers"),
                        subtitle: Text(
                          _includeCrossList
                              ? "Shows papers cross-listed into the selected subject"
                              : "Shows only papers whose primary category matches",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        value: _includeCrossList,
                        onChanged: (value) {
                          setState(() {
                            _includeCrossList = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10.0),
                      Text(
                        "Date",
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6.0),
                      DropdownButtonFormField<ArxivDateFilterMode>(
                        initialValue: _dateFilterMode,
                        decoration: const InputDecoration(
                          labelText: "Date filter",
                          isDense: true,
                        ),
                        items: ArxivDateFilterMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _dateFilterMode = value;
                          });
                        },
                      ),
                      if (_dateFilterMode ==
                          ArxivDateFilterMode.specificYear) ...[
                        const SizedBox(height: 10.0),
                        TextField(
                          controller: _yearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Year (YYYY)",
                            hintText: "e.g. 2025",
                            isDense: true,
                          ),
                        ),
                      ],
                      if (_dateFilterMode == ArxivDateFilterMode.dateRange) ...[
                        const SizedBox(height: 10.0),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _pickDate(isFrom: true),
                                child: Text(
                                  _fromDate == null
                                      ? "From date"
                                      : "${_fromDate!.year}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}",
                                ),
                              ),
                            ),
                            const SizedBox(width: 10.0),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _pickDate(isFrom: false),
                                child: Text(
                                  _toDate == null
                                      ? "To date"
                                      : "${_toDate!.year}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}",
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14.0),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<ArxivSortOption>(
                              initialValue: _sortOption,
                              decoration: const InputDecoration(
                                labelText: "Sort order",
                                isDense: true,
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
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _pageSize,
                              decoration: const InputDecoration(
                                labelText: "Results / page",
                                isDense: true,
                              ),
                              items: const [25, 50, 100, 200]
                                  .map(
                                    (size) => DropdownMenuItem(
                                      value: size,
                                      child: Text("$size"),
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
              ),
              const SizedBox(height: 14.0),
              FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13.0),
                ),
                icon: const Icon(Icons.search_rounded),
                label: const Text("Search arXiv"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermRow(int index, ColorScheme colorScheme) {
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (index > 0) ...[
                SizedBox(
                  width: 96.0,
                  child: DropdownButtonFormField<ArxivSearchOperator>(
                    initialValue: row.operator,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 8.0,
                      ),
                    ),
                    items: ArxivSearchOperator.values
                        .map(
                          (op) => DropdownMenuItem(
                            value: op,
                            child: Text(op.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        row.operator = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8.0),
              ],
              Expanded(
                child: DropdownButtonFormField<ArxivSearchField>(
                  initialValue: row.field,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Field",
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 8.0,
                    ),
                  ),
                  items: ArxivSearchField.values
                      .map(
                        (field) => DropdownMenuItem(
                          value: field,
                          child: Text(
                            field.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      row.field = value;
                    });
                  },
                ),
              ),
              if (_rows.length > 1) ...[
                const SizedBox(width: 4.0),
                IconButton(
                  tooltip: "Remove term",
                  onPressed: () => _removeRow(index),
                  icon: const Icon(Icons.close_rounded, size: 18.0),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8.0),
          TextField(
            controller: row.controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: index == 0 ? "Search term" : "Additional term",
              hintText: "e.g. diffusion models, Vaswani",
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
