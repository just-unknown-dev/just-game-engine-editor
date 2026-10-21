import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../state/component_resizer.dart';
import 'select_tool.dart';
import 'package:just_editor_core/host.dart';

/// Click an entity to make it the thing the draw and paint tools place.
///
/// Samples the entity itself rather than looking up which prefab it came
/// from — so a platform you have since recoloured, retuned or given extra
/// components is copied exactly as it is now. Switches back to whichever
/// placing tool was active, ready to draw.
class EyedropperTool extends LevelToolHandler {
  EyedropperTool({required this.switchTool, required this.codec});

  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;

  /// Changes the active tool; the eyedropper hands back once it has sampled.
  final void Function(String toolId) switchTool;

  /// Id of the prefab a sample is registered under. One slot, replaced by
  /// every new sample, so the palette does not fill up with them.
  static const String sampledPrefabId = 'sampled';

  String _returnTo = BuiltInTools.draw;

  @override
  String get id => BuiltInTools.eyedropper;

  @override
  String get label => 'Sample';

  @override
  IconData get icon => Icons.colorize;

  @override
  String? get shortcut => 'I';

  @override
  String? get description => 'Click an entity to draw and paint copies of it';

  @override
  int get order => 45;

  @override
  String get group => ToolGroups.shapes;

  /// Remembers which placing tool to go back to. Called by the session when
  /// the eyedropper is picked, with the tool that was active.
  void activatedFrom(String toolId) {
    if (toolId == BuiltInTools.draw || toolId == BuiltInTools.paint) {
      _returnTo = toolId;
    }
  }

  @override
  bool onPointerDown(ToolContext context) {
    final hit = DesignerGeometry.topmostAt(
      context.world,
      context.worldPosition,
      // Not the whole Level Map, caught near its origin as a marker.
      pickable: (e) =>
          context.controller.isShownInViewport(e) &&
          !SelectTool.isWholeMap(context.world, e),
      markerReach: context.pixels(12),
    );
    if (hit == null) {
      context.controller.setStatus('Nothing there to sample');
      return true;
    }
    final prefab = sample(hit, codec);
    context.controller.sessionPrefabs.register(prefab);
    context.controller
      ..activePrefabId.value = prefab.id
      ..setStatus('Sampled ${hit.name ?? 'entity'} — draw or paint copies');
    switchTool(_returnTo);
    return true;
  }

  /// A prefab that builds copies of [entity], stretched to the drawn size.
  ///
  /// The drawn size is in the world's axes, as the entity is seen: its
  /// transform's scale is kept, and the components are sized so that,
  /// scaled, they fill the drawn box — across the box's height for an
  /// entity turned a quarter turn, whose own width runs down the screen.
  static PrefabDefinition sample(jge.Entity entity, SceneCodec codec) {
    final spec = EntitySpec.of(entity, codec);
    final transform = entity.getComponent<jge.TransformComponent>();
    final local = DesignerGeometry.componentSize(entity);
    final scaleX = transform?.scale.x.abs() ?? 1;
    final scaleY = transform?.scale.y.abs() ?? 1;
    final turned = ComponentResizer.isQuarterTurn(transform?.angle ?? 0);
    // As it stands in the world: what a click without a drag places.
    final shown = local == null
        ? null
        : Size(local.width * scaleX, local.height * scaleY);
    final seen = shown == null || !turned
        ? shown
        : Size(shown.height, shown.width);
    final color = entity.components
        .whereType<jge.RectangleComponent>()
        .firstOrNull
        ?.fillStyle
        .color;
    final base = (entity.name ?? 'Entity').replaceFirst(RegExp(r'_\d+$'), '');

    return PrefabDefinition(
      id: sampledPrefabId,
      name: 'Sampled: $base',
      category: 'Sampled',
      icon: Icons.colorize,
      color: color ?? const Color(0xFF90A4AE),
      placement: local == null
          ? PrefabPlacement.point
          : PrefabPlacement.dragRect,
      defaultSize: seen ?? const Size(32, 32),
      description: 'A copy of ${entity.name ?? 'the sampled entity'}',
      namePrefix: base,
      build: (position, size) {
        final components = spec.decode();
        // The drawn box in the entity's own axes, before its scale.
        final across = turned ? size.height : size.width;
        final down = turned ? size.width : size.height;
        final sx = shown == null || shown.width == 0
            ? 1.0
            : across / shown.width;
        final sy = shown == null || shown.height == 0
            ? 1.0
            : down / shown.height;
        for (final c in components) {
          if (c is jge.TransformComponent) {
            c
              ..setPositionXY(position.dx, position.dy)
              ..angle = transform?.angle ?? 0;
          } else if (sx != 1 || sy != 1) {
            ComponentResizer.scaleComponent(c, sx, sy, codec.definitions);
          }
        }
        return components;
      },
    );
  }
}
