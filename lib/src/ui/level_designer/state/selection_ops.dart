import 'dart:math' as math;
import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/entity/hierarchy_commands.dart';
import '../../../core/state/editor_scene_state.dart';
import 'component_resizer.dart';
import 'designer_geometry.dart';
import 'editor_commands.dart';
import 'editor_history.dart';
import 'prefab_registry.dart';
import '../../../core/serialization/scene_codec.dart';

/// Edits applied to a whole selection at once — each exactly one undo step.
///
/// Shared by the keyboard shortcuts and the transform panel, so nudging with
/// the arrows and typing a new X go through the same code and undo the same
/// way.
class SelectionOps {
  SelectionOps({
    required this.codec,
    required this.world,
    required this.sceneState,
    required this.history,
    required String Function(String prefix) uniqueName,
  }) : _uniqueName = uniqueName;

  /// World the entities live in.
  final jge.World world;

  /// Selection and scene-graph state.
  final EditorSceneState sceneState;

  /// Where edits are recorded.
  final EditorHistory history;

  final String Function(String prefix) _uniqueName;

  /// Combined bounds of [entities]; a sizeless marker counts as a point.
  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;

  static Rect? boundsOf(List<jge.Entity> entities) {
    Rect? union;
    for (final entity in entities) {
      var b = DesignerGeometry.worldBounds(entity);
      if (b == null) {
        final t = entity.getComponent<jge.TransformComponent>();
        if (t == null) continue;
        b = Rect.fromLTWH(t.position.x, t.position.y, 0, 0);
      }
      union = union == null ? b : union.expandToInclude(b);
    }
    return union;
  }

  // ── Transforms ────────────────────────────────────────────────────────────

  /// Moves [entities] by [delta]. A run of nudges to the same selection is
  /// one undo step, so ten taps of an arrow key undo in one go.
  void nudge(List<jge.Entity> entities, Offset delta) {
    if (entities.isEmpty || delta == Offset.zero) return;
    final ids = [for (final e in entities) e.id]..sort();
    _transform(
      entities,
      'Nudge ${_describe(entities)}',
      (t) => t.setPositionXY(t.position.x + delta.dx, t.position.y + delta.dy),
      mergeKey: 'nudge:${ids.join(',')}',
    );
  }

  /// Moves [entities] so their combined bounds' top-left is at [topLeft].
  ///
  /// Calls sharing a [mergeKey] fold into one undo step.
  void moveTo(List<jge.Entity> entities, Offset topLeft, {Object? mergeKey}) {
    final bounds = boundsOf(entities);
    if (bounds == null) return;
    final delta = topLeft - bounds.topLeft;
    if (delta == Offset.zero) return;
    _transform(
      entities,
      'Move ${_describe(entities)}',
      (t) => t.setPositionXY(t.position.x + delta.dx, t.position.y + delta.dy),
      mergeKey: mergeKey,
    );
  }

  /// Turns [entities] [quarterTurns] quarter turns clockwise about their
  /// combined centre. Positions turn exactly, so turning four times lands
  /// every entity back on the same pixel.
  void rotateQuarter(List<jge.Entity> entities, int quarterTurns) {
    final bounds = boundsOf(entities);
    if (bounds == null || quarterTurns % 4 == 0) return;
    final pivot = bounds.center;
    final turn = quarterTurns * math.pi / 2;
    _transform(entities, 'Rotate ${_describe(entities)}', (t) {
      final to = DesignerGeometry.rotateQuarter(
        Offset(t.position.x, t.position.y),
        pivot,
        quarterTurns,
      );
      t
        ..setPositionXY(to.dx, to.dy)
        ..rotation = _normalise(t.rotation + turn);
    });
  }

