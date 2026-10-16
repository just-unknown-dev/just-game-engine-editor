import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// Which [jge.CollisionShape] a body uses. Never persisted: the shape's own
/// encoding carries its kind.
enum PhysicsShapeKind {
  circle,
  rectangle,
  capsule,
  polygon,
  roundedPolygon,
  segment,
  chain;

  // Most specific first: RoundedPolygonShape and RectangleShape both extend
  // PolygonShape.
  static PhysicsShapeKind of(jge.CollisionShape s) => switch (s) {
    jge.CircleShape() => circle,
    jge.RoundedPolygonShape() => roundedPolygon,
    jge.RectangleShape() => rectangle,
    jge.PolygonShape() => polygon,
    jge.CapsuleShape() => capsule,
    jge.SegmentShape() => segment,
    jge.ChainShape() => chain,
    _ => circle,
  };

  /// A sensible starting shape when the kind is switched.
  jge.CollisionShape get defaultShape => switch (this) {
    circle => jge.CircleShape(24),
    rectangle => jge.RectangleShape(64, 40),
    capsule => jge.CapsuleShape.vertical(height: 52, radius: 10),
    polygon => jge.PolygonShape(const [
      Offset(0, -30),
      Offset(28, -8),
      Offset(18, 28),
      Offset(-18, 28),
      Offset(-28, -8),
    ]),
    roundedPolygon => jge.RoundedPolygonShape.rect(
      width: 56,
      height: 36,
      cornerRadius: 8,
    ),
    segment => jge.SegmentShape(
      const Offset(-48, 0),
      const Offset(48, -20),
      thickness: 3,
    ),
    chain => jge.ChainShape(const [
      Offset(-60, 8),
      Offset(-30, -14),
      Offset(0, 8),
      Offset(30, -14),
      Offset(60, 8),
    ], thickness: 3),
  };
}

/// The editor for a `physicsShape` field: a kind dropdown, then only the
/// dimensions that kind has. Every edit produces a new shape for the field.
class PhysicsShapeEditor extends StatelessWidget {
  const PhysicsShapeEditor({super.key, required this.ctx});

  final FieldEditorContext ctx;

  static const _size = NumberScrubConfig(fractionDigits: 1, min: 0.5);
  static const _radius = NumberScrubConfig(
    step: 0.5,
    fractionDigits: 1,
    min: 0.5,
  );
  static const _thin = NumberScrubConfig(
    step: 0.5,
    fractionDigits: 1,
    min: 0.1,
  );
  static const _corner = NumberScrubConfig(
    step: 0.5,
    fractionDigits: 1,
    min: 0,
  );
  static const _point = NumberScrubConfig(fractionDigits: 1);

  @override
  Widget build(BuildContext context) {
    final shape = ctx.value is jge.CollisionShape
        ? ctx.value as jge.CollisionShape
        : PhysicsShapeKind.circle.defaultShape;
    final kind = PhysicsShapeKind.of(shape);
    final set = ctx.onChanged;
    Widget num(
      String label,
      double value,
      NumberScrubConfig cfg,
      void Function(double) apply,
    ) => ScrubFieldRow(
      label: label,
      value: value,
      scrubConfig: cfg,
      onChanged: apply,
    );
    List<Widget> point(String label, Offset p, void Function(Offset) apply) => [
      AxesFieldRow(
        label: label,
        axes: const ['X', 'Y'],
        values: [p.dx, p.dy],
        scrubConfig: _point,
        onChanged: (v) => apply(Offset(v[0], v[1])),
      ),
    ];

    final rows = <Widget>[
      DropdownEditorRow(
        label: ctx.label,
        value: kind.name,
        options: [for (final k in PhysicsShapeKind.values) k.name],
        onChanged: (name) {
          final next = PhysicsShapeKind.values.byName(name);
          if (next != kind) set(next.defaultShape);
        },
      ),
      ...switch (shape) {
        jge.CircleShape s => [
          num('Radius', s.radius, _size, (v) => set(jge.CircleShape(v))),
        ],
        jge.RoundedPolygonShape s => [
          OffsetListEditorRow(
            label: 'Vertices',
            points: List.of(s.vertices),
            onChanged: (v) {
              if (v.length >= 3) {
                set(jge.RoundedPolygonShape(List.of(v), s.cornerRadius));
              }
            },
          ),
          num(
            'Corner radius',
            s.cornerRadius,
            _corner,
            (v) => set(jge.RoundedPolygonShape(List.of(s.vertices), v)),
          ),
        ],
        jge.RectangleShape s => [
          num(
            'Width',
            s.width,
            _size,
            (v) => set(jge.RectangleShape(v, s.height)),
          ),
          num(
            'Height',
            s.height,
            _size,
            (v) => set(jge.RectangleShape(s.width, v)),
          ),
        ],
        jge.PolygonShape s => [
          OffsetListEditorRow(
            label: 'Vertices',
            points: List.of(s.vertices),
            onChanged: (v) {
              if (v.length >= 3) {
                set(jge.PolygonShape(List.of(v)));
              }
            },
          ),
        ],
        jge.CapsuleShape s => () {
          // Upright along Y, or lying along X: the two a level needs.
          final lying =
              s.center1.dy == s.center2.dy && s.center1.dx != s.center2.dx;
          final length = (s.center1 - s.center2).distance + s.radius * 2;
          jge.CapsuleShape make(double length, double radius, bool lying) {
            final half = math.max(length / 2 - radius, 0.0);
            return jge.CapsuleShape(
              center1: lying ? Offset(-half, 0) : Offset(0, -half),
              center2: lying ? Offset(half, 0) : Offset(0, half),
              radius: radius,
            );
          }

          return [
            DropdownEditorRow(
              label: 'Direction',
              value: lying ? 'lying' : 'upright',
              options: const ['upright', 'lying'],
              onChanged: (v) => set(make(length, s.radius, v == 'lying')),
            ),
            num(
              lying ? 'Length' : 'Height',
              length,
              const NumberScrubConfig(fractionDigits: 1, min: 1),
              (v) => set(make(v, s.radius, lying)),
            ),
            num(
              'Radius',
              s.radius,
              _radius,
              (v) => set(make(length, v, lying)),
            ),
          ];
        }(),
        jge.SegmentShape s => [
          ...point(
            'Point 1',
            s.point1,
            (p) => set(jge.SegmentShape(p, s.point2, thickness: s.thickness)),
          ),
          ...point(
            'Point 2',
            s.point2,
            (p) => set(jge.SegmentShape(s.point1, p, thickness: s.thickness)),
          ),
          num(
            'Thickness',
            s.thickness,
            _thin,
            (v) => set(jge.SegmentShape(s.point1, s.point2, thickness: v)),
          ),
        ],
        jge.ChainShape s => [
          OffsetListEditorRow(
            label: 'Vertices',
            points: List.of(s.vertices),
            onChanged: (v) {
              if (v.length >= 2) {
                set(
                  jge.ChainShape(
                    List.of(v),
                    loop: s.loop,
                    thickness: s.thickness,
                  ),
                );
              }
            },
          ),
          num(
            'Thickness',
            s.thickness,
            _thin,
            (v) => set(
              jge.ChainShape(List.of(s.vertices), loop: s.loop, thickness: v),
            ),
          ),
          BoolEditorRow(
            label: 'Loop',
            value: s.loop,
            onChanged: (v) => set(
              jge.ChainShape(
                List.of(s.vertices),
                loop: v,
                thickness: s.thickness,
              ),
            ),
          ),
        ],
        _ => const <Widget>[],
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 6),
            child: rows[i],
          ),
      ],
    );
  }
}
