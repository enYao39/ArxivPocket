// ignore_for_file: file_names
import 'package:flutter/material.dart';

class IDAndDate extends StatefulWidget {
  const IDAndDate({
    super.key,
    required this.id,
    required this.date,
    required this.primaryCategory,
    this.onCategoryTap,
    this.isNew = false,
    this.isRead = false,
    this.onToggleRead,
  });

  final String id;
  final String date;
  final String primaryCategory;
  final ValueChanged<String>? onCategoryTap;
  final bool isNew;
  final bool isRead;
  final VoidCallback? onToggleRead;

  @override
  State<IDAndDate> createState() => _IDAndDateState();
}

class _IDAndDateState extends State<IDAndDate> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
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
                          onTap: () =>
                              widget.onCategoryTap!(widget.primaryCategory),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withAlpha(
                                140,
                              ),
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
                if (widget.isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 2.0,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Text(
                      "NEW",
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onToggleRead != null) ...[
            const SizedBox(width: 8.0),
            Tooltip(
              message: widget.isRead ? "Mark as unread" : "Mark as read",
              child: InkWell(
                onTap: widget.onToggleRead,
                borderRadius: BorderRadius.circular(12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.0,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isRead
                        ? colorScheme.surfaceContainerHighest.withAlpha(180)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: widget.isRead
                          ? colorScheme.outlineVariant.withAlpha(140)
                          : colorScheme.outlineVariant.withAlpha(100),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isRead
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 13.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      if (widget.isRead) ...[
                        const SizedBox(width: 4.0),
                        Text(
                          "Read",
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