  /// Sets every one of [entities] to [radians], each about its own centre.
  void setRotation(
    List<jge.Entity> entities,
    double radians, {
    Object? mergeKey,
  }) => _transform(
    entities,
    'Rotate ${_describe(entities)}',
    (t) => t.rotation = radians,
    mergeKey: mergeKey,
    // An angle, not a turn: what is under them keeps its own.
    carry: false,
  );

  void _transform(
    List<jge.Entity> entities,
    String label,
    void Function(jge.TransformComponent t) change, {
    Object? mergeKey,
    bool carry = true,
  }) {
    if (entities.isEmpty) return;
    // A move or a turn takes what is under the entities along: [change] is
    // the same for any point, so it is simply applied to them too.
    final all = [
      ...entities,
      if (carry) ...carriedWith(entities, world: world),
    ];
    final before = all.map(TransformSnapshot.of).toList(growable: false);
    for (final e in all) {
      final t = e.getComponent<jge.TransformComponent>();
      if (t == null) continue;
      change(t);
      sceneState.syncEntityNode(e);
    }
    final after = all.map(TransformSnapshot.of).toList(growable: false);
    var changed = false;
    for (var i = 0; i < before.length; i++) {
      if (!before[i].matches(after[i])) changed = true;
    }
    if (!changed) return;
    _record(
      TransformCommand(
        label: label,
        entities: all,
        before: before,
        after: after,
        sceneState: sceneState,
        mergeKey: mergeKey,
      ),
    );
  }

  void _record(EditorCommand command) {
    history.pushApplied(command);
    sceneState
      ..markDirty()
      ..refresh();
  }

  // ── Whole-entity edits ────────────────────────────────────────────────────

  /// Mirrors [entities] across their combined centre.
  ///
  /// Positions mirror, rotations negate (a reflection reverses turning), and a
  /// sprite's own flip flag toggles so the image mirrors with its entity.
  /// Rectangles and circles are symmetric and need nothing more.
  void flip(List<jge.Entity> entities, {required bool horizontal}) {
    final bounds = boundsOf(entities);
    if (bounds == null) return;
    _flipEntities(
      entities,
      'Flip ${_describe(entities)}',
      bounds.center,
      horizontal: horizontal,
    );
  }

  void _flipEntities(
    List<jge.Entity> entities,
    String label,
    Offset pivot, {
    required bool horizontal,
  }) {
    _edit(entities, label, (e) {
      final t = e.getComponent<jge.TransformComponent>();
      if (t != null) {
        final to = DesignerGeometry.mirror(
          Offset(t.position.x, t.position.y),
          pivot,
          horizontal: horizontal,
        );
        t
          ..setPositionXY(to.dx, to.dy)
          ..rotation = _normalise(-t.rotation);
      }
      // Whatever a component's own flip means (a sprite's flag, say), its
      // definition's extent knows; the editor does not.
      for (final c in e.components) {
        jge.ComponentDefinitionRegistry.instance
            .definitionFor(c)
            ?.extent
            ?.flip(c, horizontal: horizontal);
      }
    });
  }

  /// Resizes and moves [entities] so their combined bounds become [to], each
  /// keeping its proportional place — the numeric counterpart of dragging a
  /// corner handle.
  void resizeTo(List<jge.Entity> entities, Rect to, {Object? mergeKey}) {
    final from = boundsOf(entities);
    if (from == null || from.width <= 0 || from.height <= 0) return;
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    _edit(entities, 'Resize ${_describe(entities)}', mergeKey: mergeKey, (e) {
      ComponentResizer.scale(e, sx, sy);
      final t = e.getComponent<jge.TransformComponent>();
      if (t == null) return;
      final p = DesignerGeometry.mapPoint(
        Offset(t.position.x, t.position.y),
        from,
        to,
      );
      t.setPositionXY(p.dx, p.dy);
    });
  }

