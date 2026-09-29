import 'package:flutter/material.dart';

import '../../../../core/constants/editor_constants.dart';
import '../../../../core/theme/editor_metrics.dart';

export '../../../kit/kit.dart';

/// The parts every dock is built from, so nine docks look like one editor:
/// the editor's kit — a toolbar row, a search field, filter chips with
/// counts, small icon buttons, an empty state — and a sortable table.

/// One column of a [DockTable].
class DockColumn<T> {
  const DockColumn({
    required this.label,
    required this.text,
    this.sortKey,
    this.flex = 1,
    this.width,
    this.color,
    this.numeric = false,
    this.onTap,
    this.tooltip,
  });

  final String label;
  final String Function(T row) text;

  /// A click on this column's cell, instead of the row's: a switch in a
  /// table whose rows do something else, or nothing.
  final void Function(T row)? onTap;

  /// What the cell says on hover — what a click on it will do.
  final String Function(T row)? tooltip;

  /// What to sort by; the text when null.
  final Comparable<Object?> Function(T row)? sortKey;
  final int flex;

  /// A fixed width instead of a share of the room.
  final double? width;
  final Color? Function(T row)? color;
  final bool numeric;
}

/// A virtualised table: click a header to sort, a row to pick it. Built for
/// thousands of rows — only the ones on screen exist.
class DockTable<T> extends StatefulWidget {
  const DockTable({
    super.key,
    required this.rows,
    required this.columns,
    this.onTap,
    this.isSelected,
    this.empty,
    this.rowHeight,
  });

  final List<T> rows;
  final List<DockColumn<T>> columns;
  final ValueChanged<T>? onTap;
  final bool Function(T row)? isSelected;
  final Widget? empty;

  /// A row's height; 22, or taller with bigger targets, when null.
  final double? rowHeight;

  @override
  State<DockTable<T>> createState() => _DockTableState<T>();
}

class _DockTableState<T> extends State<DockTable<T>> {
  int? _sortColumn;
  bool _ascending = true;

  List<T> get _sorted {
    final at = _sortColumn;
    if (at == null || at >= widget.columns.length) return widget.rows;
    final column = widget.columns[at];
    Comparable<Object?> key(T row) =>
        column.sortKey?.call(row) ??
        (column.text(row).toLowerCase() as Comparable<Object?>);
    final out = List<T>.of(widget.rows)
      ..sort((a, b) => Comparable.compare(key(a), key(b)));
    return _ascending ? out : out.reversed.toList();
  }

  Widget _cell(DockColumn<T> column, Widget child) => column.width != null
      ? SizedBox(width: column.width, child: child)
      : Expanded(flex: column.flex, child: child);

  Widget _cellText(DockColumn<T> column, T row) {
    Widget text = Text(
      column.text(row),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: column.numeric ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: column.color?.call(row) ?? EditorTheme.textSecondary,
        fontSize: 11,
        fontFeatures: column.numeric
            ? const [FontFeature.tabularFigures()]
            : null,
      ),
    );
    final onTap = column.onTap;
    if (onTap != null) {
      text = InkWell(
        onTap: () => onTap(row),
        child: SizedBox.expand(
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      );
    }
    final tip = column.tooltip?.call(row);
    return tip == null ? text : Tooltip(message: tip, child: text);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return Column(
      children: [
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: EditorTheme.surfaceDarker,
          child: Row(
            children: [
              for (var i = 0; i < widget.columns.length; i++)
                _cell(
                  widget.columns[i],
                  InkWell(
                    onTap: () => setState(() {
                      _ascending = _sortColumn == i ? !_ascending : true;
                      _sortColumn = i;
                    }),
                    child: Row(
                      mainAxisAlignment: widget.columns[i].numeric
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            widget.columns[i].label.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: EditorTheme.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (_sortColumn == i)
                          Icon(
                            _ascending
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                            size: 14,
                            color: EditorTheme.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? (widget.empty ?? const SizedBox.shrink())
              : ListView.builder(
                  itemExtent: widget.rowHeight ?? EditorMetrics.minTarget - 2,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final selected = widget.isSelected?.call(row) ?? false;
                    return InkWell(
                      onTap: widget.onTap == null
                          ? null
                          : () => widget.onTap!(row),
                      child: Container(
                        color: selected
                            ? EditorTheme.selectionBg
                            : index.isOdd
                            ? EditorTheme.textPrimary.withValues(alpha: 0.02)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            for (final column in widget.columns)
                              _cell(column, _cellText(column, row)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
