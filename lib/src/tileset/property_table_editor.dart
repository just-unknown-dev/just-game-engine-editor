import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

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
    // Adding one that is there would quietly put its value (and type) back
    // to a new one's: it is changed in its own row instead.
    if (widget.properties.typeOf(name) != null) {
      widget.onInvalid?.call('"$name" is already a property: change it above');
      return;
    }
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
    TilePropertyType.color => _argb(text),
    TilePropertyType.float => switch (double.tryParse(text.trim())) {
      // `NaN` and `Infinity` read as numbers, but no file can hold them.
      final v? when v.isFinite => v,
      _ => null,
    },
    TilePropertyType.bool => text.trim() == 'true',
  };

  /// `#AARRGGBB`, or `#RRGGBB` for an opaque colour (the `#` optional).
  static int? _argb(String text) {
    final hex = text.trim().replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final n = int.tryParse(hex, radix: 16);
    if (n == null) return null;
    return hex.length == 6 ? 0xFF000000 | n : n;
  }

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
            // Its own state (a half-typed value) stays with its name when
            // a row above it goes.
            key: ValueKey(name),
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
    super.key,
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
