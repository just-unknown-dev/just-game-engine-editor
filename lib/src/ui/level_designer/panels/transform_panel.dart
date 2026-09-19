import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/constants/editor_constants.dart';
import '../../widgets/scrubbable_number_field.dart';
import '../level_designer_session.dart';
import '../state/selection_ops.dart';

/// Position, size and rotation of the whole selection, as numbers.
///
/// X and Y are the selection's top-left; W and H resize everything in
/// proportion, exactly like dragging a corner handle. Rotation is shown and
/// set per entity. A scrub is one undo step, however far it goes.
class TransformPanel extends StatefulWidget {
  const TransformPanel({super.key, required this.session});

  /// The session whose selection this edits.
  final LevelDesignerSession session;

  @override
  State<TransformPanel> createState() => _TransformPanelState();
}

enum _Field { x, y, w, h, r }

class _TransformPanelState extends State<TransformPanel> {
  final Map<_Field, TextEditingController> _text = {
    for (final f in _Field.values) f: TextEditingController(),
  };
  final Map<_Field, FocusNode> _focus = {
    for (final f in _Field.values) f: FocusNode(),
  };

  LevelDesignerSession get _session => widget.session;

  List<VoidCallback> _stopWatching = const [];

  /// Follows the selection and every edit to it.
  void _watch() {
    final state = _session.sceneState;
    _stopWatching = [
      state.selectedEntity.watch(_sync),
      state.multiSelectedIds.watch(_sync),
      state.revision.watch(_sync),
    ];
  }

  void _unwatch() {
    for (final stop in _stopWatching) {
      stop();
    }
    _stopWatching = const [];
  }

  @override
  void initState() {
    super.initState();
    _watch();
    _sync();
  }

  @override
  void didUpdateWidget(TransformPanel old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      _unwatch();
      _watch();
      _sync();
    }
  }

  @override
  void dispose() {
    _unwatch();
    for (final c in _text.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Refreshes the numbers from the selection — except a field being typed
  /// into, which would otherwise be overwritten under the cursor.
  void _sync() {
    if (!mounted) return;
    final entities = _session.selectionEntities();
    final bounds = SelectionOps.boundsOf(entities);
    final rotation = entities.isEmpty
        ? 0.0
        : entities.first.getComponent<jge.TransformComponent>()?.rotation ?? 0;
    final values = {
      _Field.x: bounds?.left,
      _Field.y: bounds?.top,
      _Field.w: bounds?.width,
      _Field.h: bounds?.height,
      _Field.r: rotation * 180 / math.pi,
    };
    for (final f in _Field.values) {
      if (_focus[f]!.hasFocus) continue;
      final v = values[f];
      _text[f]!.text = v == null ? '' : _format(v);
    }
    setState(() {});
  }

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void _commit(_Field field) {
    final value = double.tryParse(_text[field]!.text);
    final entities = _session.selectionEntities();
    final bounds = SelectionOps.boundsOf(entities);
    if (value == null || bounds == null) return;
    final key = 'panel:${field.name}:${entities.map((e) => e.id).join(',')}';
    final ops = _session.ops;
    switch (field) {
      case _Field.x:
        ops.moveTo(entities, Offset(value, bounds.top), mergeKey: key);
      case _Field.y:
        ops.moveTo(entities, Offset(bounds.left, value), mergeKey: key);
      case _Field.w:
        ops.resizeTo(
          entities,
          Rect.fromLTWH(
            bounds.left,
            bounds.top,
            math.max(1, value),
            bounds.height,
          ),
          mergeKey: key,
        );
      case _Field.h:
        ops.resizeTo(
          entities,
          Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            math.max(1, value),
          ),
          mergeKey: key,
        );
      case _Field.r:
        ops.setRotation(entities, value * math.pi / 180, mergeKey: key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entities = _session.selectionEntities();
    if (entities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Select something to edit its position and size.',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      );
    }
    final bounds = SelectionOps.boundsOf(entities);
    final resizable = bounds != null && bounds.width > 0 && bounds.height > 0;

    Widget field(_Field f, String label, NumberScrubConfig config) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ScrubbableNumberField(
        label: label,
        labelWidth: 22,
        controller: _text[f]!,
        focusNode: _focus[f]!,
        config: config,
        onCommit: () => _commit(f),
      ),
    );

    const position = NumberScrubConfig(step: 1, fractionDigits: 0);
    const size = NumberScrubConfig(step: 1, fractionDigits: 0, min: 1);
    const angle = NumberScrubConfig(step: 1, fractionDigits: 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entities.length == 1
                ? entities.single.name ?? 'Entity'
                : '${entities.length} selected',
            style: const TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: field(_Field.x, 'X', position)),
              const SizedBox(width: 6),
              Expanded(child: field(_Field.y, 'Y', position)),
            ],
          ),
          if (resizable)
            Row(
              children: [
                Expanded(child: field(_Field.w, 'W', size)),
                const SizedBox(width: 6),
                Expanded(child: field(_Field.h, 'H', size)),
              ],
            ),
          field(_Field.r, '°', angle),
        ],
      ),
    );
  }
}
