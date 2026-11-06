import 'dart:ui';

import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// Where things are in the Level Designer: [DesignerGeometry]'s answers,
/// and a piece of a Level Map's.
///
/// A piece — tiles cut from a map layer into an entity of their own (Select
/// tiles → Make entity) — has no size its components' extents describe: a
/// map is drawn from its origin, not about it. Its bounds are the cells it
/// uses. The designer's tools ask here when they pick, sweep, snap, line
/// up, frame or erase, so a piece is picked by its tiles and its gizmo sits
/// on them, not on its corner.
abstract final class DesignerBounds {
  /// The world-space rectangle [entity] occupies: a piece's cells, or what
  /// [DesignerGeometry.worldBounds] says. Null for a sizeless marker (a
  /// spawn point), and for a piece with no tiles.
  static Rect? of(jge.Entity entity) {
    final world = entity.world;
    if (world != null &&
        entity.hasComponent<jge.LevelMapComponent>() &&
        jge.LevelMaps.isPiece(world, entity)) {
      return pieceBounds(entity);
    }
    return DesignerGeometry.worldBounds(entity);
  }

  /// The box round the cells [piece]'s map uses, each layer where it is
  /// drawn (its offset), placed at the piece's position — a map follows its
  /// position and nothing else. Null when it uses none.
  static Rect? pieceBounds(jge.Entity piece) {
    final t = piece.getComponent<jge.TransformComponent>();
    final map = piece.getComponent<jge.LevelMapComponent>();
    final data = map?.inline ?? map?.runtime?.base;
    if (t == null || data == null) return null;
    final geometry = jge.MapGeometry.of(data);
    Rect? union;
    for (final layer in data.layers) {
      final used = layer.cells.usedBounds;
      if (used == null) continue;
      final cells = geometry
          .boundsOf(
            jge.TileRange(
              used.left.toInt(),
              used.top.toInt(),
              used.right.toInt(),
              used.bottom.toInt(),
            ),
          )
          .shift(Offset(layer.offsetX, layer.offsetY));
      union = union == null ? cells : union.expandToInclude(cells);
    }
    return union?.shift(Offset(t.position.x, t.position.y));
  }

  /// The combined bounds of [entities]; a sizeless marker counts as the
  /// point it is at. Null when none has a transform.
  static Rect? union(Iterable<jge.Entity> entities) {
    Rect? union;
    for (final entity in entities) {
      var b = of(entity);
      if (b == null) {
        final t = entity.getComponent<jge.TransformComponent>();
        if (t == null) continue;
        b = Rect.fromLTWH(t.position.x, t.position.y, 0, 0);
      }
      union = union == null ? b : union.expandToInclude(b);
    }
    return union;
  }

  /// The topmost entity at [point] that [pickable] allows — as
  /// [DesignerGeometry.topmostAt] picks, by draw order, with pieces of a
  /// map picked by their cells. A sizeless marker is caught within
  /// [markerReach] of where it is.
  static jge.Entity? topmostAt(
    jge.World world,
    Offset point, {
    required bool Function(jge.Entity) pickable,
    required double markerReach,
  }) {
    final candidates = world
        .query([jge.TransformComponent])
        .where((e) => e.isActive && pickable(e))
        .toList();
    candidates.sort((a, b) {
      final la = a.getComponent<jge.LayerComponent>();
      final lb = b.getComponent<jge.LayerComponent>();
      final byLayer = (lb?.layer ?? 0).compareTo(la?.layer ?? 0);
      if (byLayer != 0) return byLayer;
      return (lb?.zOrder ?? 0).compareTo(la?.zOrder ?? 0);
    });
    for (final entity in candidates) {
      final bounds = of(entity);
      if (bounds != null) {
        if (bounds.contains(point)) return entity;
        continue;
      }
      final t = entity.getComponent<jge.TransformComponent>();
      if (t == null) continue;
      if ((Offset(t.position.x, t.position.y) - point).distance <=
          markerReach) {
        return entity;
      }
    }
    return null;
  }

  /// The entities of [entities] whose bounds meet [area] — a sizeless one
  /// by where it is — that [pickable] allows.
  static List<jge.Entity> entitiesIn(
    Rect area,
    Iterable<jge.Entity> entities, {
    required bool Function(jge.Entity) pickable,
  }) {
    final hits = <jge.Entity>[];
    for (final entity in entities) {
      if (!entity.isActive || !pickable(entity)) continue;
      final bounds = of(entity);
      if (bounds != null) {
        if (bounds.overlaps(area)) hits.add(entity);
        continue;
      }
      final t = entity.getComponent<jge.TransformComponent>();
      if (t != null && area.contains(Offset(t.position.x, t.position.y))) {
        hits.add(entity);
      }
    }
    return hits;
  }
}
