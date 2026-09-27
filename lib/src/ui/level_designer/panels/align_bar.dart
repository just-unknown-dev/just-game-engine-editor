import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/constants/editor_constants.dart';
import '../../../core/entity/hierarchy_commands.dart';
import '../level_designer_session.dart';
import '../state/designer_geometry.dart';
import '../state/editor_commands.dart';

/// Which edge or axis an alignment operates on.
enum AlignEdge {
  /// Left edges.
  left,

  /// Horizontal centres.
  centerX,

  /// Right edges.
  right,

  /// Top edges.
  top,

  /// Vertical centres.
  centerY,

  /// Bottom edges.
  bottom,
}

/// Align, distribute and array — the operations that turn a rough block-out
/// into something that reads as deliberate.
///
/// Each one commits as a single undoable command covering the whole selection,
/// so a mis-aimed align is one Ctrl+Z rather than one per entity.
class AlignBar extends StatelessWidget {
  const AlignBar({super.key, required this.session, required this.gridSize});

  /// The designer session the operations act on.
  final LevelDesignerSession session;

  /// Grid size, used as the default array step.
  final double gridSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALIGN',
            style: TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            children: [
              _Button(
                icon: Icons.align_horizontal_left,
                tooltip: 'Align left edges',
                onTap: () => _align(AlignEdge.left),
              ),
              _Button(
                icon: Icons.align_horizontal_center,
                tooltip: 'Align horizontal centres',
                onTap: () => _align(AlignEdge.centerX),
              ),
              _Button(
                icon: Icons.align_horizontal_right,
                tooltip: 'Align right edges',
                onTap: () => _align(AlignEdge.right),
              ),
              _Button(
                icon: Icons.align_vertical_top,
                tooltip: 'Align top edges',
                onTap: () => _align(AlignEdge.top),
              ),
              _Button(
                icon: Icons.align_vertical_center,
                tooltip: 'Align vertical centres',
                onTap: () => _align(AlignEdge.centerY),
              ),
              _Button(
                icon: Icons.align_vertical_bottom,
                tooltip: 'Align bottom edges',
                onTap: () => _align(AlignEdge.bottom),
              ),
              _Button(
                icon: Icons.horizontal_distribute,
                tooltip: 'Distribute horizontally',
                onTap: () => _distribute(horizontal: true),
              ),
              _Button(
                icon: Icons.vertical_distribute,
                tooltip: 'Distribute vertically',
                onTap: () => _distribute(horizontal: false),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Button(
                icon: Icons.content_copy,
                tooltip: 'Duplicate selection  (Ctrl+D)',
                onTap: session.onDuplicate,
              ),
              _Button(
                icon: Icons.grid_on,
                tooltip: 'Repeat selection 4x to the right',
                onTap: () => session.onArray(4, Offset(gridSize * 4, 0)),
              ),
              _Button(
                icon: Icons.delete_outline,
                tooltip: 'Delete selection  (Del)',
                onTap: session.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Snaps every selected entity to a shared edge or centre line.
  ///
  /// The target comes from the selection's combined bounds rather than from a
  /// "key" entity, so the result does not depend on selection order — which
  /// the author has no way to see.
  void _align(AlignEdge edge) {
    final entities = session.selectionEntities();
    if (entities.length < 2) return;

    final union = DesignerGeometry.unionBounds(entities);
    if (union == null) return;

    final before = entities.map(TransformSnapshot.of).toList(growable: false);

    for (final entity in entities) {
      final transform = entity.getComponent<jge.TransformComponent>();
      if (transform == null) continue;
      final bounds = DesignerGeometry.worldBounds(entity);
      final halfW = (bounds?.width ?? 0) / 2;
      final halfH = (bounds?.height ?? 0) / 2;

      switch (edge) {
        case AlignEdge.left:
          transform.setPositionXY(union.left + halfW, transform.position.y);
        case AlignEdge.centerX:
          transform.setPositionXY(union.center.dx, transform.position.y);
        case AlignEdge.right:
          transform.setPositionXY(union.right - halfW, transform.position.y);
        case AlignEdge.top:
          transform.setPositionXY(transform.position.x, union.top + halfH);
        case AlignEdge.centerY:
          transform.setPositionXY(transform.position.x, union.center.dy);
        case AlignEdge.bottom:
          transform.setPositionXY(transform.position.x, union.bottom - halfH);
      }
      session.sceneState.syncEntityNode(entity);
    }

    _record(entities, before, 'Align ${edge.name}');
  }

  /// Spaces the selection evenly between its two outermost members.
  void _distribute({required bool horizontal}) {
    final entities = session.selectionEntities();
    // Fewer than three and there is nothing between the ends to space out.
    if (entities.length < 3) return;

    entities.sort((a, b) {
      final ta = a.getComponent<jge.TransformComponent>()!;
      final tb = b.getComponent<jge.TransformComponent>()!;
      return horizontal
          ? ta.position.x.compareTo(tb.position.x)
          : ta.position.y.compareTo(tb.position.y);
    });

    final before = entities.map(TransformSnapshot.of).toList(growable: false);

    final first = entities.first.getComponent<jge.TransformComponent>()!;
    final last = entities.last.getComponent<jge.TransformComponent>()!;
    final start = horizontal ? first.position.x : first.position.y;
    final end = horizontal ? last.position.x : last.position.y;
    final step = (end - start) / (entities.length - 1);

    for (var i = 1; i < entities.length - 1; i++) {
      final transform = entities[i].getComponent<jge.TransformComponent>()!;
      final value = start + step * i;
      if (horizontal) {
        transform.setPositionXY(value, transform.position.y);
      } else {
        transform.setPositionXY(transform.position.x, value);
      }
      session.sceneState.syncEntityNode(entities[i]);
    }

    _record(
      entities,
      before,
      horizontal ? 'Distribute horizontally' : 'Distribute vertically',
    );
  }

  void _record(
    List<jge.Entity> entities,
    List<TransformSnapshot> before,
    String label,
  ) {
    // What is under each moved entity goes with it.
    final world = session.world;
    final carried = <jge.Entity>[];
    final carriedBefore = <TransformSnapshot>[];
    for (var i = 0; i < entities.length; i++) {
      final now = TransformSnapshot.of(entities[i]);
      final dx = now.x - before[i].x, dy = now.y - before[i].y;
      final under = carriedWith(
        [entities[i]],
        world: world,
      ).where((e) => !entities.contains(e) && !carried.contains(e));
      for (final child in under) {
        final t = child.getComponent<jge.TransformComponent>()!;
        carried.add(child);
        carriedBefore.add(TransformSnapshot.of(child));
        if (dx == 0 && dy == 0) continue;
        t.setPositionXY(t.position.x + dx, t.position.y + dy);
        session.sceneState.syncEntityNode(child);
      }
    }
    final all = [...entities, ...carried];
    session.history.pushApplied(
      TransformCommand(
        label: label,
        entities: all,
        before: [...before, ...carriedBefore],
        after: all.map(TransformSnapshot.of).toList(growable: false),
        sceneState: session.sceneState,
      ),
    );
    session.sceneState
      ..markDirty()
      ..refresh();
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: EditorTheme.textSecondary),
        ),
      ),
    );
  }
}
