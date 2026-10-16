import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
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

  /// Whether a body of [friction] and [restitution] is made of this.
  bool matches(double friction, double restitution) =>
      (friction - this.friction).abs() < 1e-6 && (restitution - this.restitution).abs() < 1e-6;
}

/// What the inspector adds to the physics components — the 2-D ones here,
/// and a 3-D body's material presets through [materialsFor]:
///
/// - **Rigid Body 2D**: a one-line summary, material presets heading its
///   Surface group, and while the game runs, how the body is moving.
/// - **Collider 2D**: its shape in a few words, Fit to what is drawn, and
///   Edit in the viewport.
abstract final class PhysicsBodyExtras {
  /// The rigid body's saved type.
  static const String rigidBodyType = 'RigidBody2D';

  /// The collider's saved type.
  static const String colliderType = 'Collider2D';

  static const List<PhysicsMaterialPreset> materials = [
    PhysicsMaterialPreset('Default', 0.5, 0, 'What a new body starts as.'),
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

  /// Every 2-D extra.
  static List<ComponentEditorExtras> all(EditorScope scope) => [rigidBody(scope), collider(scope)];

  /// What [RigidBody2D]'s inspector adds.
  static ComponentEditorExtras rigidBody(EditorScope scope) => ComponentEditorExtras(
    type: rigidBodyType,
    summary: (c) => summaryOf(c as jge.RigidBody2D, scope),
    groupLeading: {
      'Surface': (context, c) => _MaterialPresetRow(scope: scope, body: c),
    },
    section: (context, c) => _BodyNotes(scope: scope, body: c as jge.RigidBody2D),
  );

  /// The material presets on any body of [type] with `friction` and
  /// `restitution` fields, heading its Surface group — what a 3-D rigid
  /// body shows too, so both pick a material the same way. The editor is
  /// found from where the row is shown.
  static ComponentEditorExtras materialsFor(String type, {String Function(jge.Component c)? summary}) =>
      ComponentEditorExtras(
        type: type,
        summary: summary,
        groupLeading: {
          'Surface': (context, c) {
            final scope = EditorScopeProvider.maybeOf(context);
            return scope == null ? const SizedBox.shrink() : _MaterialPresetRow(scope: scope, body: c);
          },
        },
      );

  /// What [Collider2D]'s inspector adds.
  static ComponentEditorExtras collider(EditorScope scope) => ComponentEditorExtras(
    type: colliderType,
    summary: (c) => shapeLabel(c as jge.Collider2D),
    actions: [
      InspectorAction(
        id: 'physics.fitToVisual',
        label: 'Fit the collider to what is drawn',
        icon: Icons.fit_screen_rounded,
        run: (context, c) async => fitToVisual(scope, c as jge.Collider2D),
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
  );

  /// `Dynamic body · Sensor · Player`.
  static String summaryOf(jge.RigidBody2D b, EditorScope scope) {
    final layers = scope.physicsLayers.layers.value;
    return [
      switch (b.bodyType) {
        jge.BodyType.static => 'Static body',
        jge.BodyType.kinematic => 'Kinematic body',
        jge.BodyType.dynamic => 'Dynamic body',
      },
      if (b.isSensor) 'Sensor',
      if (b.layer != 0) layers.labelOf(b.layer),
    ].join(' · ');
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// A collider in a few words: `Circle r 17.4`, `Box 64 × 20 · One-way`.
  static String shapeLabel(jge.Collider2D c) {
    final shape = switch (c.shape) {
      jge.ColliderShape2D.box => 'Box ${_n(c.size.x)} × ${_n(c.size.y)}',
      jge.ColliderShape2D.circle => 'Circle r ${_n(c.radius)}',
      jge.ColliderShape2D.capsule => 'Capsule r ${_n(c.radius)} × ${_n(c.height)}',
      jge.ColliderShape2D.polygon => '${c.points.length}-gon',
      jge.ColliderShape2D.segment => 'Segment',
      jge.ColliderShape2D.chain => 'Chain of ${c.points.length}',
      jge.ColliderShape2D.matchShape => 'Matches what is drawn',
    };
    return [shape, if (c.oneWay) 'One-way'].join(' · ');
  }

  /// A simulated shape in a few words, for messages.
  static String collisionShapeLabel(jge.CollisionShape s) => switch (s) {
    jge.CircleShape c => 'Circle r ${_n(c.radius)}',
    jge.RoundedPolygonShape p => 'Rounded ${p.vertices.length}-gon',
    jge.RectangleShape r => 'Box ${_n(r.width)} × ${_n(r.height)}',
    jge.PolygonShape p => '${p.vertices.length}-gon',
    jge.CapsuleShape c => 'Capsule r ${_n(c.radius)}',
    jge.SegmentShape _ => 'Segment',
    jge.ChainShape c => 'Chain of ${c.vertices.length}',
    _ => 'Shape',
  };

  /// The entity [component] is on: the selection's, else whoever has it.
  static jge.Entity? ownerOf(EditorScope scope, jge.Component component) {
    final selected = scope.sceneState.selectedEntity.value;
    if (selected != null && selected.components.any((c) => identical(c, component))) {
      return selected;
    }
    for (final e in scope.world.entities) {
      if (e.components.any((c) => identical(c, component))) return e;
    }
    return null;
  }

  /// Gives [collider] the shape of what its entity draws, centred and
  /// unturned, as one undo step — set once; a collider matching the shape
  /// ([jge.ColliderShape2D.matchShape]) follows it instead. Says so in the
  /// log when there is nothing to fit to.
  static bool fitToVisual(EditorScope scope, jge.Collider2D collider) {
    final entity = ownerOf(scope, collider);
    final shape = entity == null ? null : jge.ColliderGeometry.visualShapeOf(entity, definitions: scope.definitions);
    if (shape == null) {
      scope.log.log(
        'Fit to visual: the entity draws nothing with a size to fit to.',
        source: 'editor',
        category: 'physics',
      );
      return false;
    }
    final edit = ComponentEdit.begin(scope, collider);
    setFrom(collider, shape);
    edit.commit('Fit collider');
    return true;
  }

  /// Sets [collider]'s fields to stand for [shape] (in its own space),
  /// centred and unturned, its own scale 1.
  static void setFrom(jge.Collider2D collider, jge.CollisionShape shape) {
    collider
      ..offset = Offset.zero
      ..rotation = 0
      ..scale = jge.Vector2(1, 1)
      ..cornerRadius = 0;
    switch (shape) {
      case jge.CircleShape s:
        collider
          ..shape = jge.ColliderShape2D.circle
          ..radius = s.radius
          ..offset = s.center;
      case jge.CapsuleShape s:
        final d = s.center2 - s.center1;
        collider
          ..shape = jge.ColliderShape2D.capsule
          ..radius = s.radius
          ..height = d.distance + 2 * s.radius
          ..rotation = d.distance < 1e-9 ? 0 : math.atan2(-d.dx, d.dy)
          ..offset = (s.center1 + s.center2) / 2;
      case jge.RectangleShape s:
        collider
          ..shape = jge.ColliderShape2D.box
          ..size = jge.Vector2(s.width, s.height);
      case jge.RoundedPolygonShape s:
        final r = jge.ColliderGeometry.boundsOf(jge.PolygonShape(s.vertices));
        collider
          ..shape = jge.ColliderShape2D.box
          ..size = jge.Vector2(r.width + 2 * s.cornerRadius, r.height + 2 * s.cornerRadius)
          ..cornerRadius = s.cornerRadius
          ..offset = r.center;
      case jge.PolygonShape s:
        collider
          ..shape = jge.ColliderShape2D.polygon
          ..points = [...s.vertices];
      case jge.SegmentShape s:
        collider
          ..shape = jge.ColliderShape2D.segment
          ..points = [s.point1, s.point2]
          ..thickness = s.thickness;
      case jge.ChainShape s:
        collider
          ..shape = jge.ColliderShape2D.chain
          ..points = [...s.vertices]
          ..loop = s.loop
          ..thickness = s.thickness;
    }
  }

  /// [body]'s friction and restitution, read through its definition — a
  /// 2-D or a 3-D body alike; null when it has neither.
  static (double, double)? surfaceOf(EditorScope scope, jge.Component body) {
    final definition = scope.definitions.definitionFor(body);
    final friction = definition?.field('friction')?.read(body);
    final restitution = definition?.field('restitution')?.read(body);
    if (friction is! num || restitution is! num) return null;
    return (friction.toDouble(), restitution.toDouble());
  }

  /// Makes [body] — any body with friction and restitution fields — of
  /// [preset], as one undo step.
  static void applyMaterial(EditorScope scope, jge.Component body, PhysicsMaterialPreset preset) {
    final definition = scope.definitions.definitionFor(body);
    if (definition == null) return;
    final edit = ComponentEdit.begin(scope, body);
    definition.field('friction')?.write?.call(body, preset.friction);
    definition.field('restitution')?.write?.call(body, preset.restitution);
    edit.commit('Material: ${preset.name}');
  }
}

/// "Preset [Rubber ▾]" at the head of the Surface group.
class _MaterialPresetRow extends StatelessWidget {
  const _MaterialPresetRow({required this.scope, required this.body});

  final EditorScope scope;
  final jge.Component body;

  @override
  Widget build(BuildContext context) {
    final surface = PhysicsBodyExtras.surfaceOf(scope, body);
    PhysicsMaterialPreset? current;
    for (final m in PhysicsBodyExtras.materials) {
      if (surface != null && m.matches(surface.$1, surface.$2)) current = m;
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
  final jge.RigidBody2D body;

  @override
  Widget build(BuildContext context) => SignalBuilder<bool>(
    signal: scope.isPlayTesting,
    builder: (context, playing, _) {
      final entity = PhysicsBodyExtras.ownerOf(scope, body);
      final notes = <String>[
        if (entity != null && !entity.hasComponent<jge.Collider2D>())
          'It has no Collider 2D, so it has no shape and touches nothing.',
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
  final jge.RigidBody2D body;

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
        if (!b.lockRotation)
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
