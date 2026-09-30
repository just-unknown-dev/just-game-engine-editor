import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/editor_constants.dart';

/// One choice in an [EditorDropdown].
class EditorDropdownOption<T> {
  const EditorDropdownOption({
    required this.value,
    required this.label,
    this.color,
    this.detail,
  });

  final T value;
  final String label;

  /// A dot before the label — a tag's colour.
  final Color? color;

  /// Muted text after it: how many use it, where it comes from.
  final String? detail;
}

/// The editor's dropdown: a field the same height as the text and number
/// fields beside it, opening a compact list directly below.
///
/// The stock Material `DropdownButton` is 48 px tall and opens *over* itself
/// with 48 px items, which in an inspector of 28 px fields reads as a row from
/// another application. This one matches the fields, ticks the current value,
/// and — when [searchable] — filters as you type, which is what makes picking
/// one entity out of a level's worth workable.
class EditorDropdown<T> extends StatelessWidget {
  const EditorDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.searchable = false,
    this.customValue,
    this.customLabel,
    this.isExpanded = true,
    this.height,
    this.fontSize = 11,
    this.tooltip,
  });

  /// Space above and below the label when no [height] is given — the same as
  /// the editor's text and number fields, so a dropdown is exactly as tall as
  /// they are at any font and text scale rather than at one guessed number.
  static const double fieldPadding = 8;

  /// Height of one entry in the opened list.
  static const double itemHeight = 26;

  /// The list scrolls past this.
  static const double maxMenuHeight = 264;

  /// The selected value, or null to show [hint].
  final T? value;
  final List<EditorDropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Shown, muted, when [value] is null or not among [options].
  final String? hint;

  /// Puts a filter box at the top of the list.
  final bool searchable;

  /// With [searchable]: turns what was typed into a value, so something that
  /// is not in the list yet can still be chosen. Null forbids it.
  final T Function(String typed)? customValue;

  /// How the entry for a typed value reads; `Use "…"` when null. A tag
  /// picker says `Create tag "…"`, or why it cannot.
  final String Function(String typed)? customLabel;

  /// Fills the width it is given. Off, it is as wide as its label — for a
  /// toolbar, where there is no column to fill.
  final bool isExpanded;

  /// A fixed height, for a toolbar. Null sizes it like a text field: the
  /// label plus [fieldPadding] above and below.
  final double? height;
  final double fontSize;
  final String? tooltip;

  EditorDropdownOption<T>? get _selected {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  String? get _label => _selected?.label;

  Future<void> _open(BuildContext context) async {
    final chosen = await openEditorDropdownMenu<T>(
      context,
      options: options,
      selected: value,
      searchable: searchable,
      customValue: customValue,
      customLabel: customLabel,
      fontSize: fontSize,
    );
    if (chosen != null) onChanged(chosen.value);
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    final text = Text(
      label ?? hint ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: label == null ? EditorTheme.textMuted : EditorTheme.textPrimary,
        fontSize: fontSize,
        // A text field lays its text out on the theme's bodyLarge line
        // height; a bare Text inherits bodyMedium's. Sharing it is what makes
        // the two fields the same height to the pixel.
        height: height == null
            ? Theme.of(context).textTheme.bodyLarge?.height
            : null,
      ),
    );
    final field = Material(
      color: EditorTheme.inputBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: EditorTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: options.isEmpty && customValue == null
            ? null
            : () => _open(context),
        hoverColor: EditorTheme.hoverBg,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              8,
              height == null ? fieldPadding : 0,
              4,
              height == null ? fieldPadding : 0,
            ),
            child: Row(
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (_selected?.color case final dot?) ...[
                  _Dot(dot),
                  const SizedBox(width: 6),
                ],
                if (isExpanded)
                  Expanded(child: text)
                else
                  Flexible(child: text),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  // Never taller than the label's line, so it cannot set the height.
                  size: height == null
                      ? fontSize + 2
                      : math.min(16, height! - 8),
                  color: EditorTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? field : Tooltip(message: tooltip, child: field);
  }
}

/// A tag's colour, before its name.
class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Opens an [EditorDropdown]'s list below whatever [anchor] is the context
/// of — for a button that is not a dropdown field but offers the same list:
/// a "⋮" menu's "Add tag…". Null when it was dismissed.
Future<EditorChoice<T>?> openEditorDropdownMenu<T>(
  BuildContext anchor, {
  required List<EditorDropdownOption<T>> options,
  T? selected,
  bool searchable = false,
  T Function(String typed)? customValue,
  String Function(String typed)? customLabel,
  double fontSize = 11,
  double? width,
  double gap = 0,
}) {
  final field = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  // Anchored to the field's bottom edge: the list opens below, and showMenu
  // moves it up only when there is no room.
  final rect = Rect.fromPoints(
    field.localToGlobal(field.size.bottomLeft(Offset.zero), ancestor: overlay),
    field.localToGlobal(field.size.bottomRight(Offset.zero), ancestor: overlay),
  ).translate(0, gap);
  final w = width ?? math.max(field.size.width, searchable ? 200.0 : 120.0);
  return showMenu<EditorChoice<T>>(
    context: anchor,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: EditorTheme.menuBg,
    elevation: 6,
    menuPadding: EdgeInsets.zero,
    constraints: BoxConstraints(minWidth: w, maxWidth: w),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: EditorTheme.border),
    ),
    items: [
      _MenuBody<T>(
        options: options,
        selected: selected,
        searchable: searchable,
        customValue: customValue,
        customLabel: customLabel,
        fontSize: fontSize,
      ),
    ],
  );
}

