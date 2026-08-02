import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

/// Which [CollisionShape] subtype a [PhysicsBodyComponent] currently uses.
///
/// Derived from `shape.runtimeType` — never persisted directly, since the
/// serialized shape JSON (`scene_file_generator.dart`) already round-trips
/// the concrete shape type on its own.
enum PhysicsShapeKind {
  circle,
  rectangle,
  capsule,
  polygon,
  roundedPolygon,
  segment,
  chain,
}

// Most-specific-type-first, matching the ordering scene_file_generator.dart
// already uses for its shape codec (RoundedPolygonShape/RectangleShape both
// extend PolygonShape, so they must be checked before the generic case).
PhysicsShapeKind _kindOf(CollisionShape shape) {
  if (shape is CircleShape) return PhysicsShapeKind.circle;
  if (shape is RoundedPolygonShape) return PhysicsShapeKind.roundedPolygon;
  if (shape is RectangleShape) return PhysicsShapeKind.rectangle;
  if (shape is PolygonShape) return PhysicsShapeKind.polygon;
  if (shape is CapsuleShape) return PhysicsShapeKind.capsule;
  if (shape is SegmentShape) return PhysicsShapeKind.segment;
  if (shape is ChainShape) return PhysicsShapeKind.chain;
  return PhysicsShapeKind.circle;
}

CollisionShape _defaultShapeFor(PhysicsShapeKind kind) {
  switch (kind) {
    case PhysicsShapeKind.circle:
      return CircleShape(24);
    case PhysicsShapeKind.rectangle:
      return RectangleShape(64, 40);
    case PhysicsShapeKind.capsule:
      return CapsuleShape.vertical(height: 52, radius: 10);
    case PhysicsShapeKind.polygon:
      return PolygonShape([
        const Offset(0, -30),
        const Offset(28, -8),
        const Offset(18, 28),
        const Offset(-18, 28),
        const Offset(-28, -8),
      ]);
    case PhysicsShapeKind.roundedPolygon:
      return RoundedPolygonShape.rect(width: 56, height: 36, cornerRadius: 8);
    case PhysicsShapeKind.segment:
      return SegmentShape(
        const Offset(-48, 0),
        const Offset(48, -20),
        thickness: 3,
      );
    case PhysicsShapeKind.chain:
      return ChainShape(const [
        Offset(-60, 8),
        Offset(-30, -14),
        Offset(0, 8),
        Offset(30, -14),
        Offset(60, 8),
      ], thickness: 3);
  }
}

PhysicsBodyComponent _asBody(Component c) => c as PhysicsBodyComponent;

