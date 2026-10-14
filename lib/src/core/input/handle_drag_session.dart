import 'package:flutter/painting.dart';

import '../../extension/viewport_handles.dart';
import '../entity/component_edit.dart';
import '../scope/editor_scope.dart';
import '../view/editor_view.dart';

/// One drag (or click) of a [ViewportHandle] at a time: the handle under a
/// press, the drag handed to it, and what it changed in its component
/// recorded as one undo step when the press ends.
final class HandleDragSession {
  /// Drags whose changes go into [scope]'s history.
  HandleDragSession(this.scope);

  /// The editor.
  final EditorScope scope;

  /// How near, in pixels, a press must be to take a handle.
  static const double reach = 8;

  ViewportHandle? _active;
  int _index = -1;
  Offset _down = Offset.zero;
  bool _moved = false;
  bool _alt = false;
  ComponentEdit? _edit;

  /// Whether a handle is held.
  bool get isDragging => _active != null;

  /// Which of the handles last pressed is held, or -1.
  int get activeIndex => _active == null ? -1 : _index;

  /// The index of the handle in [handles] nearest [screen] within [reach],
  /// or -1. "+" handles yield to a corner on top of them.
  static int hit(Offset screen, List<ViewportHandle> handles, EditorView view) {
    var best = -1;
    var bestScore = double.infinity;
    for (var i = 0; i < handles.length; i++) {
      final at = view.isPlanar
          ? view.worldToScreen(Offset(handles[i].position.x, handles[i].position.y))
          : view.projectToScreen(handles[i].position);
      if (at == null) continue;
      final distance = (at - screen).distance;
      if (distance > reach) continue;
      final score = distance + (handles[i].style == ViewportHandleStyle.add ? reach : 0);
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /// Takes hold of the handle among [handles] under [screen], if there is
  /// one; [alt] when Alt is held.
  bool down(Offset screen, List<ViewportHandle> handles, EditorView view, {bool alt = false}) {
    final index = hit(screen, handles, view);
    if (index < 0) return false;
    _active = handles[index];
    _index = index;
    _down = screen;
    _moved = false;
    _alt = alt;
    _edit = ComponentEdit.begin(scope, _active!.component);
    return true;
  }

  /// The pointer moved to [screen]: the held handle follows (snapping when
  /// [snap], to [grid]).
  void move(Offset screen, EditorView view, {bool snap = false, double grid = 1}) {
    final handle = _active;
    if (handle == null) return;
    if (!_moved && (screen - _down).distance < 3) return;
    _moved = true;
    handle.onDrag(
      HandleDrag(ray: view.screenToRay(screen), start: handle.position, snap: snap, grid: grid),
    );
    scope.sceneState.refresh();
  }

  /// The press ended: a click (no drag) goes to the handle's click; either
  /// way what changed is one undo step.
  void up() {
    final handle = _active;
    if (handle == null) return;
    if (!_moved) handle.onClick?.call(HandleClick(alt: _alt));
    _finish(handle);
  }

  /// The press was taken away: what the drag changed is still recorded.
  void cancel() {
    final handle = _active;
    if (handle != null) _finish(handle);
  }

  void _finish(ViewportHandle handle) {
    _active = null;
    final edit = _edit;
    _edit = null;
    final definition = scope.definitions.definitionFor(handle.component);
    edit?.commit('Edit ${definition?.hints.name ?? definition?.type ?? 'component'}');
  }
}
