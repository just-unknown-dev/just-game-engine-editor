import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/scope/editor_scope.dart';
import '../../level_designer/state/editor_commands.dart';
import '../../overlay/gizmo_painter.dart';
import '../../widgets/editor_dropdown.dart';
import '../component_extras.dart';
import '../field_style.dart';
import 'collider_edit_session.dart';

/// A surface a body can be made of: how much it grips and how much it
/// bounces. Choosing one fills both fields; nothing remembers the choice.
class PhysicsMaterialPreset {
  const PhysicsMaterialPreset(
    this.name,
    this.friction,
    this.restitution,
    this.description,
  );

  final String name;
  final double friction;
  final double restitution;
  final String description;

  /// Whether [body] is made of this.
  bool matches(jge.PhysicsBodyComponent body) =>
      (body.friction - friction).abs() < 1e-6 &&
      (body.restitution - restitution).abs() < 1e-6;
}

/// What the inspector adds to a Physics Body: a one-line summary, Fit to
/// visual and Edit collider, material presets, and while the game runs,
/// how the body is moving.
abstract final class PhysicsBodyExtras {
  static const String type = 'PhysicsBodyComponent';

  static const List<PhysicsMaterialPreset> materials = [
    PhysicsMaterialPreset('Default', 0.2, 0.8, 'What a new body starts as.'),
    PhysicsMaterialPreset(
      'Character',
      0,
      0,
      'Slides along walls instead of sticking to them, and never bounces.',
    ),
    PhysicsMaterialPreset('Stone', 0.8, 0.05, 'Firm footing; no bounce.'),
    PhysicsMaterialPreset('Wood', 0.5, 0.2, 'A little grip, a little bounce.'),
    PhysicsMaterialPreset('Metal', 0.3, 0.1, 'Smooth and hard.'),
    PhysicsMaterialPreset('Ice', 0.02, 0.05, 'Barely holds anything back.'),
    PhysicsMaterialPreset('Rubber', 0.9, 0.6, 'Grips, and bounces back.'),
    PhysicsMaterialPreset('Bouncy', 0.3, 0.9, 'A ball, a trampoline.'),
    PhysicsMaterialPreset('Sticky', 1, 0, 'Holds on; gives nothing back.'),
  ];

  static ComponentEditorExtras extras(EditorScope scope) =>
      ComponentEditorExtras(
        type: type,
        summary: (c) => summaryOf(c as jge.PhysicsBodyComponent, scope),
        actions: [
          InspectorAction(
            id: 'physics.fitToVisual',
            label: 'Fit the collider to what is drawn',
            icon: Icons.fit_screen_rounded,
            run: (context, c) async =>
                fitToVisual(scope, c as jge.PhysicsBodyComponent),
          ),
          InspectorAction(
            id: 'physics.editCollider',
            label: 'Edit the collider in the viewport',
            icon: Icons.edit_location_alt_outlined,
            run: (context, c) async {
              final session = ColliderEditSession.of(scope);
              final entity = ownerOf(scope, c);
              if (entity != null) session.toggle(entity);
            },
          ),
        ],
        groupLeading: {
          'Material': (context, c) => _MaterialPresetRow(
            scope: scope,
            body: c as jge.PhysicsBodyComponent,
          ),
        },
        section: (context, c) =>
            _BodyNotes(scope: scope, body: c as jge.PhysicsBodyComponent),
      );

  /// `Dynamic · Circle r 17.4 · Sensor · Player`.
  static String summaryOf(jge.PhysicsBodyComponent b, EditorScope scope) {
    final layers = scope.physicsLayers.layers.value;
    return [
      switch (b.bodyType) {
        jge.BodyType.static => 'Static',
        jge.BodyType.kinematic => 'Kinematic',
        jge.BodyType.dynamic => 'Dynamic',
      },
      shapeLabel(b.shape),
      if (b.isSensor) 'Sensor',
      if (b.isOneWay) 'One-way',
      if (b.layer != 0) layers.labelOf(b.layer),
    ].join(' · ');
  }