/// The single "Add Component" entry for [PhysicsBodyComponent], replacing
/// the old per-shape/per-sensor catalog entries. Shape is chosen via the
/// `shapeKind` dropdown; only the dimension fields relevant to the selected
/// shape are shown (see [EditorComponentField.visibleWhen]).
class PhysicsBodyEditorComponent extends EditorComponent {
  PhysicsBodyEditorComponent()
    : super(
        id: 'physics_body_9f2c1a04',
        name: 'Physics Body',
        type: 'PhysicsBodyComponent',
        group: 'Physics',
        description: 'Rigid body with a selectable collision shape.',
        allowMultiple: false,
        deletable: true,
        componentType: ComponentType.core,
        icon: Icons.category_outlined,
        accentColor: const Color(0xFFFF7043),
        factory: () => PhysicsBodyComponent(
          shape: CircleShape(24),
          mass: 1.0,
          isStatic: false,
          restitution: 0.6,
          drag: 0.98,
        ),
        fields: const [],
        fieldGroups: [
          EditorFieldGroup(
            name: 'Shape',
            fields: [
              EditorComponentField(
                name: 'shapeKind',
                label: 'Shape',
                kind: EditorFieldKind.enumeration,
                enumValues: PhysicsShapeKind.values.map((k) => k.name).toList(),
                enumParser: (s) => PhysicsShapeKind.values.byName(s),
                read: (c) => _kindOf(_asBody(c).shape),
                write: (c, v) {
                  final body = _asBody(c);
                  final kind = v as PhysicsShapeKind;
                  if (_kindOf(body.shape) == kind) return;
                  body.shape = _defaultShapeFor(kind);
                },
              ),
              // ── Circle ──────────────────────────────────────────────────
              EditorComponentField(
                name: 'radius',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 1.0,
                  fractionDigits: 1,
                  min: 0.5,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.circle,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is CircleShape ? s.radius : 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  if (body.shape is CircleShape) {
                    body.shape = CircleShape((v as num).toDouble());
                  }
                },
              ),
              // ── Rectangle ───────────────────────────────────────────────
              EditorComponentField(
                name: 'width',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 1.0,
                  fractionDigits: 1,
                  min: 0.5,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.rectangle,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is RectangleShape ? s.width : 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is RectangleShape) {
                    body.shape = RectangleShape(
                      (v as num).toDouble(),
                      s.height,
                    );
                  }
                },
              ),
              EditorComponentField(
                name: 'height',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 1.0,
                  fractionDigits: 1,
                  min: 0.5,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.rectangle,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is RectangleShape ? s.height : 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is RectangleShape) {
                    body.shape = RectangleShape(s.width, (v as num).toDouble());
                  }
                },
              ),
              // ── Capsule (height/radius via CapsuleShape.vertical) ──────
              EditorComponentField(
                name: 'capsuleHeight',
                label: 'Height',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 1.0,
                  fractionDigits: 1,
                  min: 1.0,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.capsule,
                read: (c) {
                  final s = _asBody(c).shape;
                  if (s is CapsuleShape) {
                    return (s.center1 - s.center2).distance + s.radius * 2;
                  }
                  return 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is CapsuleShape) {
                    body.shape = CapsuleShape.vertical(
                      height: (v as num).toDouble(),
                      radius: s.radius,
                    );
                  }
                },
              ),
              EditorComponentField(
                name: 'capsuleRadius',
                label: 'Radius',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.5,
                  fractionDigits: 1,
                  min: 0.5,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.capsule,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is CapsuleShape ? s.radius : 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is CapsuleShape) {
                    final height =
                        (s.center1 - s.center2).distance + s.radius * 2;
                    body.shape = CapsuleShape.vertical(
                      height: height,
                      radius: (v as num).toDouble(),
                    );
                  }
                },
              ),
              // ── Polygon / RoundedPolygon / Chain vertices ──────────────
              EditorComponentField(
                name: 'vertices',
                kind: EditorFieldKind.offsetList,
                visibleWhen: (c) {
                  final k = _kindOf(_asBody(c).shape);
                  return k == PhysicsShapeKind.polygon ||
                      k == PhysicsShapeKind.roundedPolygon ||
                      k == PhysicsShapeKind.chain;
                },
                read: (c) {
                  final s = _asBody(c).shape;
                  if (s is PolygonShape) return List<Offset>.from(s.vertices);
                  if (s is ChainShape) return List<Offset>.from(s.vertices);
                  return const <Offset>[];
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  final list = (v as List).cast<Offset>();
                  if (s is ChainShape) {
                    if (list.length < 2) return;
                    s.vertices
                      ..clear()
                      ..addAll(list);
                  } else if (s is PolygonShape) {
                    if (list.length < 3) return;
                    s.vertices
                      ..clear()
                      ..addAll(list);
                  }
                },
              ),
              // ── RoundedPolygon ──────────────────────────────────────────
              EditorComponentField(
                name: 'cornerRadius',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.5,
                  fractionDigits: 1,
                  min: 0.0,
                ),
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) ==
                    PhysicsShapeKind.roundedPolygon,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is RoundedPolygonShape ? s.cornerRadius : 0.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is RoundedPolygonShape) {
                    body.shape = RoundedPolygonShape(
                      List<Offset>.from(s.vertices),
                      (v as num).toDouble(),
                    );
                  }
                },
              ),
              // ── Segment ─────────────────────────────────────────────────
              EditorComponentField(
                name: 'point1',
                kind: EditorFieldKind.offset,
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.segment,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is SegmentShape ? s.point1 : Offset.zero;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is SegmentShape) {
                    body.shape = SegmentShape(
                      v as Offset,
                      s.point2,
                      thickness: s.thickness,
                    );
                  }
                },
              ),
              EditorComponentField(
                name: 'point2',
                kind: EditorFieldKind.offset,
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.segment,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is SegmentShape ? s.point2 : Offset.zero;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is SegmentShape) {
                    body.shape = SegmentShape(
                      s.point1,
                      v as Offset,
                      thickness: s.thickness,
                    );
                  }
                },
              ),
              // Shared by Segment + Chain.
              EditorComponentField(
                name: 'thickness',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.5,
                  fractionDigits: 1,
                  min: 0.1,
                ),
                visibleWhen: (c) {
                  final k = _kindOf(_asBody(c).shape);
                  return k == PhysicsShapeKind.segment ||
                      k == PhysicsShapeKind.chain;
                },
                read: (c) {
                  final s = _asBody(c).shape;
                  if (s is SegmentShape) return s.thickness;
                  if (s is ChainShape) return s.thickness;
                  return 2.0;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  final t = (v as num).toDouble();
                  if (s is SegmentShape) {
                    body.shape = SegmentShape(s.point1, s.point2, thickness: t);
                  } else if (s is ChainShape) {
                    body.shape = ChainShape(
                      List<Offset>.from(s.vertices),
                      loop: s.loop,
                      thickness: t,
                    );
                  }
                },
              ),
              // ── Chain ───────────────────────────────────────────────────
              EditorComponentField(
                name: 'loop',
                kind: EditorFieldKind.boolean,
                visibleWhen: (c) =>
                    _kindOf(_asBody(c).shape) == PhysicsShapeKind.chain,
                read: (c) {
                  final s = _asBody(c).shape;
                  return s is ChainShape ? s.loop : false;
                },
                write: (c, v) {
                  final body = _asBody(c);
                  final s = body.shape;
                  if (s is ChainShape) {
                    body.shape = ChainShape(
                      List<Offset>.from(s.vertices),
                      loop: v as bool,
                      thickness: s.thickness,
                    );
                  }
                },
              ),
            ],
          ),
          EditorFieldGroup(
            name: 'Body',
            fields: [
              EditorComponentField(
                name: 'isStatic',
                label: 'Static',
                kind: EditorFieldKind.boolean,
                read: (c) => _asBody(c).isStatic,
                write: (c, v) => _asBody(c).isStatic = v as bool,
              ),
              EditorComponentField(
                name: 'isSensor',
                label: 'Sensor',
                kind: EditorFieldKind.boolean,
                read: (c) => _asBody(c).isSensor,
                write: (c, v) => _asBody(c).isSensor = v as bool,
              ),
              EditorComponentField(
                name: 'isOneWay',
                label: 'One-way',
                kind: EditorFieldKind.boolean,
                read: (c) => _asBody(c).isOneWay,
                write: (c, v) => _asBody(c).isOneWay = v as bool,
              ),
              EditorComponentField(
                name: 'massValue',
                label: 'Mass',
                kind: EditorFieldKind.decimal,
                // min is intentionally > 0: a dynamic body's inverse mass
                // (1/mass) is used directly by the impulse solver, so a mass
                // of exactly 0 (or negative, from a hand-edited scene file)
                // produces a divide-by-zero/NaN cascade in physics stepping.
                scrubConfig: const NumberScrubConfig(
                  step: 0.1,
                  fractionDigits: 2,
                  min: 0.01,
                ),
                read: (c) => _asBody(c).mass,
                write: (c, v) =>
                    _asBody(c).mass = (v as num).toDouble().clamp(0.01, double.infinity),
              ),
              EditorComponentField(
                name: 'drag',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.05,
                  fractionDigits: 2,
                  min: 0.0,
                ),
                read: (c) => _asBody(c).drag,
                write: (c, v) => _asBody(c).drag = (v as num).toDouble(),
              ),
              EditorComponentField(
                name: 'restitution',
                label: 'Rest.',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.05,
                  fractionDigits: 2,
                  min: 0.0,
                ),
                read: (c) => _asBody(c).restitution,
                write: (c, v) => _asBody(c).restitution = (v as num).toDouble(),
              ),
            ],
          ),
          EditorFieldGroup(
            name: 'Collision',
            fields: [
              EditorComponentField(
                name: 'categoryBits',
                label: 'Category',
                kind: EditorFieldKind.integer,
                scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
                read: (c) => _asBody(c).categoryBits,
                write: (c, v) => _asBody(c).categoryBits = (v as num).toInt(),
              ),
              EditorComponentField(
                name: 'maskBits',
                label: 'Mask Bits',
                kind: EditorFieldKind.integer,
                scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
                read: (c) => _asBody(c).maskBits,
                write: (c, v) => _asBody(c).maskBits = (v as num).toInt(),
              ),
              EditorComponentField(
                name: 'groupIndex',
                label: 'Group Index',
                kind: EditorFieldKind.integer,
                scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
                read: (c) => _asBody(c).groupIndex,
                write: (c, v) => _asBody(c).groupIndex = (v as num).toInt(),
              ),
            ],
          ),
          EditorFieldGroup(
            name: 'Debug',
            fields: [
              EditorComponentField(
                name: 'showDebugOutline',
                label: 'Show Outline',
                kind: EditorFieldKind.boolean,
                read: (c) => _asBody(c).showDebugOutline,
                write: (c, v) => _asBody(c).showDebugOutline = v as bool,
              ),
            ],
          ),
        ],
      );
}
