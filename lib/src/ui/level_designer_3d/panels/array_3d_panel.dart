import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/entity/entity_ops.dart';
import '../../../core/scope/editor_scope_services.dart';

/// The 3-D designer's ARRAY section: copies of the selection in a row, a
/// grid or round a circle, made as one undo step. Distances are in metres,
/// up as up (the engine's -Y).
class Array3DPanel extends StatelessWidget {
  const Array3DPanel({super.key, required this.scope, required this.make});

  /// The editor whose array settings it shows.
  final EditorScope scope;

  /// Makes the copies [spec] lays out.
  final void Function(Array3DSpec spec) make;

  static TextStyle get _label =>
      TextStyle(color: EditorTheme.textSecondary, fontSize: 11);

  @override
  Widget build(BuildContext context) {
    final array = scope.designer3D.array;
    return SignalBuilder<Array3DSpec>(
      signal: array,
      builder: (context, spec, _) {
        void set(Array3DSpec next) => array.value = next;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              EditorSegmented<ArrayMode3D>(
                value: spec.mode,
                expand: true,
                options: [for (final m in ArrayMode3D.values) (m, m.label)],
                tooltips: {
                  for (final m in ArrayMode3D.values) m: m.description,
                },
                onChanged: (m) => set(spec.copyWith(mode: m)),
              ),
              const SizedBox(height: 6),
              ...switch (spec.mode) {
                ArrayMode3D.linear => [
                  _row('Count', 'How many, the original among them', [
                    _whole(spec.count, (v) => set(spec.copyWith(count: v))),
                  ]),
                  _row('Step', 'From one to the next: X, up, Z (m)', [
                    _metres(spec.stepX, (v) => set(spec.copyWith(stepX: v))),
                    _metres(-spec.stepY, (v) => set(spec.copyWith(stepY: -v))),
                    _metres(spec.stepZ, (v) => set(spec.copyWith(stepZ: v))),
                  ]),
                ],
                ArrayMode3D.grid => [
                  _row('Count', 'How many along X, up and along Z', [
                    _whole(spec.columns, (v) => set(spec.copyWith(columns: v))),
                    _whole(spec.floors, (v) => set(spec.copyWith(floors: v))),
                    _whole(spec.rows, (v) => set(spec.copyWith(rows: v))),
                  ]),
                  _row('Spacing', 'How far apart: X, up, Z (m)', [
                    _metres(
                      spec.spacingX,
                      (v) => set(spec.copyWith(spacingX: v)),
                    ),
                    _metres(
                      spec.spacingY,
                      (v) => set(spec.copyWith(spacingY: v)),
                    ),
                    _metres(
                      spec.spacingZ,
                      (v) => set(spec.copyWith(spacingZ: v)),
                    ),
                  ]),
                ],
                ArrayMode3D.radial => [
                  _row(
                    'Count',
                    'How many round the circle, the original among them',
                    [_whole(spec.around, (v) => set(spec.copyWith(around: v)))],
                  ),
                  _row(
                    'Radius',
                    'The circle\'s middle is this far along -X (m)',
                    [
                      _metres(
                        spec.radius,
                        (v) => set(spec.copyWith(radius: v)),
                      ),
                    ],
                  ),
                  _row('Sweep', 'How far round they go (degrees)', [
                    _metres(
                      spec.sweep,
                      (v) => set(spec.copyWith(sweep: v)),
                      digits: 0,
                    ),
                  ]),
                  _row('Face the middle', 'Each turns as it goes round', [
                    EditorToggle(
                      value: spec.faceCentre,
                      label: 'Face the middle',
                      onChanged: (v) => set(spec.copyWith(faceCentre: v)),
                    ),
                  ]),
                ],
              },
              const SizedBox(height: 6),
              SignalBuilder<jge.Entity?>(
                signal: scope.sceneState.selectedEntity,
                builder: (context, selected, _) {
                  // What it makes, in entities: each copy holds a copy of
                  // everything in what is selected.
                  final made = selected == null
                      ? 0
                      : scope.entities.arrayEntityCount3D(spec);
                  final tooMany = made > EntityOps.maxArrayEntities;
                  final copies = spec.total - 1;
                  final why = tooMany
                      ? 'One array makes at most '
                            '${EntityOps.maxArrayEntities} entities'
                      : made > copies
                      ? '$made entities, with what they hold'
                      : null;
                  final button = EditorButton(
                    label: spec.total <= 1
                        ? 'Nothing to make'
                        : tooMany
                        ? 'Too many: $made entities'
                        : 'Make $copies cop${copies == 1 ? 'y' : 'ies'}',
                    icon: Icons.grid_view,
                    onPressed: selected == null || spec.total <= 1 || tooMany
                        ? null
                        : () => make(spec),
                  );
                  return why == null
                      ? button
                      : Tooltip(message: why, child: button);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _row(String label, String hint, List<Widget> fields) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Tooltip(
            message: hint,
            child: Text(label, style: _label, overflow: TextOverflow.ellipsis),
          ),
        ),
        for (final field in fields) ...[
          const SizedBox(width: 4),
          SizedBox(width: field is EditorToggle ? null : 46, child: field),
        ],
      ],
    ),
  );

  static Widget _whole(int value, ValueChanged<int> onChanged) =>
      MiniNumberField(
        value: value.toDouble(),
        fractionDigits: 0,
        onSubmitted: (v) => onChanged(v.round().clamp(1, 100)),
      );

  static Widget _metres(
    double value,
    ValueChanged<double> onChanged, {
    int digits = 2,
  }) => MiniNumberField(
    value: value == 0 ? 0 : value,
    fractionDigits: digits,
    onSubmitted: onChanged,
  );
}