  /// A shape in a few words: `Circle r 17.4`, `Box 64 × 20`.
  static String shapeLabel(jge.CollisionShape s) {
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return switch (s) {
      jge.CircleShape c => 'Circle r ${n(c.radius)}',
      jge.RoundedPolygonShape p => 'Rounded ${p.vertices.length}-gon',
      jge.RectangleShape r => 'Box ${n(r.width)} × ${n(r.height)}',
      jge.PolygonShape p => '${p.vertices.length}-gon',
      jge.CapsuleShape c => 'Capsule r ${n(c.radius)}',
      jge.SegmentShape _ => 'Segment',
      jge.ChainShape c => 'Chain of ${c.vertices.length}',
      _ => 'Shape',
    };
  }

  /// The entity [component] is on: the selection's, else whoever has it.
  static jge.Entity? ownerOf(EditorScope scope, jge.Component component) {
    final selected = scope.sceneState.selectedEntity.value;
    if (selected != null &&
        selected.components.any((c) => identical(c, component))) {
      return selected;
    }
    for (final e in scope.world.query([jge.PhysicsBodyComponent])) {
      if (identical(e.getComponent<jge.PhysicsBodyComponent>(), component)) {
        return e;
      }
    }
    return null;
  }

  /// The collider that would cover what [entity] draws, in its own space
  /// (before its scale): a circle for a circle, a capsule for a capsule, a
  /// polygon for a polygon, and a box around anything else that has a size.
  /// Null when it draws nothing with a size.
  static jge.CollisionShape? visualShapeOf(jge.Entity entity) {
    for (final c in entity.components) {
      switch (c) {
        case jge.CircleComponent v:
          return jge.CircleShape(v.radius);
        case jge.CapsuleComponent v:
          final r = math.min(v.width, v.height) / 2;
          final half = (math.max(v.width, v.height) / 2 - r).clamp(0, 1e9);
          return v.height >= v.width
              ? jge.CapsuleShape(
                  center1: Offset(0, -half.toDouble()),
                  center2: Offset(0, half.toDouble()),
                  radius: r,
                )
              : jge.CapsuleShape(
                  center1: Offset(-half.toDouble(), 0),
                  center2: Offset(half.toDouble(), 0),
                  radius: r,
                );
        case jge.RectangleComponent v:
          return jge.RectangleShape(v.width, v.height);
        case jge.PolygonComponent v when v.vertices.length >= 3:
          return jge.PolygonShape([...v.vertices]);
      }
    }
    Size? best;
    for (final c in entity.components) {
      if (c is jge.PhysicsBodyComponent) continue;
      final size = GizmoPainter.sizeOf(c);
      if (size == null || size.width <= 0 || size.height <= 0) continue;
      if (best == null || size.width * size.height > best.width * best.height) {
        best = size;
      }
    }
    return best == null ? null : jge.RectangleShape(best.width, best.height);
  }

  /// Gives [body] the collider of what its entity draws, centred, as one
  /// undo step. Says so in the log when there is nothing to fit to.
  static bool fitToVisual(EditorScope scope, jge.PhysicsBodyComponent body) {
    final entity = ownerOf(scope, body);
    final shape = entity == null ? null : visualShapeOf(entity);
    if (shape == null) {
      scope.log.log(
        'Fit to visual: the entity draws nothing with a size to fit to.',
        source: 'editor',
        category: 'physics',
      );
      return false;
    }
    setCollider(scope, body, shape, Offset.zero, label: 'Fit collider');
    return true;
  }

  /// Sets [body]'s shape and offset together, as one undo step.
  static void setCollider(
    EditorScope scope,
    jge.PhysicsBodyComponent body,
    jge.CollisionShape shape,
    Offset offset, {
    String label = 'Edit collider',
  }) {
    final state = scope.sceneState;
    scope.history.push(
      CompositeCommand(
        label: label,
        commands: [
          ComponentFieldCommand(
            label: label,
            component: body,
            write: (c, v) => (c as jge.PhysicsBodyComponent).shape =
                v! as jge.CollisionShape,
            before: body.shape,
            after: shape,
            sceneState: state,
          ),
          ComponentFieldCommand(
            label: label,
            component: body,
            write: (c, v) =>
                (c as jge.PhysicsBodyComponent).offset = v! as Offset,
            before: body.offset,
            after: offset,
            sceneState: state,
          ),
        ],
      ),
    );
    state.refresh();
  }

