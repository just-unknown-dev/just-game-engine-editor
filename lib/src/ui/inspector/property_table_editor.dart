import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import 'field_rows.dart';

/// A table of custom properties — a tile's, a map shape's: each with its
/// value to change or take off, and a row to add another of any type.
///
/// It only shows; [onSet] and [onRemove] make the change, so whoever owns
/// the properties records it their way.
class PropertyTableEditor extends StatefulWidget {
  const PropertyTableEditor({
    super.key,
    required this.properties,
    required this.onSet,
    required this.onRemove,
    this.onInvalid,
    this.labelWidth = 76,
  });

  final TileProperties properties;

  /// Sets [name] to [value], of [type] — a new one, or a change.
  final void Function(String name, Object? value, TilePropertyType type) onSet;

  final void Function(String name) onRemove;

  /// Told when a typed-in value is not of its property's type.
  final void Function(String message)? onInvalid;

  final double labelWidth;

  @override
  State<PropertyTableEditor> createState() => _PropertyTableEditorState();
}

class _PropertyTableEditorState extends State<PropertyTableEditor> {
  TilePropertyType _newType = TilePropertyType.string;
  final TextEditingController _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  void _add() {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    widget.onSet(name, defaultOf(_newType), _newType);
    _newName.clear();
  }

  /// What a new property of [type] starts as.
  static Object? defaultOf(TilePropertyType type) => switch (type) {
    TilePropertyType.string || TilePropertyType.file => '',
    TilePropertyType.int ||
    TilePropertyType.object ||
    TilePropertyType.color => 0,
    TilePropertyType.float => 0.0,
    TilePropertyType.bool => false,
  };

  /// [text] as a value of [type]; null when it is not one.
  static Object? parse(TilePropertyType type, String text) => switch (type) {
    TilePropertyType.string || TilePropertyType.file => text,
    TilePropertyType.int ||
    TilePropertyType.object => int.tryParse(text.trim()),
    TilePropertyType.color => int.tryParse(
      text.trim().replaceFirst('#', ''),
      radix: 16,
    ),
    TilePropertyType.float => double.tryParse(text.trim()),
    TilePropertyType.bool => text.trim() == 'true',
  };

  static String _show(TilePropertyType type, Object? value) => switch (type) {
    TilePropertyType.color when value is int =>
      '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    _ => '${value ?? ''}',
  };

  @override
  Widget build(BuildContext context) {
    final props = widget.properties;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final name in props.names.toList())
          _Row(
            label: name,
            labelWidth: widget.labelWidth,
            trailing: IconButton(
              tooltip: 'Remove $name',
              iconSize: 13,
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onRemove(name),
              icon: Icon(Icons.close, color: EditorTheme.textMuted),
            ),
            child: props.typeOf(name) == TilePropertyType.bool
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Checkbox(
                      value: props.getBool(name) ?? false,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          widget.onSet(name, v ?? false, TilePropertyType.bool),
                    ),
                  )
                : MiniTextField(
                    value: _show(props.typeOf(name)!, props[name]),
                    // What does not read as the property's type is not kept:
                    // the field shows the value it has again, and says why.
                    accept: (v) {
                      final type = props.typeOf(name)!;
                      if (parse(type, v) != null) return true;
                      widget.onInvalid?.call('"$v" is not a ${type.name}');
                      return false;
                    },
                    onSubmitted: (v) {
                      final type = props.typeOf(name)!;
                      final value = parse(type, v);
                      if (value != null) widget.onSet(name, value, type);
                    },
                  ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newName,
                style: TextStyle(fontSize: 11, color: EditorTheme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New property',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: EditorTheme.textMuted,
                  ),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<TilePropertyType>(
              tooltip: 'Its type',
              color: EditorTheme.menuBg,
              onSelected: (t) => setState(() => _newType = t),
              itemBuilder: (context) => [
                for (final t in TilePropertyType.values)
                  PopupMenuItem(
                    value: t,
                    height: 26,
                    child: Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: EditorTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
              child: Text(
                _newType.name,
                style: TextStyle(
                  fontSize: 11,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Add the property',
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              onPressed: _add,
              icon: Icon(Icons.add, color: EditorTheme.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.child,
    required this.labelWidth,
    this.trailing,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
          ),
        ),
        Expanded(child: child),
        ?trailing,
      ],
    ),
  );
}
