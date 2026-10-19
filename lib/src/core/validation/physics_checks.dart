import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../ui/inspector/physics/physics_body_extras.dart';
import '../../ui/inspector/physics_field_editors.dart';
import 'package:just_editor_core/host.dart';
import '../physics/physics_bodies.dart';
import 'built_in_validators.dart';

/// What the Problems dock says about 2-D physics bodies — as `Physics3DChecks`
/// says about 3-D ones: bodies with no shape, characters with a body as
/// well, colliders that match nothing or do not match what is drawn, layers,
/// and shapes the native physics cannot take as they are.
abstract final class PhysicsChecks {
  static const List<SceneValidator> all = [
    shapes,
    characters,
    colliderMatchesVisual,
    layers,
    polygons,
    unshippedLayers,
  ];

  /// The colliders an author placed: not the level map's, not the game's.
  static Iterable<(jge.Entity, jge.Collider2D, jge.RigidBody2D?)> _colliders(
    ValidationContext context,
  ) sync* {
    for (final e in context.world.query([jge.Collider2D])) {
      if (!PhysicsBodies.isAuthored(e)) continue;
      yield (
        e,
        e.getComponent<jge.Collider2D>()!,
        e.getComponent<jge.RigidBody2D>(),
      );
    }
  }

  static String _name(jge.Entity e) => e.name ?? 'Entity ${e.id}';

