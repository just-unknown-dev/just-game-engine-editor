import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
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
          world: c.world,
          sceneState: c.sceneState,
        ),
      },
    ),
    ComponentEditorExtras(
      type: 'ParentComponent',
      fieldEditors: {
        'parentId': (c) => _EntityLinks(
          label: c.label,
          ids: [?(c.component as jge.ParentComponent).parentId],
          world: c.world,
          sceneState: c.sceneState,
        ),
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
  const _EntityLinks({
    required this.label,
    required this.ids,
    this.world,
    this.sceneState,
  });

  final String label;
  final List<int> ids;

  /// Where the ids are looked up and selected, the scene's unless given:
  /// a screen's ids mean nothing in the level.
  final jge.World? world;
  final EditorSceneState? sceneState;

  @override
  Widget build(BuildContext context) {
    final scope = EditorScopeProvider.maybeOf(context);
    final world = this.world ?? scope?.world;
    final selection = sceneState ?? scope?.sceneState;
    return EntityLinkList(
      label: label,
      names: [
        for (final id in ids) (id: id, name: _nameOf(world?.getEntity(id), id)),
      ],
      onSelect: (id) {
        final entity = world?.getEntity(id);
        if (entity != null) selection?.selectEntity(entity);
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
