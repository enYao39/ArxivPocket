// ignore_for_file: file_names
import 'package:flutter/material.dart';

class IDAndDate extends StatefulWidget {
  const IDAndDate({
    super.key,
    required this.id,
    required this.date,
    required this.primaryCategory,
    this.onCategoryTap,
  });

  final String id;
  final String date;
  final String primaryCategory;
  final ValueChanged<String>? onCategoryTap;

  @override
  State<IDAndDate> createState() => _IDAndDateState();
}

class _IDAndDateState extends State<IDAndDate> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(bottom: 2.0, right: 5.0),
      child: Wrap(
        spacing: 10.0,
        runSpacing: 2.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "ID: ${widget.id}",
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12.0,
            ),
          ),
          if (widget.primaryCategory.isNotEmpty)
            widget.onCategoryTap == null
                ? Text(
                    "Category: ${widget.primaryCategory}",
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12.0,
                    ),
                  )
                : GestureDetector(
                    onTap: () => widget.onCategoryTap!(widget.primaryCategory),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7.0,
                        vertical: 2.0,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withAlpha(140),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        widget.primaryCategory,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
