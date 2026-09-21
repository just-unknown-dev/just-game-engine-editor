import 'package:flutter/material.dart';

import '../../../../core/constants/editor_constants.dart';

/// The parts every dock is built from, so nine docks look like one editor:
/// a toolbar row, a search field, filter chips with counts, small icon
/// buttons, an empty state, and a sortable table.

/// The row of controls at the top of a dock.
class DockToolbar extends StatelessWidget {
  const DockToolbar({super.key, required this.children});

  final List<Widget> children;

  static const double height = 32;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(children: children),
  );
}

/// A compact search box. [onChanged] fires as the text changes.
class DockSearchField extends StatefulWidget {
  const DockSearchField({
    super.key,
    required this.onChanged,
    this.initial = '',
    this.hint = 'Search',
    this.width = 220,
  });

  final ValueChanged<String> onChanged;
  final String initial;
  final String hint;
  final double width;

  @override
  State<DockSearchField> createState() => _DockSearchFieldState();
}

class _DockSearchFieldState extends State<DockSearchField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 24,
    child: TextField(
      controller: _text,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: EditorTheme.surfaceDarker,
        hintText: widget.hint,
        hintStyle: const TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 13,
          color: EditorTheme.textMuted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 24),
        suffixIcon: _text.text.isEmpty
            ? null
            : InkWell(
                onTap: () {
                  _text.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                child: const Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: EditorTheme.textMuted,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 22),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
          borderSide: BorderSide(color: EditorTheme.primaryMutedLight),
        ),
      ),
    ),
  );
}

/// A toggle that says how many things it would show: `Errors 3`.
class DockFilterChip extends StatelessWidget {
  const DockFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color = EditorTheme.primaryBright,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Material(
      color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.6)
                  : EditorTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 11,
                  color: selected ? color : EditorTheme.textMuted,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? EditorTheme.textPrimary
                      : EditorTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? color : EditorTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// A small square icon button for a dock's toolbar.
class DockIconButton extends StatelessWidget {
  const DockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.color = EditorTheme.primaryBright,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 400),
    child: Material(
      color: isActive ? color.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 24,
          child: Icon(
            icon,
            size: 14,
            color: onTap == null
                ? EditorTheme.textMuted.withValues(alpha: 0.4)
                : isActive
                ? color
                : EditorTheme.textSecondary,
          ),
        ),
      ),
    ),
  );
}

/// What a dock shows when it has nothing to show, and what to do about it.
class DockEmptyState extends StatelessWidget {
  const DockEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? hint;

  /// The one thing to do from here — "Add a Timeline Player". Shown only
  /// with [onAction].
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: EditorTheme.textMuted),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: EditorTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ],
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 26,
            child: ElevatedButton.icon(
              onPressed: onAction,
              // Stated in full: the ambient Material theme is the light
              // default, and its primary is not this editor's.
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTheme.buttonBg,
                foregroundColor: EditorTheme.primary,
                disabledBackgroundColor: EditorTheme.buttonBg,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: const BorderSide(color: EditorTheme.border),
                ),
              ),
              icon: Icon(actionIcon ?? Icons.add_rounded, size: 14),
              label: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

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
  });

  final String label;
  final String Function(T row) text;

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
    this.rowHeight = 22,
  });

  final List<T> rows;
  final List<DockColumn<T>> columns;
  final ValueChanged<T>? onTap;
  final bool Function(T row)? isSelected;
  final Widget? empty;
  final double rowHeight;

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
                            style: const TextStyle(
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
                  itemExtent: widget.rowHeight,
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
                              _cell(
                                column,
                                Text(
                                  column.text(row),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: column.numeric
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: TextStyle(
                                    color:
                                        column.color?.call(row) ??
                                        EditorTheme.textSecondary,
                                    fontSize: 11,
                                    fontFeatures: column.numeric
                                        ? const [FontFeature.tabularFigures()]
                                        : null,
                                  ),
                                ),
                              ),
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