/// What the menu pops with. A wrapper, because a popup treats a null result
/// as "dismissed" and a dropdown's value may legitimately be null-like.
class EditorChoice<T> {
  const EditorChoice(this.value);
  final T value;
}

/// The whole opened list as one menu entry, so it can hold a filter box and
/// change what it shows as you type.
class _MenuBody<T> extends PopupMenuEntry<EditorChoice<T>> {
  const _MenuBody({
    required this.options,
    required this.selected,
    required this.searchable,
    required this.customValue,
    required this.fontSize,
    this.customLabel,
  });

  final List<EditorDropdownOption<T>> options;
  final T? selected;
  final bool searchable;
  final T Function(String typed)? customValue;
  final String Function(String typed)? customLabel;
  final double fontSize;

  @override
  double get height => EditorDropdown.itemHeight;

  @override
  bool represents(EditorChoice<T>? value) => false;

  @override
  State<_MenuBody<T>> createState() => _MenuBodyState<T>();
}

class _MenuBodyState<T> extends State<_MenuBody<T>> {
  String _query = '';

  List<EditorDropdownOption<T>> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final option in widget.options)
        if (option.label.toLowerCase().contains(q)) option,
    ];
  }

  /// What was typed, when it may be chosen as it stands.
  String? get _custom {
    final typed = _query.trim();
    if (widget.customValue == null || typed.isEmpty) return null;
    final known = widget.options.any(
      (o) => o.label.toLowerCase() == typed.toLowerCase(),
    );
    return known ? null : typed;
  }

  void _choose(T value) => Navigator.of(context).pop(EditorChoice<T>(value));

  void _submit() {
    final shown = _shown;
    if (shown.isNotEmpty) {
      _choose(shown.first.value);
    } else if (_custom case final typed?) {
      _choose(widget.customValue!(typed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final custom = _custom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.searchable) _searchBox(),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: EditorDropdown.maxMenuHeight,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 3),
            children: [
              for (final option in shown)
                _item(
                  option.label,
                  selected: option.value == widget.selected,
                  onTap: () => _choose(option.value),
                  color: option.color,
                  detail: option.detail,
                ),
              if (custom != null)
                _item(
                  widget.customLabel?.call(custom) ?? 'Use "$custom"',
                  selected: false,
                  muted: true,
                  onTap: () => _choose(widget.customValue!(custom)),
                ),
              if (shown.isEmpty && custom == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Text(
                    'Nothing matches',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: widget.fontSize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchBox() => Container(
    height: 30,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorTheme.border)),
    ),
    child: TextField(
      autofocus: true,
      onChanged: (text) => setState(() => _query = text),
      onSubmitted: (_) => _submit(),
      inputFormatters: [LengthLimitingTextInputFormatter(80)],
      style: TextStyle(
        color: EditorTheme.textPrimary,
        fontSize: widget.fontSize,
      ),
      cursorColor: EditorTheme.primary,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        prefixIcon: Icon(Icons.search, size: 14, color: EditorTheme.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 26),
        hintText: 'Search',
        hintStyle: TextStyle(
          color: EditorTheme.textMuted,
          fontSize: widget.fontSize,
        ),
      ),
    ),
  );

  Widget _item(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    bool muted = false,
    Color? color,
    String? detail,
  }) => InkWell(
    onTap: onTap,
    hoverColor: EditorTheme.hoverBg,
    child: Container(
      height: EditorDropdown.itemHeight,
      color: selected ? EditorTheme.selectionBg : null,
      padding: const EdgeInsets.only(left: 6, right: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: selected
                ? Icon(Icons.check, size: 12, color: EditorTheme.primary)
                : null,
          ),
          if (color != null) ...[_Dot(color), const SizedBox(width: 6)],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted
                    ? EditorTheme.textSecondary
                    : selected
                    ? EditorTheme.textBright
                    : EditorTheme.textPrimary,
                fontSize: widget.fontSize,
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              detail,
              maxLines: 1,
              style: TextStyle(
                color: EditorTheme.textMuted,
                fontSize: widget.fontSize - 1,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
