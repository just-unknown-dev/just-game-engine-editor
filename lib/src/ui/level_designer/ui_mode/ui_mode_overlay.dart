/// The viewport, showing the interface instead of the world.
///
/// A device frame at the canvas's design size with the *real* UI layer
/// inside it — the same widgets the game builds — and, over that, the
/// editor's own handles. What is seen here is what ships, because it is
/// the same thing.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/scope/editor_scope.dart';
import '../../../core/state/editor_scene_state.dart';
import '../../panels/entity_inspector_panel.dart';
import '../../scene_tree/scene_tree_model.dart';
import '../../scene_tree/scene_tree_panel.dart';
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
    this.onClose,
    this.fullScreen,
    this.onToggleFullScreen,
    this.scope,
  });

  final UiModeSession session;
  final EditorSceneState sceneState;
  final EditorHistory history;

  /// Shuts the editor. Null when it is not shown as a window of its own —
  /// then it draws neither the close button nor the one beside it.
  final VoidCallback? onClose;

  /// Whether the window fills the editor, and how to say otherwise.
  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  /// Given when this is the editor's own window rather than a frame in
  /// somebody else's: then it brings its own tree and inspector, because
  /// the editor's are behind it and out of reach.
  final EditorScope? scope;

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

  /// The pointer pushing the view about with the middle button held.
  int? _panning;
  List<Rect> _snapLines = const [];

  UiModeSession get session => widget.session;

  jge.Entity? get _selected => widget.sceneState.selectedEntity.value;

  RenderBox? get _frame {
    final box = _frameKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// The keys the window answers to itself.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final close = widget.onClose;
    if (key == LogicalKeyboardKey.escape && close != null) {
      close();
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      session.zoomToFit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      session.zoomBy(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      session.zoomBy(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The device: as large as the window will take, or at the size the
  /// author asked for, with the room to move about that then needs.
  Widget _frameArea() {
    final frame = session.frameSize;
    final device = session.device.value;
    final landscape = session.landscape.value;
    final screen = DecoratedBox(
      // The border and the corners are drawn around the frame at full
      // size; inside the FittedBox they would be scaled with the rest.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FittedBox(
          // The box is already the device's shape, so filling it
          // scales both ways alike.
          fit: BoxFit.fill,
          child: Container(
            width: frame.width,
            height: frame.height,
            color: const Color(0xFF15131A),
            child: Stack(
              key: _frameKey,
              children: [
                Positioned.fill(
                  child: MediaQuery(
                    // The device's own notch, so a canvas that keeps
                    // clear of one can be seen doing it.
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
                Positioned.fill(child: _handles(session.showBoxes.value)),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // What fit comes to, so the first step in or out is a step from
        // the size on screen rather than from 100%.
        session.fittedZoom = math.min(
          box.maxWidth / frame.width,
          box.maxHeight / frame.height,
        );
        final area = Size(box.maxWidth, box.maxHeight);
        final zoom = session.shownZoom;
        final size = Size(frame.width * zoom, frame.height * zoom);
        // Fitted, the pan is nothing and this is the middle of the view.
        final origin = Offset(
          (area.width - size.width) / 2 + session.pan.value.dx,
          (area.height - size.height) / 2 + session.pan.value.dy,
        );

        /// Never so far that there is no corner of the screen left to
        /// take hold of.
        Offset held(Offset pan, Size of) {
          final x = math.max((of.width + area.width) / 2 - 48, 0.0);
          final y = math.max((of.height + area.height) / 2 - 48, 0.0);
          return Offset(pan.dx.clamp(-x, x), pan.dy.clamp(-y, y));
        }

        /// Sizes the screen [to], keeping whatever is under [at] there.
        void zoomTo(double to, Offset at) {
          final next = to.clamp(UiModeSession.minZoom, UiModeSession.maxZoom);
          final point = (at - origin) / zoom;
          final grown = Size(frame.width * next, frame.height * next);
          final middle = Offset(
            (area.width - grown.width) / 2,
            (area.height - grown.height) / 2,
          );
          session.pan.value = held(at - point * next - middle, grown);
          session.zoom.value = next;
        }

        return Listener(
          // Over the whole middle of the window, not only over the
          // screen: the wheel and the middle button work in the space
          // around it too.
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            // A turn of the wheel is a fraction of the size, so it feels
            // the same however far in or out it already is.
            zoomTo(
              zoom * math.exp(-event.scrollDelta.dy / 300),
              event.localPosition,
            );
          },
          onPointerDown: (event) {
            if (event.buttons & kMiddleMouseButton != 0) {
              _panning = event.pointer;
            }
          },
          onPointerMove: (event) {
            if (_panning != event.pointer) return;
            session.pan.value = held(session.pan.value + event.delta, size);
          },
          onPointerUp: (event) {
            if (_panning == event.pointer) _panning = null;
          },
          onPointerCancel: (event) {
            if (_panning == event.pointer) _panning = null;
          },
          child: ClipRect(
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    width: size.width,
                    height: size.height,
                    child: screen,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        session.device,
        session.landscape,
        session.showBoxes,
        session.zoom,
        session.pan,
      ],
      builder: (context, _) {
        final body = ColoredBox(
          // The world is still there, and still running; it is just not
          // what is being worked on.
          color: const Color(0xCC08070B),
          child: Column(
            children: [
              _Toolbar(
                session: session,
                onClose: widget.onClose,
                fullScreen: widget.fullScreen,
                onToggleFullScreen: widget.onToggleFullScreen,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The interface's own tree. The world's tree stops at
                    // a HUD; what is inside one is listed here.
                    if (widget.scope != null) ...[
                      SizedBox(
                        width: 264,
                        child: SceneTreePanel(
                          scope: widget.scope!,
                          entities: widget.scope!.entities,
                          contents: TreeContents.ui,
                          onCreateUi: widget.scope!.entities.createUi,
                        ),
                      ),
                      VerticalDivider(width: 1, color: EditorTheme.border),
                    ],
                    Expanded(child: _frameArea()),
                    // What the selected piece of interface is made of.
                    if (widget.scope != null) ...[
                      VerticalDivider(width: 1, color: EditorTheme.border),
                      SizedBox(
                        width: 312,
                        child: EntityInspectorPanel(
                          scope: widget.scope!,
                          sceneState: widget.sceneState,
                          world: session.world,
                          onDetachFromParent:
                              widget.scope!.entities.detachFromParent,
                          onGroupSelection: widget.scope!.entities.createGroup,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
        // Escape shuts the window and Ctrl with the zoom keys sizes the
        // screen — unless something inside, a name being typed, took the
        // key first.
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _onKey(event),
          child: body,
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
    // The left button moves a piece of interface; the middle one moves
    // the view, and the right one is nobody's business here.
    if (event.buttons & kPrimaryButton == 0) return;
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
  const _Toolbar({
    required this.session,
    this.onClose,
    this.fullScreen,
    this.onToggleFullScreen,
  });

  final UiModeSession session;
  final VoidCallback? onClose;
  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: EditorTheme.surfaceBg,
      child: Row(
        children: [
          Text(
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
                    Icon(
                      Icons.phone_iphone,
                      size: 13,
                      color: EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      device.toString(),
                      style: TextStyle(
                        color: EditorTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Icon(
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
          _ZoomControl(session: session),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: EditorTheme.border,
          ),
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
          // The window's own buttons, at the end of its title bar where a
          // window keeps them.
          if (onClose != null) ...[
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: EditorTheme.border,
            ),
            if (onToggleFullScreen != null)
              ValueListenableBuilder<bool>(
                valueListenable: fullScreen ?? const _Never(),
                builder: (context, filled, _) => _BarButton(
                  icon: filled ? Icons.close_fullscreen : Icons.open_in_full,
                  tooltip: filled ? 'Back to a window' : 'Fill the editor',
                  onPressed: onToggleFullScreen!,
                ),
              ),
            _BarButton(
              icon: Icons.close,
              tooltip: 'Close the interface editor (Esc)',
              onPressed: onClose!,
              danger: true,
            ),
          ],
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

/// A title-bar button: the window's own, not the interface's.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      hoverColor: danger
          ? EditorTheme.error.withValues(alpha: 0.18)
          : EditorTheme.primary.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Icon(icon, size: 14, color: EditorTheme.textSecondary),
      ),
    ),
  );
}

/// A listenable that never changes: the stand-in when a window has no say
/// over whether it is filled.
class _Never implements ValueListenable<bool> {
  const _Never();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// `−  Fit  +`: how large the screen is drawn.
class _ZoomControl extends StatelessWidget {
  const _ZoomControl({required this.session});

  final UiModeSession session;

  @override
  Widget build(BuildContext context) => SignalBuilder<double>(
    signal: session.zoom,
    builder: (context, zoom, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BarButton(
          icon: Icons.remove,
          tooltip: 'Smaller (Ctrl and −)',
          onPressed: () => session.zoomBy(-1),
        ),
        Builder(
          builder: (context) => Tooltip(
            message: 'How large the screen is drawn',
            child: InkWell(
              onTap: () async {
                final box = context.findRenderObject() as RenderBox?;
                final at = box == null
                    ? Offset.zero
                    : box.localToGlobal(box.size.bottomLeft(Offset.zero));
                final chosen = await showEditorMenu<double>(context, at, [
                  editorMenuItem(0, 'Fit'),
                  for (final stop in UiModeSession.zoomStops)
                    editorMenuItem(stop, '${(stop * 100).round()}%'),
                ]);
                if (chosen != null) session.zoom.value = chosen;
              },
              child: SizedBox(
                width: 46,
                child: Text(
                  session.isFitted ? 'Fit' : '${(zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ),
        _BarButton(
          icon: Icons.add,
          tooltip: 'Larger (Ctrl and +)',
          onPressed: () => session.zoomBy(1),
        ),
      ],
    ),
  );
}