  /// A rigid body with no collider (no shape, so it touches nothing), and a
  /// collider matching the shape of an entity that draws nothing.
  static List<SceneProblem> shapes(ValidationContext context) {
    final scope = context.scope;
    final out = <SceneProblem>[];
    for (final e in context.world.query([jge.RigidBody2D])) {
      if (!PhysicsBodies.isAuthored(e) || e.hasComponent<jge.Collider2D>()) {
        continue;
      }
      out.add(
        SceneProblem(
          entity: e,
          message:
              '${_name(e)} has a 2-D rigid body but no collider, so it has no shape and touches nothing.',
          hint: 'Add a Collider 2D.',
          fixes: [
            ProblemFix(
              label: 'Add a collider matching what it draws',
              apply: () => scope.history.push(
                AddComponentCommand(
                  entity: e,
                  component: jge.Collider2D(
                    shape: jge.ColliderShape2D.matchShape,
                  ),
                  sceneState: scope.sceneState,
                ),
              ),
            ),
          ],
        ),
      );
    }
    for (final (entity, collider, _) in _colliders(context)) {
      if (collider.shape != jge.ColliderShape2D.matchShape) continue;
      if (jge.ColliderGeometry.visualShapeOf(
            entity,
            definitions: scope.definitions,
          ) !=
          null) {
        continue;
      }
      out.add(
        SceneProblem(
          entity: entity,
          severity: ProblemSeverity.error,
          message:
              "${_name(entity)}'s collider matches what it draws, but it draws nothing with a size, so it makes no body.",
          hint:
              'Give it a shape or a sprite to match, or pick a shape for the collider.',
          fixes: [
            ProblemFix(
              label: 'Make it a box',
              apply: () {
                final edit = ComponentEdit.begin(scope, collider);
                collider.shape = jge.ColliderShape2D.box;
                edit.commit('Collider shape');
              },
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// A character that is also a rigid body or has a collider: the
  /// simulation and the character mover would both move it.
  static List<SceneProblem> characters(ValidationContext context) {
    final scope = context.scope;
    final out = <SceneProblem>[];
    for (final e in context.world.query([jge.CharacterBody2D])) {
      if (!PhysicsBodies.isAuthored(e)) continue;
      final rigid = e.getComponent<jge.RigidBody2D>();
      final collider = e.getComponent<jge.Collider2D>();
      if (rigid == null && collider == null) continue;
      out.add(
        SceneProblem(
          entity: e,
          severity: ProblemSeverity.error,
          message: rigid != null
              ? '${_name(e)} is a character and a rigid body at once; the two would fight over where it is.'
              : "${_name(e)} is a character with a collider as well; the collider would be a second body where it stands, and the character's own shape is in its Character Body 2D.",
          hint:
              'Keep the Character Body 2D and remove the ${rigid != null ? 'Rigid Body 2D' : 'Collider 2D'}.',
          fixes: [
            ProblemFix(
              label: 'Keep it a character',
              apply: () => scope.history.push(
                CompositeCommand(
                  label: 'Keep it a character',
                  commands: [
                    for (final c in <jge.Component?>[rigid, collider])
                      if (c != null)
                        RemoveComponentCommand(
                          entity: e,
                          component: c,
                          sceneState: scope.sceneState,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// A collider a little bigger or smaller than the circle, box or capsule
  /// drawn for it: the body rests above what it lands on, or sinks in.
  /// Sprites are left alone — a character's collider is smaller than its
  /// picture on purpose — and so are sensors, and colliders matching what is
  /// drawn (they always do).
  static List<SceneProblem> colliderMatchesVisual(ValidationContext context) {
    final out = <SceneProblem>[];
    for (final (entity, collider, rigid) in _colliders(context)) {
      if (rigid?.isSensor ?? false) continue;
      if (collider.shape == jge.ColliderShape2D.matchShape) continue;
      final drawn = entity.components.any(
        (c) =>
            c is jge.CircleComponent ||
            c is jge.RectangleComponent ||
            c is jge.CapsuleComponent ||
            c is jge.PolygonComponent,
      );
      if (!drawn) continue;
      final visual = jge.ColliderGeometry.visualShapeOf(entity);
      final placed = jge.ColliderGeometry.of(collider);
      if (visual == null || placed == null) continue;
      final want = jge.ColliderGeometry.boundsOf(visual);
      final have = jge.ColliderGeometry.boundsOf(placed);
      bool off(double a, double b) {
        final d = (a - b).abs();
        return d > 1 && d > 0.05 * b.abs().clamp(1, double.infinity);
      }

      if (!off(have.width, want.width) &&
          !off(have.height, want.height) &&
          (have.center - want.center).distance <= 1) {
        continue;
      }
      final where = (have.center - want.center).distance > 0.5
          ? ', off centre'
          : '';
      out.add(
        SceneProblem(
          entity: entity,
          message:
              "${_name(entity)}'s collider is "
              '${PhysicsBodyExtras.shapeLabel(collider)}$where, but what it '
              'draws is ${PhysicsBodyExtras.collisionShapeLabel(visual)}: it rests '
              'above what it lands on, or sinks into it.',
          hint:
              'Make the collider match what is drawn, fit it once, or edit '
              'it in the viewport.',
          fixes: [
            ProblemFix(
              label: 'Match what is drawn',
              apply: () {
                final edit = ComponentEdit.begin(context.scope, collider);
                collider
                  ..shape = jge.ColliderShape2D.matchShape
                  ..offset = Offset.zero
                  ..rotation = 0;
                edit.commit('Match what is drawn');
              },
            ),
            ProblemFix(
              label: 'Fit to visual',
              apply: () =>
                  PhysicsBodyExtras.fitToVisual(context.scope, collider),
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// A body on a layer with no name, and one that collides with nothing.
  static List<SceneProblem> layers(ValidationContext context) {
    final scope = context.scope;
    final grid = scope.physicsLayers.layers.value;
    final out = <SceneProblem>[];
    for (final (entity, _, rigid) in _colliders(context)) {
      final body = rigid;
      if (body == null) continue;
      if (grid.nameOf(body.layer).isEmpty) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_name(entity)} is on layer ${body.layer}, which has no '
                'name.',
            hint:
                'Name the layer in the Physics Layers dock, or move the '
                'body to a named one.',
            fixes: [
              ProblemFix(
                label: 'Move to ${grid.labelOf(0)}',
                apply: () =>
                    _set(scope, entity, body, 'Layer', (b) => b.layer, (b, v) {
                      b.layer = v as int;
                    }, 0),
              ),
              ProblemFix(
                label: 'Open Physics Layers',
                apply: () => PhysicsFieldEditors.openDock(scope),
              ),
            ],
          ),
        );
      }
      final mask = body.collidesWith ?? grid.maskOf(body.layer);
      if (mask == 0 && !body.isSensor) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_name(entity)} collides with no layer: everything passes '
                'through it.',
            hint: body.collidesWith == null
                ? 'Tick its layer against others in the Physics Layers '
                      'dock.'
                : 'Add layers to its Collides with list, or follow the '
                      "project's grid.",
            fixes: [
              if (body.collidesWith != null)
                ProblemFix(
                  label: 'Follow the project grid',
                  apply: () => _set(
                    scope,
                    entity,
                    body,
                    'Collides with',
                    (b) => b.collidesWith,
                    (b, v) => b.collidesWith = v as int?,
                    null,
                  ),
                ),
              ProblemFix(
                label: 'Open Physics Layers',
                apply: () => PhysicsFieldEditors.openDock(scope),
              ),
            ],
          ),
        );
      }
      // Listed by the body, but that layer's row leaves the body's layer
      // out: a contact needs both, so they never touch.
      final own = body.collidesWith;
      if (own != null && !body.isSensor) {
        for (final other in grid.named) {
          if ((own >> other) & 1 == 0 || grid.collides(other, body.layer)) {
            continue;
          }
          final them = grid.nameOf(other), us = grid.labelOf(body.layer);
          final without = own & ~(1 << other);
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '${_name(entity)} collides with $them, but in the grid $them '
                  'does not collide with $us: they never touch.',
              hint:
                  'A contact needs both sides. Tick $them and $us in the '
                  'Physics Layers grid, or take $them off the list.',
              fixes: [
                ProblemFix(
                  label: 'Tick $them and $us',
                  apply: () =>
                      scope.physicsLayers.setCollision(other, body.layer, true),
                ),
                ProblemFix(
                  label: 'Take $them off the list',
                  apply: () => _set(
                    scope,
                    entity,
                    body,
                    'Collides with',
                    (b) => b.collidesWith,
                    (b, v) => b.collidesWith = v as int?,
                    without == grid.maskOf(body.layer) ? null : without,
                  ),
                ),
              ],
            ),
          );
        }
      }
    }
    return out;
  }

  /// A polygon the native physics takes as something else: a dent filled
  /// in (it uses the outline's convex hull), or more than eight points.
  static List<SceneProblem> polygons(ValidationContext context) {
    final out = <SceneProblem>[];
    for (final (entity, collider, _) in _colliders(context)) {
      if (collider.shape != jge.ColliderShape2D.polygon) continue;
      final v = collider.points;
      if (v.length > 8) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                "${_name(entity)}'s collider has ${v.length} points; the "
                'native physics takes at most 8, and drops the rest.',
            hint:
                'Remove points (Alt-click one while editing the collider), '
                'or make it a chain.',
          ),
        );
      } else if (!isConvex(v)) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                "${_name(entity)}'s collider dents inwards; the native "
                'physics fills the dent in (it uses the convex outline).',
            hint:
                'Make every corner point outwards, or build the shape from '
                'several bodies or a chain.',
          ),
        );
      }
    }
    return out;
  }

  /// Whether [v] goes round turning the same way at every corner.
  static bool isConvex(List<Offset> v) {
    if (v.length < 4) return true;
    var sign = 0;
    for (var i = 0; i < v.length; i++) {
      final a = v[i], b = v[(i + 1) % v.length], c = v[(i + 2) % v.length];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// The project has layers, but the game would not see them: pubspec.yaml
  /// does not ship the file.
  static List<SceneProblem> unshippedLayers(ValidationContext context) {
    const path = jge.PhysicsLayers.defaultPath;
    if (!context.fileExists(path)) return const [];
    final shipped = BuiltInValidators.shippedAssets(context);
    if (shipped == null || BuiltInValidators.isShipped(path, shipped)) {
      return const [];
    }
    return const [
      SceneProblem(
        message:
            'The physics layers are not shipped: the game collides '
            'everything with everything.',
        hint: 'Add "- $path" under flutter: assets: in pubspec.yaml.',
      ),
    ];
  }

  static void _set<T>(
    EditorScope scope,
    jge.Entity entity,
    jge.RigidBody2D body,
    String label,
    T Function(jge.RigidBody2D) read,
    void Function(jge.RigidBody2D, Object?) write,
    T value,
  ) {
    scope.history.push(
      ComponentFieldCommand(
        label: 'Change $label',
        component: body,
        write: (c, v) => write(c as jge.RigidBody2D, v),
        before: read(body),
        after: value,
        sceneState: scope.sceneState,
        entity: entity,
      ),
    );
  }
}