  /// Makes [body] of [preset], as one undo step.
  static void applyMaterial(
    EditorScope scope,
    jge.PhysicsBodyComponent body,
    PhysicsMaterialPreset preset,
  ) {
    final state = scope.sceneState;
    final label = 'Material: ${preset.name}';
    scope.history.push(
      CompositeCommand(
        label: label,
        commands: [
          ComponentFieldCommand(
            label: label,
            component: body,
            write: (c, v) =>
                (c as jge.PhysicsBodyComponent).friction = v! as double,
            before: body.friction,
            after: preset.friction,
            sceneState: state,
          ),
          ComponentFieldCommand(
            label: label,
            component: body,
            write: (c, v) =>
                (c as jge.PhysicsBodyComponent).restitution = v! as double,
            before: body.restitution,
            after: preset.restitution,
            sceneState: state,
          ),
        ],
      ),
    );
    state
      ..markDirty()
      ..refresh();
  }
}

/// "Preset [Rubber ▾]" at the head of the Material group.
class _MaterialPresetRow extends StatelessWidget {
  const _MaterialPresetRow({required this.scope, required this.body});

  final EditorScope scope;
  final jge.PhysicsBodyComponent body;

  @override
  Widget build(BuildContext context) {
    PhysicsMaterialPreset? current;
    for (final m in PhysicsBodyExtras.materials) {
      if (m.matches(body)) current = m;
    }
    return Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Text('Preset', style: InspectorField.labelStyle),
        ),
        Expanded(
          child: EditorDropdown<String>(
            value: current?.name,
            hint: 'Custom',
            options: [
              for (final m in PhysicsBodyExtras.materials)
                EditorDropdownOption(
                  value: m.name,
                  label: m.name,
                  detail:
                      'grip ${m.friction.toStringAsFixed(2)} · '
                      'bounce ${m.restitution.toStringAsFixed(2)}',
                ),
            ],
            onChanged: (name) {
              final preset = PhysicsBodyExtras.materials.firstWhere(
                (m) => m.name == name,
              );
              PhysicsBodyExtras.applyMaterial(scope, body, preset);
            },
          ),
        ),
      ],
    );
  }
}

/// Under the fields: what is worth knowing about how the body will behave,
/// and while the game runs, how it is moving.
class _BodyNotes extends StatelessWidget {
  const _BodyNotes({required this.scope, required this.body});

  final EditorScope scope;
  final jge.PhysicsBodyComponent body;

  @override
  Widget build(BuildContext context) => SignalBuilder<bool>(
    signal: scope.isPlayTesting,
    builder: (context, playing, _) {
      final notes = <String>[
        if (body.isDynamic &&
            !body.isSensor &&
            body.restitution > 0 &&
            scope.world.query([jge.MapBodyComponent]).isNotEmpty)
          'The level map\'s tiles have no bounciness, and a hit bounces as '
              'little as the less bouncy body — so this bounces off other bodies '
              'only.',
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: EditorTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      n,
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (playing) _LiveReadout(scope: scope, body: body),
        ],
      );
    },
  );
}

/// How the body is moving, a few times a second while the game runs.
class _LiveReadout extends StatefulWidget {
  const _LiveReadout({required this.scope, required this.body});

  final EditorScope scope;
  final jge.PhysicsBodyComponent body;

  @override
  State<_LiveReadout> createState() => _LiveReadoutState();
}

class _LiveReadoutState extends State<_LiveReadout>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (elapsed - _last < const Duration(milliseconds: 120)) return;
      _last = elapsed;
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entity = PhysicsBodyExtras.ownerOf(widget.scope, widget.body);
    final body = entity?.getComponent<jge.PhysicsBodyRefComponent>()?.body;
    final b = widget.body;
    String n(double v) => v.toStringAsFixed(0);
    final rows = <(String, String)>[
      if (body == null)
        ('Body', 'not in the simulation')
      else ...[
        ('Velocity', '${n(body.velocity.x)}, ${n(body.velocity.y)} px/s'),
        ('Speed', '${n(body.velocity.length)} px/s'),
        if (!b.fixedRotation)
          ('Spin', '${n(body.angularVelocity * 180 / math.pi)} °/s'),
        if (b.isDynamic) ('Asleep', body.isAwake ? 'no' : 'yes'),
        if (b.isDynamic) ('Grounded', b.isGrounded ? 'yes' : 'no'),
        if (b.groundEntity case final ground?)
          ('Standing on', ground.name ?? 'entity #${ground.id}'),
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: InspectorField.boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LIVE',
            style: TextStyle(
              color: EditorTheme.success,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: InspectorField.labelWidth - 8,
                    child: Text(label, style: InspectorField.labelStyle),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: InspectorField.valueStyle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
