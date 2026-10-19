import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/view/orbit_fly_editor_view.dart';
import '../split/split_views.dart';

/// The 3-D designer's VIEW section: how the scene is drawn (lit, unlit,
/// wireframe, its colliders), perspective or orthographic, the selection's
/// outline, and a slice that takes away what is above a height — to work
/// inside a building, a floor at a time.
///
/// Editor-only: what the game draws is unchanged.
class View3DPanel extends StatelessWidget {
  const View3DPanel({super.key, required this.scope, this.split});

  /// The editor whose view it sets.
  final EditorScope scope;

  /// The four views, where the editor offers them.
  final SplitViews? split;

  static TextStyle get _label =>
      TextStyle(color: EditorTheme.textSecondary, fontSize: 11);

  @override
  Widget build(BuildContext context) {
    final state = scope.designer3D;
    return SignalBuilder3<ViewMode3D, bool, bool>(
      signal1: state.viewMode,
      signal2: state.outline,
      signal3: state.sliceOn,
      builder: (context, mode, outline, slicing, _) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            EditorSegmented<ViewMode3D>(
              value: mode,
              expand: true,
              options: [for (final m in ViewMode3D.values) (m, m.label)],
              tooltips: {for (final m in ViewMode3D.values) m: m.description},
              onChanged: (m) => state.viewMode.value = m,
            ),
            const SizedBox(height: 8),
            _row('Orthographic', 'Pad 5', _OrthographicToggle(scope: scope)),
            if (split case final views?)
              _row(
                'Four views',
                tooltipWithShortcut(
                  'Top, front, side and perspective',
                  scope.commands.shortcutOf('editor.view.split'),
                ),
                SignalBuilder<bool>(
                  signal: views.on,
                  builder: (context, on, _) => EditorToggle(
                    value: on,
                    label: 'Four views',
                    onChanged: (_) => views.toggle(),
                  ),
                ),
              ),
            _row(
              'Outline the selection',
              null,
              EditorToggle(
                value: outline,
                label: 'Outline the selection',
                onChanged: (v) => state.outline.value = v,
              ),
            ),
            _row(
              'Slice above',
              'Hide what is higher, to see inside',
              EditorToggle(
                value: slicing,
                label: 'Slice above a height',
                onChanged: (v) => state.sliceOn.value = v,
              ),
            ),
            if (slicing) _SliceHeight(scope: scope),
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String? hint, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Tooltip(
            message: hint ?? label,
            child: Text(label, style: _label, overflow: TextOverflow.ellipsis),
          ),
        ),
        control,
      ],
    ),
  );
}

/// Perspective or orthographic, kept in step with the view — which pad 5
/// and the view cube switch too, so it looks again a few times a second.
class _OrthographicToggle extends StatefulWidget {
  const _OrthographicToggle({required this.scope});

  final EditorScope scope;

  @override
  State<_OrthographicToggle> createState() => _OrthographicToggleState();
}

class _OrthographicToggleState extends State<_OrthographicToggle> {
  Timer? _look;
  bool _shown = false;

  bool get _ortho {
    final view = widget.scope.sceneView;
    return view is OrbitFlyEditorView && view.orthographic;
  }

  @override
  void initState() {
    super.initState();
    _shown = _ortho;
    _look = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _ortho != _shown) setState(() {});
    });
  }

  @override
  void dispose() {
    _look?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.scope.sceneView;
    final ortho = _shown = _ortho;
    return EditorToggle(
      value: ortho,
      label: 'Orthographic',
      onChanged: view is! OrbitFlyEditorView
          ? null
          : (v) => setState(() => view.orthographic = v),
    );
  }
}

/// The slice's height, in metres up, a move step at a time.
class _SliceHeight extends StatelessWidget {
  const _SliceHeight({required this.scope});

  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    final state = scope.designer3D;
    double step() {
      final s = scope.sceneState.moveStep3D;
      return s > 0 ? s : 0.25;
    }

    return SignalBuilder<double>(
      signal: state.sliceY,
      builder: (context, y, _) => Row(
        children: [
          Expanded(
            child: Text(
              // +Y is down: the height is -Y.
              '${(-y).abs() < 0.005 ? '0.00' : (-y).toStringAsFixed(2)} m up',
              style: View3DPanel._label,
            ),
          ),
          EditorIconButton(
            icon: Icons.remove,
            tooltip: 'Lower',
            onTap: () => state.sliceY.value = y + step(),
          ),
          EditorIconButton(
            icon: Icons.add,
            tooltip: 'Higher',
            onTap: () => state.sliceY.value = y - step(),
          ),
          // A height only a level plane has: an upright one's offset is a
          // depth or a side, not how high it is.
          SignalBuilder<WorkingPlaneAxis>(
            signal: state.planeAxis,
            builder: (context, axis, _) => EditorIconButton(
              icon: Icons.layers_outlined,
              tooltip: axis == WorkingPlaneAxis.ground
                  ? 'At the working plane, a little above it'
                  : 'At the working plane: only when it lies level',
              onTap: axis == WorkingPlaneAxis.ground
                  ? () => state.sliceY.value = state.plane.offset - 2
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
