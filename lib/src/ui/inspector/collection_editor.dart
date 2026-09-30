import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../kit/fields.dart';
import 'field_style.dart';

/// Edits a list or a map field as rows, not as JSON.
///
/// A list of plain values is a column of cells; a list of objects is a stack
/// of small cards, one row per key; a map is key / value pairs. Every value
/// keeps the type it had — a number stays a number — and "Add" makes a copy of
/// [template], or of the last item when there is none, so a new entry starts
/// with the right shape instead of an empty brace to fill in by hand.
///
/// The label sits above the items rather than beside them: a collection needs
/// the panel's whole width.
class CollectionEditor extends StatelessWidget {
  const CollectionEditor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.template,
    this.description,
    this.itemCell,
  });

  final String label;

  /// The whole row for one key of an object item, when that key needs more
  /// than a plain cell — a target, a tag. Null, or a null answer, keeps the
  /// plain cell.
  final Widget? Function(
    String key,
    Object? value,
    ValueChanged<Object?> onChanged,
  )?
  itemCell;

  /// A `List` or a `Map`; anything else is shown as text.
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool readOnly;

  /// What a new item looks like: a value for a list, a value for a map's new
  /// key. Null falls back to a copy of the last item, then to empty text.
  final Object? template;
  final String? description;

  static Object? _copy(Object? v) => switch (v) {
    Map() => {for (final e in v.entries) e.key: _copy(e.value)},
    List() => [for (final x in v) _copy(x)],
    _ => v,
  };

  /// A fresh value of the same kind as [like]: numbers to zero, text to
  /// empty, objects key by key.
  static Object? _blank(Object? like) => switch (like) {
    Map() => {for (final e in like.entries) e.key: _blank(e.value)},
    List() => <Object?>[],
    int() => 0,
    double() => 0.0,
    bool() => false,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final v = value;
    final isMap = v is Map;
    final count = v is Map ? v.length : (v is List ? v.length : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: InspectorField.labelStyle),
            const SizedBox(width: 6),
            _CountPill(count),
            const Spacer(),
            if (!readOnly && (v is List || v is Map))
              _IconAction(
                icon: Icons.add_rounded,
                tooltip: isMap ? 'Add an entry' : 'Add an item',
                onTap: () => isMap ? _addEntry(v) : _addItem(v as List),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (v is List)
          ..._listRows(v)
        else if (v is Map)
          ..._mapRows(v)
        else
          _Muted(v == null ? 'None' : '$v'),
        if (count == 0 && (v is List || v is Map)) const _Muted('Empty'),
      ],
    );
  }

  // ── Lists ────────────────────────────────────────────────────────────────

  void _addItem(List list) {
    final like = template ?? (list.isEmpty ? '' : _blank(list.last));
    onChanged([...list, _copy(like)]);
  }

  List<Widget> _listRows(List list) => [
    for (var i = 0; i < list.length; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: list[i] is Map
            ? _ItemCard(
                index: i,
                item: list[i] as Map,
                readOnly: readOnly,
                itemCell: readOnly ? null : itemCell,
                onChanged: (next) => onChanged([...list]..[i] = next),
                onRemove: () => onChanged([...list]..removeAt(i)),
              )
            : Row(
                children: [
                  _IndexChip(i),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Cell(
                      value: list[i],
                      readOnly: readOnly,
                      onChanged: (next) => onChanged([...list]..[i] = next),
                    ),
                  ),
                  if (!readOnly)
                    _IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Remove',
                      onTap: () => onChanged([...list]..removeAt(i)),
                    ),
                ],
              ),
      ),
  ];

  // ── Maps ─────────────────────────────────────────────────────────────────

  void _addEntry(Map map) {
    var n = map.length + 1;
    while (map.containsKey('key$n')) {
      n++;
    }
    final like = template ?? (map.isEmpty ? '' : _blank(map.values.last));
    onChanged({...map, 'key$n': _copy(like)});
  }

  List<Widget> _mapRows(Map map) => [
    for (final entry in map.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: _Cell(
                value: '${entry.key}',
                readOnly: readOnly,
                // Renaming keeps the entry where it was.
                onChanged: (next) {
                  final key = '$next'.trim();
                  if (key.isEmpty || key == entry.key) return;
                  if (map.containsKey(key)) return;
                  onChanged({
                    for (final e in map.entries)
                      (e.key == entry.key ? key : e.key): e.value,
                  });
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.arrow_right_alt_rounded,
                size: 14,
                color: EditorTheme.textMuted,
              ),
            ),
            Expanded(
              flex: 6,
              child: _Cell(
                value: entry.value,
                readOnly: readOnly,
                onChanged: (next) => onChanged({...map, entry.key: next}),
              ),
            ),
            if (!readOnly)
              _IconAction(
                icon: Icons.close_rounded,
                tooltip: 'Remove',
                onTap: () => onChanged({...map}..remove(entry.key)),
              ),
          ],
        ),
      ),
  ];
}

