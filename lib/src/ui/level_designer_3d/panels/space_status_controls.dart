import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';

/// The 3-D designer's move step, in metres, for its status bar: what the
/// gizmo, the handles, placing and the grid snap to. Kept in the settings.
class MoveStep3DField extends StatelessWidget {
  const MoveStep3DField({super.key, required this.scope});

  /// The editor whose settings it changes.
  final EditorScope scope;

  /// The steps on offer, metres.
  static const List<double> steps = [0.05, 0.1, 0.25, 0.5, 1, 2, 5];

  /// [metres] as the field shows it.
  static String label(double metres) =>
      metres >= 1 && metres == metres.roundToDouble()
      ? '${metres.toInt()} m'
      : '${metres.toString().replaceFirst(RegExp(r'0+$'), '')} m';

  @override
  Widget build(BuildContext context) => SignalBuilder<OverlayUiSettings>(
    signal: scope.prefs.settings,
    builder: (context, settings, _) {
      final current = settings.moveStep3D;
      return PopupMenuButton<double>(
        tooltip: 'Move step: what moving, placing and the grid snap to',
        initialValue: current,
        color: EditorTheme.menuBg,
        position: PopupMenuPosition.over,
        onSelected: (step) =>
            scope.prefs.change((s) => s.copyWith(moveStep3D: step)),
        itemBuilder: (context) => [
          for (final step in steps)
            PopupMenuItem(
              value: step,
              height: 30,
              child: Text(
                label(step),
                style: TextStyle(
                  color: step == current
                      ? EditorTheme.textPrimary
                      : EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label(current),
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: EditorTheme.textSecondary,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The working plane for the 3-D designer's status bar: which way it lies
/// and where, with a menu to turn it, move it a step, put it at the
/// selection or keep it there.
class WorkingPlaneControl extends StatelessWidget {
  const WorkingPlaneControl({
    super.key,
    required this.scope,
    required this.selection,
  });

  /// The editor whose plane it shows.
  final EditorScope scope;

  /// What is selected, for "to the selection".
  final List<jge.Entity> Function() selection;

  /// [plane] as the control says it: a height for the ground (up is -Y), a
  /// depth or an X for an upright one.
  static String describe(WorkingPlane plane) {
    final at = plane.axis == WorkingPlaneAxis.ground
        ? -plane.offset
        : plane.offset;
    // Not "-0.00": a height of nothing has no sign.
    return '${plane.axis.label} ${(at.abs() < 0.005 ? 0.0 : at).toStringAsFixed(2)} m';
  }

  @override
  Widget build(BuildContext context) {
    final state = scope.designer3D;
    return SignalBuilder3<WorkingPlaneAxis, double, bool>(
      signal1: state.planeAxis,
      signal2: state.planeOffset,
      signal3: state.followSelection,
      builder: (context, axis, offset, follow, _) => PopupMenuButton<String>(
        tooltip:
            'Working plane: where things go when nothing is under the '
            'pointer  (PgUp / PgDn move it, \\ turns it)',
        color: EditorTheme.menuBg,
        position: PopupMenuPosition.over,
        onSelected: (choice) {
          switch (choice) {
            case 'up':
              state.raise(_step);
            case 'down':
              state.raise(-_step);
            case 'zero':
              state.planeOffset.value = 0;
            case 'selection':
              final picked = selection();
              if (picked.isNotEmpty) state.moveTo(picked);
            case 'follow':
              state.followSelection.value = !follow;
            default:
              final turned = WorkingPlaneAxis.values
                  .where((a) => a.name == choice)
                  .firstOrNull;
              if (turned != null) state.planeAxis.value = turned;
          }
        },
        itemBuilder: (context) => [
          for (final a in WorkingPlaneAxis.values)
            CheckedPopupMenuItem(
              value: a.name,
              checked: a == axis,
              height: 30,
              child: Text(a.label, style: _item),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'up',
            height: 30,
            child: Text('A step up', style: _item),
          ),
          PopupMenuItem(
            value: 'down',
            height: 30,
            child: Text('A step down', style: _item),
          ),
          PopupMenuItem(
            value: 'zero',
            height: 30,
            child: Text('Back to 0', style: _item),
          ),
          PopupMenuItem(
            value: 'selection',
            height: 30,
            child: Text('To the selection', style: _item),
          ),
          CheckedPopupMenuItem(
            value: 'follow',
            checked: follow,
            height: 30,
            child: Text('Follow the selection', style: _item),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                follow ? Icons.my_location : Icons.layers_outlined,
                size: 14,
                color: EditorTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                follow
                    ? '${axis.label} · at the selection'
                    : describe(WorkingPlane(axis, offset)),
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: EditorTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _step {
    final step = scope.sceneState.moveStep3D;
    return step > 0 ? step : 1;
  }

  static TextStyle get _item =>
      TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
}

/// Where the 3-D gizmo sits on the selection, for the status bar: the
/// middle of what is selected, its own origin, or the middle of its base.
class PivotModeField extends StatelessWidget {
  const PivotModeField({super.key, required this.scope});

  /// The editor whose pivot it sets.
  final EditorScope scope;

  @override
  Widget build(BuildContext context) => SignalBuilder<PivotMode3D>(
    signal: scope.designer3D.pivotMode,
    builder: (context, mode, _) => PopupMenuButton<PivotMode3D>(
      tooltip:
          'Pivot: where the gizmo sits, and what it turns and scales about',
      initialValue: mode,
      color: EditorTheme.menuBg,
      position: PopupMenuPosition.over,
      onSelected: (m) => scope.designer3D.pivotMode.value = m,
      itemBuilder: (context) => [
        for (final m in PivotMode3D.values)
          PopupMenuItem(
            value: m,
            height: 30,
            child: Tooltip(
              message: m.description,
              child: Text(
                m.label,
                style: TextStyle(
                  color: m == mode
                      ? EditorTheme.textPrimary
                      : EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_center_focus,
              size: 14,
              color: EditorTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              mode.label,
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: EditorTheme.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