  /// Replaces each of [entities] with [prefab], built at the same place and
  /// size, on the same layer, under the same parent. One undo step for the
  /// whole swap.
  void replaceWith(List<jge.Entity> entities, PrefabDefinition prefab) {
    if (entities.isEmpty) return;
    final specs = <EntitySpec>[];
    for (final e in entities) {
      final t = e.getComponent<jge.TransformComponent>();
      if (t == null) continue;
      final local = DesignerGeometry.componentSize(e);
      final size = local == null
          ? prefab.defaultSize
          : Size(local.width * t.scale.x.abs(), local.height * t.scale.y.abs());
      final built = prefab.build(Offset(t.position.x, t.position.y), size);
      final oldLayer = e.getComponent<jge.LayerComponent>();
      if (oldLayer?.mapLayer != null &&
          !built.any((c) => c is jge.LayerComponent)) {
        built.add(jge.LayerComponent());
      }
      for (final c in built) {
        if (c is jge.TransformComponent) c.rotation = t.rotation;
        if (c is jge.LayerComponent && oldLayer != null) {
          c
            ..layerId = oldLayer.layerId
            ..layer = oldLayer.layer
            ..zOrder = oldLayer.zOrder
            ..mapLayer = oldLayer.mapLayer;
        }
      }
      final was = EntitySpec.of(e, codec, world: world);
      specs.add(
        EntitySpec(
          name: _uniqueName(prefab.namePrefix ?? prefab.id),
          componentsJson: [
            for (final c in built)
              if (c is! jge.ParentComponent && c is! jge.ChildrenComponent)
                ?codec.encode(c),
          ],
          codec: codec,
          parentName: was.parentName,
          siblingIndex: was.siblingIndex,
        ),
      );
    }
    if (specs.isEmpty) return;
    history.push(
      CompositeCommand(
        label: 'Replace ${_describe(entities)} with ${prefab.name}',
        commands: [
          DeleteEntitiesCommand(
            label: 'Delete',
            world: world,
            sceneState: sceneState,
            entities: entities,
            codec: codec,
          ),
          CreateEntitiesCommand(
            label: 'Create',
            world: world,
            sceneState: sceneState,
            specs: specs,
            onCreated: _select,
          ),
        ],
      ),
    );
  }

  /// Puts [entities] at the depth [layerId]. One undo step.
  void moveToLayer(List<jge.Entity> entities, String layerId) =>
      _edit(entities, 'Move to $layerId', (e) {
        final layer = e.getComponent<jge.LayerComponent>();
        if (layer != null) {
          layer.layerId = layerId;
        } else {
          e.addComponent(jge.LayerComponent(layerId: layerId));
        }
      });

  void _edit(
    List<jge.Entity> entities,
    String label,
    void Function(jge.Entity entity) change, {
    Object? mergeKey,
  }) {
    if (entities.isEmpty) return;
    final before = entities
        .map((e) => EntitySpec.of(e, codec))
        .toList(growable: false);
    for (final e in entities) {
      change(e);
      sceneState.syncEntityNode(e);
    }
    final command = EntityStateCommand(
      label: label,
      world: world,
      sceneState: sceneState,
      ids: [for (final e in entities) e.id],
      before: before,
      after: entities
          .map((e) => EntitySpec.of(e, codec))
          .toList(growable: false),
      mergeKey: mergeKey,
    );
    if (!command.changesAnything) return;
    _record(command);
  }

  void _select(List<jge.Entity> entities) {
    sceneState.clearSelection();
    if (entities.length == 1) {
      sceneState.selectEntity(entities.single);
      return;
    }
    for (final e in entities) {
      sceneState.toggleMultiSelect(e);
    }
  }

  static String _describe(List<jge.Entity> entities) => entities.length == 1
      ? entities.first.name ?? 'entity'
      : '${entities.length} entities';

  /// Keeps angles in (-π, π], so repeated turns do not accumulate.
  static double _normalise(double radians) {
    var r = radians % (2 * math.pi);
    if (r > math.pi) r -= 2 * math.pi;
    return r;
  }
}
