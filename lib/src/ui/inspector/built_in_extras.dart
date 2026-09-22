import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'component_extras.dart';
import 'field_rows.dart';
import 'collection_editor.dart';
import '../../core/scope/editor_scope.dart';
import 'package:flutter/widgets.dart';

/// What the editor itself adds to built-in components beyond their fields.
abstract final class BuiltInExtras {
  static List<ComponentEditorExtras> get all => [
    // The hierarchy stores entity ids, which mean nothing to an author: show
    // who they are, and let a click go there.
    ComponentEditorExtras(
      type: 'ChildrenComponent',
      summary: (c) {
        final n = (c as jge.ChildrenComponent).childIds.length;
        return n == 1 ? '1 child' : '$n children';
      },
      fieldEditors: {
        'childIds': (c) => _EntityLinks(
          label: c.label,
          ids: [...(c.component as jge.ChildrenComponent).childIds],
        ),
      },
    ),
    ComponentEditorExtras(
      type: 'ParentComponent',
      fieldEditors: {
        'parentId': (c) => _EntityLinks(
          label: c.label,
          ids: [?(c.component as jge.ParentComponent).parentId],
        ),
      },
    ),
    // A custom widget is whatever the game registered: offer those by
    // name, and then the properties that widget said it takes.
    ComponentEditorExtras(
      type: 'UiCustomComponent',
      summary: (c) {
        final id = (c as jge.UiCustomComponent).widgetId;
        return id.isEmpty ? 'nothing chosen' : id;
      },
      fieldEditors: {
        'widgetId': (c) => _WidgetIdField(
          label: c.label,
          value: c.value as String? ?? '',
          readOnly: c.readOnly,
          onChanged: c.onChanged,
        ),
        'props': (c) => _CustomWidgetProps(
          label: c.label,
          component: c.component as jge.UiCustomComponent,
          readOnly: c.readOnly,
          onChanged: c.onChanged,
        ),
      },
    ),
    ComponentEditorExtras(
      type: 'UiCanvasComponent',
      summary: (c) {
        final canvas = c as jge.UiCanvasComponent;
        final size =
            '${canvas.designSize.width.toInt()}'
            '×${canvas.designSize.height.toInt()}';
        return canvas.isScreen ? 'screen, $size' : size;
      },
    ),
    ComponentEditorExtras(
      type: 'SpriteAnimationComponent',
      summary: (c) {
        final clip = (c as jge.SpriteAnimationComponent).clip;
        return clip.isEmpty ? 'every frame' : clip;
      },
      // The clip is one of the atlas's tags: offer them once it has loaded.
      fieldEditors: {
        'clip': (c) => _ClipField(
          label: c.label,
          component: c.component as jge.SpriteAnimationComponent,
          readOnly: c.readOnly,
          onChanged: c.onChanged,
        ),
      },
    ),
  ];
}

