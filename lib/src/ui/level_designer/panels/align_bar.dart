import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../level_designer_session.dart';

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
  Widget build(BuildContext context) => SignalConsumer(
    signals: [
      session.sceneState.selectedEntity,
      session.sceneState.multiSelectedIds,
    ],
    builder: (context, _) => _bar(session.selectionEntities().length),
  );

  /// Only with something selected: there is nothing to align otherwise. A
  /// button that cannot act yet says what it waits for.
  Widget _bar(int n) {
    if (n == 0) return const SizedBox.shrink();
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onTap, {
      int needs = 1,
      String? shortcut,
    }) => EditorIconButton(
      icon: icon,
      tooltip: n >= needs ? tooltip : '$tooltip — select $needs or more',
      shortcut: shortcut,
      onTap: n >= needs ? onTap : null,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorSectionHeader(
            n == 1 ? 'Selection' : 'Selection · $n',
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          ),
          Wrap(
            children: [
              button(
                Icons.align_horizontal_left,
                'Align left edges',
                () => _align(AlignEdge.left),
                needs: 2,
              ),
              button(
                Icons.align_horizontal_center,
                'Align horizontal centres',
                () => _align(AlignEdge.centerX),
                needs: 2,
              ),
              button(
                Icons.align_horizontal_right,
                'Align right edges',
                () => _align(AlignEdge.right),
                needs: 2,
              ),
              button(
                Icons.align_vertical_top,
                'Align top edges',
                () => _align(AlignEdge.top),
                needs: 2,
              ),
              button(
                Icons.align_vertical_center,
                'Align vertical centres',
                () => _align(AlignEdge.centerY),
                needs: 2,
              ),
              button(
                Icons.align_vertical_bottom,
                'Align bottom edges',
                () => _align(AlignEdge.bottom),
                needs: 2,
              ),
              button(
                Icons.horizontal_distribute,
                'Distribute horizontally',
                () => _distribute(horizontal: true),
                needs: 3,
              ),
              button(
                Icons.vertical_distribute,
                'Distribute vertically',
                () => _distribute(horizontal: false),
                needs: 3,
              ),
            ],
          ),
          Row(
            children: [
              button(
                Icons.content_copy,
                'Duplicate the selection',
                session.onDuplicate,
                shortcut: session.scope.commands.shortcutOf('editor.duplicate'),
              ),
              button(
                Icons.grid_on,
                'Repeat the selection 4 times to the right',
                () => session.onArray(4, Offset(gridSize * 4, 0)),
              ),
              button(
                Icons.delete_outline,
                'Delete the selection',
                session.onDelete,
                shortcut: session.scope.commands.shortcutOf('editor.delete'),
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
