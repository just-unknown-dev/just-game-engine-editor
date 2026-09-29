/// The diamond beside an inspector field while a timeline is open: keys the
/// field at the playhead, and says whether the timeline animates it.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import 'timeline_session.dart';

class FieldKeyButton extends StatefulWidget {
  const FieldKeyButton({
    super.key,
    required this.session,
    required this.entity,
    required this.component,
    required this.fields,
  });

  final TimelineSession session;
  final jge.Entity entity;
  final jge.Component component;

  /// The fields of the row this sits beside: one, or the cells of a shared
  /// row.
  final List<jge.SchemaField> fields;

  @override
  State<FieldKeyButton> createState() => _FieldKeyButtonState();
}

class _FieldKeyButtonState extends State<FieldKeyButton> {
  final List<void Function()> _stop = [];

  @override
  void initState() {
    super.initState();
    void rebuild() {
      if (mounted) setState(() {});
    }

    // The playhead moving on or off a key changes what the diamond says.
    for (final signal in <Signal<Object?>>[
      widget.session.playhead,
      widget.session.revision,
    ]) {
      _stop.add(signal.watch(rebuild));
    }
  }

  @override
  void dispose() {
    for (final stop in _stop) {
      stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    var state = FieldKeyState.none;
    for (final f in widget.fields) {
      final s = session.keyStateOf(widget.entity, widget.component, f);
      if (s.index > state.index) state = s;
    }
    final (icon, color, message) = switch (state) {
      FieldKeyState.keyed => (
        Icons.diamond,
        EditorTheme.warning,
        'Keyed here. Click to key it again with this value.',
      ),
      FieldKeyState.animated => (
        Icons.diamond_outlined,
        EditorTheme.warning,
        'Animated by the timeline. Click to add a key here.',
      ),
      FieldKeyState.none => (
        Icons.diamond_outlined,
        EditorTheme.textMuted,
        'Add to the timeline, with a key here.',
      ),
    };
    return Tooltip(
      message: message,
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () =>
            session.keyFields(widget.entity, widget.component, widget.fields),
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}
