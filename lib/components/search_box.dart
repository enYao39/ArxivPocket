// ignore_for_file: file_names
import 'package:arxiv/apis/arxiv.dart';
import 'package:arxiv/components/category_picker_sheet.dart';
import 'package:arxiv/data/arxiv_categories.dart';
import 'package:arxiv/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.searchTermController,
    required this.searchFunction,
    required this.sortOption,
    required this.onSortOptionChanged,
    required this.onCategorySelected,
    this.onClearCategory,
    this.onOpenAdvancedSearch,
    this.selectedCategory,
  });

  final TextEditingController searchTermController;
  final Future<void> Function({bool? resetPagination}) searchFunction;
  final ArxivSortOption sortOption;
  final Future<void> Function(ArxivSortOption option) onSortOptionChanged;
  final ValueChanged<ArxivCategory> onCategorySelected;
  final Future<void> Function()? onClearCategory;
  final VoidCallback? onOpenAdvancedSearch;
  final ArxivCategory? selectedCategory;

  Future<void> clearSearchQuery() async {
    searchTermController.clear();
    // Empty input reloads suggested papers (or active category) instead of running a blank search.
    await searchFunction(resetPagination: true);
  }

  void openCategoryPicker(BuildContext context) {
    showCategoryPickerSheet(
      context,
      currentQuery: searchTermController.text.trim(),
      selectedCategory: selectedCategory,
      onClearCategory: onClearCategory == null
          ? null
          : () {
              onClearCategory!();
            },
      onCategorySelected: onCategorySelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(left: 10.0, right: 10.0),
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(color: colorScheme.surface),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 18.0, right: 18.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30.0),
                color: subtleSurfaceColor(colorScheme),
              ),
              child: TextField(
                controller: searchTermController,
                keyboardType: TextInputType.url,
                cursorColor: colorScheme.primary,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: selectedCategory != null
                      ? "Search in ${selectedCategory!.code}..."
                      : "Search, author, or arXiv ID/URL...",
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
                  suffixIcon: searchTermController.text.isNotEmpty
                      ? IconButton(
                          onPressed: clearSearchQuery,
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                ),
                onSubmitted: (searchTerm) async {
                  await searchFunction(resetPagination: true);
                },
              ),
            ),
          ),
          if (onOpenAdvancedSearch != null)
            IconButton(
              tooltip: "Advanced search",
              onPressed: onOpenAdvancedSearch,
              icon: const Icon(Icons.tune),
            ),
          IconButton(
            tooltip: "Browse categories",
            onPressed: () => openCategoryPicker(context),
            icon: Icon(
              Icons.category_outlined,
              color: selectedCategory != null ? colorScheme.primary : null,
            ),
          ),
          PopupMenuButton<ArxivSortOption>(
            tooltip: "Sort: ${sortOption.label}",
            initialValue: sortOption,
            onSelected: (option) async {
              await onSortOptionChanged(option);
            },
            itemBuilder: (context) => ArxivSortOption.values
                .map(
                  (option) => PopupMenuItem<ArxivSortOption>(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          option == sortOption
                              ? Icons.check
                              : Icons.sort,
                          size: 18.0,
                          color: option == sortOption
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10.0),
                        Text(option.label),
                      ],
                    ),
                  ),
                )
                .toList(),
            icon: Icon(
              Icons.sort,
              color: sortOption != ArxivSortOption.relevance
                  ? colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            tooltip: "Search",
            onPressed: () async {
              await searchFunction(resetPagination: true);
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }
}
