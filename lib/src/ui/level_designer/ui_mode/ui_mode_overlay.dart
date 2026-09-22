/// The viewport, showing the interface instead of the world.
///
/// A device frame at the canvas's design size with the *real* UI layer
/// inside it — the same widgets the game builds — and, over that, the
/// editor's own handles. What is seen here is what ships, because it is
/// the same thing.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/state/editor_scene_state.dart';
import '../../widgets/editor_menu.dart';
import '../state/editor_commands.dart';
import '../state/editor_history.dart';
import 'ui_device.dart';
import 'ui_mode_session.dart';

class UiModeOverlay extends StatefulWidget {
  const UiModeOverlay({
    super.key,
    required this.session,
    required this.sceneState,
    required this.history,
  });

  final UiModeSession session;
  final EditorSceneState sceneState;
  final EditorHistory history;

  @override
  State<UiModeOverlay> createState() => _UiModeOverlayState();
}

class _UiModeOverlayState extends State<UiModeOverlay> {
  final GlobalKey _frameKey = GlobalKey();

  /// The drag in progress: what is moving, where from, and how it is being
  /// changed.
  jge.Entity? _dragging;
  Offset _dragStart = Offset.zero;
  Offset _startOffset = Offset.zero;
  Size _startSize = Size.zero;
  _Handle _handle = _Handle.move;
  List<Rect> _snapLines = const [];

  UiModeSession get session => widget.session;

  jge.Entity? get _selected => widget.sceneState.selectedEntity.value;