/// A sprite animation's clip, chosen from the clips of its atlas.
class _ClipField extends StatelessWidget {
  const _ClipField({
    required this.label,
    required this.component,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final jge.SpriteAnimationComponent component;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  /// The clips of the atlas [component] plays from, if the engine's system
  /// has loaded it for some entity carrying this component.
  List<String> _clips(EditorScope? scope) {
    final world = scope?.world;
    if (world == null) return const [];
    for (final system in world.systems) {
      if (system is! jge.SpriteAnimationSystem) continue;
      for (final entity in world.query([jge.SpriteAnimationComponent])) {
        if (!identical(
          entity.getComponent<jge.SpriteAnimationComponent>(),
          component,
        )) {
          continue;
        }
        return system.atlasOf(entity)?.clipNames.toList() ?? const [];
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    if (readOnly) return ReadonlyRow(label: label, value: component.clip);
    final clips = _clips(EditorScopeProvider.maybeOf(context));
    if (clips.isEmpty) {
      return TextEditorRow(
        label: label,
        initialValue: component.clip,
        onSubmitted: onChanged,
      );
    }
    return DropdownEditorRow(
      label: label,
      value: component.clip,
      options: ['', ...clips],
      allowCustom: true,
      onChanged: onChanged,
    );
  }
}

/// Entity ids as the names of the entities they point at, each a link that
/// selects it.
class _EntityLinks extends StatelessWidget {
  const _EntityLinks({required this.label, required this.ids});

  final String label;
  final List<int> ids;

  @override
  Widget build(BuildContext context) {
    final scope = EditorScopeProvider.maybeOf(context);
    final world = scope?.world;
    return EntityLinkList(
      label: label,
      names: [
        for (final id in ids) (id: id, name: _nameOf(world?.getEntity(id), id)),
      ],
      onSelect: (id) {
        final entity = world?.getEntity(id);
        if (entity != null) scope!.sceneState.selectEntity(entity);
      },
    );
  }

  /// Null when the entity is gone, so the row can say so.
  static String? _nameOf(jge.Entity? entity, int id) => entity == null
      ? null
      : (entity.name?.isNotEmpty ?? false)
      ? entity.name
      : 'entity #$id';
}

/// Which widget a `UiCustomComponent` is, chosen from what the game
/// registered.
class _WidgetIdField extends StatelessWidget {
  const _WidgetIdField({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final definition in jge.UiWidgets.all) definition.id,
      // A scene naming a widget this build does not have keeps its name,
      // so opening the inspector never quietly rewrites it.
      if (value.isNotEmpty && !jge.UiWidgets.has(value)) value,
    ];
    if (readOnly || ids.isEmpty) {
      return ReadonlyRow(
        label: label,
        value: value.isEmpty ? '(none registered)' : value,
      );
    }
    return DropdownEditorRow(
      label: label,
      value: ids.contains(value) ? value : ids.first,
      options: ids,
      searchable: ids.length > 8,
      onChanged: onChanged,
    );
  }
}

/// What the scene tells a custom widget: one row per property the widget
/// said it takes, rather than a map to hand-edit.
class _CustomWidgetProps extends StatelessWidget {
  const _CustomWidgetProps({
    required this.label,
    required this.component,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final jge.UiCustomComponent component;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final definition = jge.UiWidgets.of(component.widgetId);
    // Nothing known about this widget: the raw map is better than nothing,
    // and it is what a scene from another build leaves behind.
    if (definition == null || definition.props.isEmpty) {
      return CollectionEditor(
        label: label,
        value: component.props,
        readOnly: readOnly,
        onChanged: onChanged,
      );
    }
    void set(String name, String value) {
      onChanged({...component.props, name: value});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final prop in definition.props) ...[
          _propRow(prop, set),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _propRow(jge.UiWidgetProp prop, void Function(String, String) set) {
    final value = component.props[prop.name] ?? prop.defaultValue;
    if (readOnly) return ReadonlyRow(label: prop.label, value: value);
    return switch (prop.kind) {
      jge.UiPropKind.flag => BoolEditorRow(
        label: prop.label,
        value: value == 'true',
        onChanged: (v) => set(prop.name, '$v'),
      ),
      jge.UiPropKind.number => TextEditorRow(
        label: prop.label,
        initialValue: value,
        onSubmitted: (text) {
          final parsed = double.tryParse(text.trim());
          if (parsed != null) set(prop.name, text.trim());
        },
      ),
      jge.UiPropKind.color => ColorEditorRow(
        label: prop.label,
        paintStyle: jge.ShapePaintStyle(color: _colorOf(value)),
        onChanged: (style) => set(
          prop.name,
          '#${style.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
        ),
      ),
      jge.UiPropKind.asset => AssetRefEditorRow(
        label: prop.label,
        value: value,
        extensions: const ['png', 'jpg', 'jpeg', 'webp', 'json'],
        onChanged: (path) => set(prop.name, path),
      ),
      jge.UiPropKind.text => TextEditorRow(
        label: prop.label,
        initialValue: value,
        onSubmitted: (text) => set(prop.name, text),
      ),
    };
  }

  static Color _colorOf(String value) {
    final text = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return const Color(0xFFFFFFFF);
    return Color(text.length <= 6 ? 0xFF000000 | parsed : parsed);
  }
}
