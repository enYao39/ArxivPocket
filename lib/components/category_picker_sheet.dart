import 'package:arxiv/components/app_bottom_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/services/arxiv_category_parser.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';

Future<void> showCategoryPickerSheet(
  BuildContext context, {
  required String currentQuery,
  ArxivCategory? selectedCategory,
  VoidCallback? onClearCategory,
  required ValueChanged<ArxivCategory> onCategorySelected,
}) {
  return showAppBottomSheet<void>(
    context,
    child: Builder(
      builder: (sheetContext) {
        return CategoryPickerSheet(
          currentQuery: currentQuery,
          selectedCategory: selectedCategory,
          onClearCategory: onClearCategory == null
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  onClearCategory();
                },
          onCategorySelected: (category) {
            // Close the sheet before triggering search so the feed updates underneath.
            Navigator.pop(sheetContext);
            onCategorySelected(category);
          },
        );
      },
    ),
  );
}

class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.currentQuery,
    this.selectedCategory,
    this.onClearCategory,
    required this.onCategorySelected,
  });

  final String currentQuery;
  final ArxivCategory? selectedCategory;
  final VoidCallback? onClearCategory;
  final ValueChanged<ArxivCategory> onCategorySelected;

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final TextEditingController _filterController = TextEditingController();
  final Set<String> _expandedGroups = <String>{};
  String _filterText = "";

  void _toggleGroup(String group) {
    setState(() {
      if (!_expandedGroups.add(group)) {
        _expandedGroups.remove(group);
      }
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Map<String, List<ArxivCategory>> _filteredGroups() {
    final grouped = groupedArxivCategories();
    final needle = _filterText.trim().toLowerCase();
    if (needle.isEmpty) return grouped;

    final filtered = <String, List<ArxivCategory>>{};
    for (final entry in grouped.entries) {
      final matches = entry.value.where((category) {
        return category.code.toLowerCase().contains(needle) ||
            category.label.toLowerCase().contains(needle) ||
            category.group.toLowerCase().contains(needle);
      }).toList();
      if (matches.isNotEmpty) {
        filtered[entry.key] = matches;
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groupedCategories = _filteredGroups();
    final hasActiveCategory =
        widget.selectedCategory != null ||
        categoryFromSearchInput(widget.currentQuery) != null;

    return AppBottomSheetShell(
      title: "Categories",
      maxHeightFactor: 0.82,
      titleTextStyle: TextStyle(
        fontSize: 21.0,
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
        height: 1.2,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    onChanged: (value) {
                      setState(() {
                        _filterText = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: "Filter categories (e.g. astro-ph, physics, cs.LG)...",
                      prefixIcon: const Icon(Icons.search, size: 20.0),
                      suffixIcon: _filterText.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _filterController.clear();
                                setState(() {
                                  _filterText = "";
                                });
                              },
                              icon: const Icon(Icons.clear, size: 18.0),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: subtleSurfaceColor(colorScheme),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (hasActiveCategory && widget.onClearCategory != null) ...[
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: widget.onClearCategory,
                    child: const Text("Clear"),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: groupedCategories.isEmpty
                ? Center(
                    child: Text(
                      "No matching categories",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0),
                    children: [
                      for (final entry in groupedCategories.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: _CategorySectionGroup(
                            title: entry.key,
                            count: entry.value.length,
                            expanded:
                                _filterText.trim().isNotEmpty ||
                                _expandedGroups.contains(entry.key),
                            hasSelected: entry.value.any(
                              (category) => isCategorySelected(
                                category,
                                widget.currentQuery,
                                selectedCategory: widget.selectedCategory,
                              ),
                            ),
                            onToggle: () => _toggleGroup(entry.key),
                            children: [
                              for (final category in entry.value)
                                _CategoryPickerRow(
                                  category: category,
                                  selected: isCategorySelected(
                                    category,
                                    widget.currentQuery,
                                    selectedCategory: widget.selectedCategory,
                                  ),
                                  onTap: () =>
                                      widget.onCategorySelected(category),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategorySectionGroup extends StatelessWidget {
  const _CategorySectionGroup({
    required this.title,
    required this.count,
    required this.expanded,
    required this.hasSelected,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final int count;
  final bool expanded;
  final bool hasSelected;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: subtleSurfaceColor(colorScheme),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: hasSelected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12.0),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${title.toUpperCase()} ($count)",
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        height: 1.2,
                        color: hasSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.9,
                              ),
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18.0,
                    color: hasSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Divider(
                height: 1.0,
                thickness: 1.0,
                color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
            const SizedBox(height: 6.0),
            Padding(
              padding: const EdgeInsets.fromLTRB(4.0, 0.0, 4.0, 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryPickerRow extends StatelessWidget {
  const _CategoryPickerRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ArxivCategory category;
  final bool selected;
  final VoidCallback onTap;

  static const _rowRadius = 10.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      // Codes are hidden in the UI but exposed to screen readers.
      label: '${category.label}, ${category.code}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.62)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(_rowRadius),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(_rowRadius),
              splashColor: colorScheme.primary.withValues(alpha: 0.08),
              highlightColor: colorScheme.primary.withValues(alpha: 0.04),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 11.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontSize: 14.5,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      height: 1.25,
                                      color: selected
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurface,
                                    ) ??
                                const TextStyle(),
                            child: Text(categoryChipLabel(category)),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            category.code,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: selected
                                  ? colorScheme.onPrimaryContainer.withValues(
                                      alpha: 0.8,
                                    )
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    AnimatedScale(
                      scale: selected ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: selected ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          width: 22.0,
                          height: 22.0,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 14.0,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