  RenderBox? get _frame {
    final box = _frameKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder3<UiDevice, bool, bool>(
      signal1: session.device,
      signal2: session.landscape,
      signal3: session.showBoxes,
      builder: (context, device, landscape, boxes, _) {
        final frame = session.frameSize;
        return ColoredBox(
          // The world is still there, and still running; it is just not
          // what is being worked on.
          color: const Color(0xCC08070B),
          child: Column(
            children: [
              _Toolbar(session: session),
              Expanded(
                child: Center(
                  child: FittedBox(
                    child: Container(
                      width: frame.width,
                      height: frame.height,
                      decoration: BoxDecoration(
                        color: const Color(0xFF15131A),
                        border: Border.all(color: EditorTheme.border),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        key: _frameKey,
                        children: [
                          Positioned.fill(
                            child: MediaQuery(
                              // The device's own notch, so a canvas that
                              // keeps clear of one can be seen doing it.
                              data: MediaQueryData(
                                size: frame,
                                padding: EdgeInsets.only(
                                  top: landscape ? 0 : device.safeArea,
                                ),
                              ),
                              child: jge.UiLayer(
                                world: session.world,
                                nodeKeys: session.nodeKeys,
                              ),
                            ),
                          ),
                          Positioned.fill(child: _handles(boxes)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Picking, dragging and the boxes drawn over the interface.
  Widget _handles(bool showBoxes) {
    return SignalBuilder<jge.Entity?>(
      signal: widget.sceneState.selectedEntity,
      builder: (context, selected, _) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        child: CustomPaint(
          painter: _UiHandlesPainter(
            session: session,
            selected: selected,
            frame: _frame,
            showBoxes: showBoxes,
            snapLines: _snapLines,
            repaint: widget.sceneState.revision,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _onDown(PointerDownEvent event) {
    final frame = _frame;
    if (frame == null) return;
    final point = frame.globalToLocal(event.position);
    final selected = _selected;

    // A handle on what is already selected wins over picking something
    // else — otherwise the corner handles could never be grabbed.
    if (selected != null) {
      final rect = session.rectOf(selected, against: frame);
      if (rect != null) {
        final handle = _handleAt(rect, point);
        if (handle != null) {
          _begin(selected, point, handle);
          return;
        }
      }
    }

    final picked = session.pick(point, against: frame);
    if (picked == null) {
      widget.sceneState.clearSelection();
      return;
    }
    widget.sceneState.selectEntity(picked);
    _begin(picked, point, _Handle.move);
  }

  void _begin(jge.Entity entity, Offset point, _Handle handle) {
    final slot = entity.getComponent<jge.UiSlotComponent>();
    if (slot == null) return;
    setState(() {
      _dragging = entity;
      _dragStart = point;
      _handle = handle;
      _startOffset = slot.offset;
      _startSize = slot.size;
    });
  }

  void _onMove(PointerMoveEvent event) {
    final entity = _dragging;
    final frame = _frame;
    if (entity == null || frame == null) return;
    final slot = entity.getComponent<jge.UiSlotComponent>();
    if (slot == null) return;

    final point = frame.globalToLocal(event.position);
    var delta = point - _dragStart;
    var lines = const <Rect>[];

    if (_handle == _Handle.move) {
      if (session.snap.value) {
        final rect = session.rectOf(entity, against: frame);
        if (rect != null) {
          final snapped = snapUiDrag(
            // Where it was when the drag began, not where it is now.
            moving: rect.shift(_startOffset - slot.offset),
            offset: delta,
            targets: session.snapTargets(entity, against: frame),
          );
          delta = snapped.offset;
          lines = snapped.lines;
        }
      }
      _write(
        entity,
        slot,
        'Move ${entity.name ?? 'element'}',
        offset: _startOffset + delta,
      );
    } else {
      // A corner handle: the size grows by the drag, and the anchor stays
      // where it is.
      final signX = _handle == _Handle.left ? -1.0 : 1.0;
      final signY = _handle == _Handle.top ? -1.0 : 1.0;
      _write(
        entity,
        slot,
        'Resize ${entity.name ?? 'element'}',
        size: Size(
          (_startSize.width + delta.dx * signX).clamp(0.0, 4096.0),
          (_startSize.height + delta.dy * signY).clamp(0.0, 4096.0),
        ),
      );
    }
    setState(() => _snapLines = lines);
  }

  void _onUp(PointerUpEvent event) {
    if (_dragging == null && _snapLines.isEmpty) return;
    setState(() {
      _dragging = null;
      _snapLines = const [];
    });
  }

  /// Writes one field of a slot as an undoable edit.
  ///
  /// Each move is its own command, and the history merges the run of them
  /// into one step — so a drag undoes as a drag, not pixel by pixel.
  void _write(
    jge.Entity entity,
    jge.UiSlotComponent slot,
    String label, {
    Offset? offset,
    Size? size,
  }) {
    if (offset != null) {
      widget.history.push(
        ComponentFieldCommand(
          label: label,
          component: slot,
          before: slot.offset,
          after: offset,
          write: (c, v) => (c as jge.UiSlotComponent).offset = v as Offset,
          sceneState: widget.sceneState,
        ),
      );
    }
    if (size != null) {
      widget.history.push(
        ComponentFieldCommand(
          label: label,
          component: slot,
          before: slot.size,
          after: size,
          write: (c, v) => (c as jge.UiSlotComponent).size = v as Size,
          sceneState: widget.sceneState,
        ),
      );
    }
  }

  /// Which handle of [rect] is under [point], or null for none.
  static _Handle? _handleAt(Rect rect, Offset point) {
    const grab = 9.0;
    final corners = {
      _Handle.topLeft: rect.topLeft,
      _Handle.top: rect.topCenter,
      _Handle.left: rect.centerLeft,
      _Handle.bottomRight: rect.bottomRight,
    };
    for (final entry in corners.entries) {
      if ((entry.value - point).distance <= grab) return entry.key;
    }
    return null;
  }
}

/// What a drag is doing.
enum _Handle { move, top, left, topLeft, bottomRight }

/// The boxes, the selection and the snap lines.
class _UiHandlesPainter extends CustomPainter {
  _UiHandlesPainter({
    required this.session,
    required this.selected,
    required this.frame,
    required this.showBoxes,
    required this.snapLines,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final UiModeSession session;
  final jge.Entity? selected;
  final RenderBox? frame;
  final bool showBoxes;
  final List<Rect> snapLines;

  @override
  void paint(Canvas canvas, Size size) {
    final against = frame;
    if (against == null) return;

    if (showBoxes) {
      final faint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.primary.withValues(alpha: 0.25);
      for (final rect in session.snapTargets(null, against: against)) {
        canvas.drawRect(rect, faint);
      }
    }

    for (final line in snapLines) {
      canvas.drawRect(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF6BE58B),
      );
    }

    final entity = selected;
    if (entity == null) return;
    final rect = session.rectOf(entity, against: against);
    if (rect == null) return;

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = EditorTheme.primaryBright,
    );
    final handle = Paint()..color = EditorTheme.primaryBright;
    for (final corner in [
      rect.topLeft,
      rect.topCenter,
      rect.centerLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: 6, height: 6),
        handle,
      );
    }

    // The anchor it is pinned by, drawn where it pins.
    final slot = entity.getComponent<jge.UiSlotComponent>();
    if (slot == null || slot.mode != jge.UiSlotMode.anchored) return;
    final parent = rect;
    final pin = Offset(
      parent.left + slot.pivot.dx * parent.width,
      parent.top + slot.pivot.dy * parent.height,
    );
    canvas.drawCircle(pin, 3, Paint()..color = const Color(0xFFFFC53D));
  }

  @override
  bool shouldRepaint(_UiHandlesPainter old) =>
      old.selected != selected ||
      old.showBoxes != showBoxes ||
      old.snapLines != snapLines;
}

/// The strip above the frame: which screen, which way up, and what the
/// editor draws over it.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.session});

  final UiModeSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: EditorTheme.surfaceBg,
      child: Row(
        children: [
          const Text(
            'UI',
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          SignalBuilder<UiDevice>(
            signal: session.device,
            builder: (context, device, _) => Builder(
              builder: (context) => InkWell(
                onTap: () async {
                  final box = context.findRenderObject() as RenderBox?;
                  final at = box == null
                      ? Offset.zero
                      : box.localToGlobal(box.size.bottomLeft(Offset.zero));
                  final chosen = await showEditorMenu<UiDevice>(context, at, [
                    for (final option in UiDevices.all)
                      editorMenuItem(option, option.toString()),
                  ]);
                  if (chosen != null) session.device.value = chosen;
                },
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_iphone,
                      size: 13,
                      color: EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      device.toString(),
                      style: const TextStyle(
                        color: EditorTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          _Toggle(
            signal: session.landscape,
            icon: Icons.screen_rotation,
            tooltip: 'Turn the screen',
          ),
          _Toggle(
            signal: session.showBoxes,
            icon: Icons.border_all,
            tooltip: 'Show every box',
          ),
          _Toggle(
            signal: session.snap,
            icon: Icons.grid_goldenratio,
            tooltip: 'Snap to edges',
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.signal,
    required this.icon,
    required this.tooltip,
  });

  final Signal<bool> signal;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) => SignalBuilder<bool>(
    signal: signal,
    builder: (context, on, _) => Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: () => signal.value = !on,
        icon: Icon(icon),
        iconSize: 15,
        color: on ? EditorTheme.primaryBright : EditorTheme.textMuted,
        splashRadius: 14,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      ),
    ),
  );
}
