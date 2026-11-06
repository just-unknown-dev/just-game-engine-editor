import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_editor_core/host.dart';
import 'dock_widgets.dart';

/// The selected entity's animator while the game runs: the state it is in,
/// its parameters as they change, and the transitions it has taken.
class AnimatorDock extends StatefulWidget {
  const AnimatorDock({super.key, required this.scope});

  final EditorScope scope;

  @override
  State<AnimatorDock> createState() => _AnimatorDockState();
}

class _AnimatorDockState extends State<AnimatorDock> {
  Timer? _tick;
  StreamSubscription<jge.AnimatorStateChange>? _changes;
  jge.AnimatorSystem? _listeningTo;
  final List<String> _trail = [];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _listen();
      setState(() {});
    });
    _listen();
  }

  jge.AnimatorSystem? get _system {
    for (final s in widget.scope.world.systems) {
      if (s is jge.AnimatorSystem) return s;
    }
    return null;
  }

  /// The animator system may be replaced (a scene reload): follow it.
  void _listen() {
    final system = _system;
    if (identical(system, _listeningTo)) return;
    _changes?.cancel();
    _listeningTo = system;
    _changes = system?.stateChanges.listen((c) {
      if (!identical(c.entity, widget.scope.sceneState.selectedEntity.value)) {
        return;
      }
      _trail.insert(0, '${c.from.isEmpty ? 'entry' : c.from} → ${c.to}');
      if (_trail.length > 12) _trail.removeLast();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entity = widget.scope.sceneState.selectedEntity.value;
    final animator = entity?.getComponent<jge.AnimatorComponent>();
    if (entity == null || animator == null) {
      return const EditorEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Select an entity with an Animator',
        hint: 'Its state and parameters show here, live, while the game plays.',
      );
    }
    final graph = _system?.graphOf(entity);
    final sprite = entity.getComponent<jge.SpriteAnimationComponent>();
    // The clip its state plays, from the graph: the sprite's own clip field
    // is what was authored, not what the animator chose.
    final clip =
        graph?.stateNamed(animator.currentState)?.clipName ?? sprite?.clip;
    final bound = {
      for (final p in graph?.parameters ?? const <jge.AnimatorParameter>[])
        if (p.binding != null) p.name: p.binding!,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorToolbar(
                children: [
                  Text(
                    animator.currentState.isEmpty
                        ? 'not running'
                        : animator.currentState,
                    style: TextStyle(
                      color: EditorTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    [
                      if (animator.previousState.isNotEmpty)
                        'from ${animator.previousState}',
                      '${animator.stateTime.toStringAsFixed(2)} s',
                      if (sprite != null)
                        'clip $clip · frame ${sprite.frameIndex + 1}',
                    ].join('  ·  '),
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (animator.graphPath.isNotEmpty)
                    EditorIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Open the graph',
                      onTap: () =>
                          widget.scope.openInWorkspace(animator.graphPath),
                    ),
                ],
              ),
              Expanded(
                child: DockTable<MapEntry<String, Object>>(
                  rows: animator.parameters.entries.toList(),
                  empty: const EditorEmptyState(
                    icon: Icons.tune_rounded,
                    title: 'No parameters yet',
                    hint: 'They appear once the graph has loaded.',
                  ),
                  columns: [
                    DockColumn(label: 'Parameter', flex: 3, text: (e) => e.key),
                    DockColumn(
                      label: 'Value',
                      flex: 2,
                      numeric: true,
                      text: (e) => e.value is double
                          ? (e.value as double).toStringAsFixed(2)
                          : '${e.value}',
                      color: (e) =>
                          e.value == true ? EditorTheme.success : null,
                    ),
                    DockColumn(
                      label: 'From',
                      flex: 3,
                      text: (e) => bound[e.key] == null
                          ? 'the game'
                          : '⇠ ${bound[e.key]}',
                      color: (_) => EditorTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: EditorTheme.border),
        Expanded(
          flex: 2,
          child: _trail.isEmpty
              ? const EditorEmptyState(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transitions yet',
                  hint: 'Press Play: each change of state is listed here.',
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (var i = 0; i < _trail.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          _trail[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: i == 0
                                ? EditorTheme.textPrimary
                                : EditorTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