/// One object of a list, as a small card: `#2`, its keys, a remove button.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.index,
    required this.item,
    required this.readOnly,
    required this.onChanged,
    required this.onRemove,
    this.itemCell,
  });

  final int index;
  final Map item;
  final bool readOnly;
  final ValueChanged<Map> onChanged;
  final VoidCallback onRemove;
  final Widget? Function(String, Object?, ValueChanged<Object?>)? itemCell;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 2, 6),
      decoration: BoxDecoration(
        color: EditorTheme.inputBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IndexChip(index),
              const Spacer(),
              if (!readOnly)
                _IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove',
                  onTap: onRemove,
                ),
            ],
          ),
          for (final entry in item.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child:
                  itemCell?.call(
                    '${entry.key}',
                    entry.value,
                    (next) => onChanged({...item, entry.key: next}),
                  ) ??
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${entry.key}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: EditorTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _Cell(
                          value: entry.value,
                          readOnly: readOnly,
                          onChanged: (next) =>
                              onChanged({...item, entry.key: next}),
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

/// One value, edited as what it is: a switch for a bool, a field for a
/// number or text. A nested list or map falls back to JSON in a field.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final Object? value;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  bool get _isNested => value is Map || value is List;

  Object? _parse(String text) {
    final v = value;
    if (v is Map || v is List) {
      try {
        return jsonDecode(text);
      } on FormatException {
        return v;
      }
    }
    final trimmed = text.trim();
    return switch (v) {
      int() => int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round() ?? v,
      double() => double.tryParse(trimmed) ?? v,
      _ => trimmed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v is bool) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 24,
          child: Transform.scale(
            scale: 0.7,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: v,
              activeThumbColor: EditorTheme.primary,
              onChanged: readOnly ? null : onChanged,
            ),
          ),
        ),
      );
    }
    final text = _isNested ? jsonEncode(v) : '${v ?? ''}';
    if (readOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
        ),
      );
    }
    // Kept on Enter or when the cell is left; a value changed from outside
    // — an undo, another item removed — shows while it is not being typed
    // in.
    return CommitTextField(
      value: text,
      keyboardType: v is num
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      onCommit: (t) => onChanged(_parse(t)),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        filled: true,
        fillColor: EditorTheme.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.primaryActive),
        ),
      ),
    );
  }
}

class _IndexChip extends StatelessWidget {
  const _IndexChip(this.index);

  final int index;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: EditorTheme.hoverBg,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      '${index + 1}',
      style: TextStyle(
        color: EditorTheme.textSecondary,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: EditorTheme.hoverBg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$count',
      style: TextStyle(color: EditorTheme.textSecondary, fontSize: 9),
    ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      hoverColor: EditorTheme.hoverBg,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 14, color: EditorTheme.textSecondary),
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: 10,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

/// A read-only list of references to other entities, shown by **name** and
/// clickable, instead of as the ids the engine stores.
class EntityLinkList extends StatelessWidget {
  const EntityLinkList({
    super.key,
    required this.label,
    required this.names,
    required this.onSelect,
  });

  final String label;

  /// One entry per reference; null where the entity no longer exists.
  final List<({int id, String? name})> names;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(label, style: InspectorField.labelStyle),
          const SizedBox(width: 6),
          _CountPill(names.length),
        ],
      ),
      const SizedBox(height: 4),
      if (names.isEmpty) const _Muted('None'),
      for (final entry in names)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: EditorTheme.inputBg,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: entry.name == null ? null : () => onSelect(entry.id),
              hoverColor: EditorTheme.hoverBg,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      entry.name == null
                          ? Icons.link_off_rounded
                          : Icons.subdirectory_arrow_right_rounded,
                      size: 12,
                      color: EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.name ?? 'missing entity #${entry.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: entry.name == null
                              ? EditorTheme.textMuted
                              : EditorTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
