part of 'just_game_editor_plugin.dart';

/// The pointer in the viewport: each event to the pane under it, as that
/// pane's view sees it.
extension PluginPanes on JustGameEditorPlugin {
  /// Runs [handle] with [event] in the pane it belongs to: the one it went
  /// down in, while a gesture lasts, else the one under it. Without a
  /// split, as it is.
  T _routed<T>(
    PointerEvent event,
    T Function(PointerEvent) handle,
    T outside, {
    bool begins = false,
  }) {
    final split = activeSplit;
    if (split == null) return handle(event);
    final pane = begins || split.active == null
        ? split.paneAt(event.localPosition)
        : split.active;
    if (pane == null) return outside;
    split.active = pane;
    return _inPane(pane, event, handle);
  }

  /// A press on the canvas, sent on to the viewport through its pane.
  @internal
  bool pointerDown(PointerDownEvent event) => _routed(
    event,
    (e) => viewport.onPointerDown(e as PointerDownEvent),
    false,
    begins: true,
  );

  /// The pointer moving with no button down.
  @internal
  void pointerHover(PointerHoverEvent event) => _routed(
    event,
    (e) => viewport.onPointerHover(e as PointerHoverEvent),
    null,
    begins: true,
  );

  /// The pointer moving with a button down.
  @internal
  void pointerMove(PointerMoveEvent event) => _routed(
    event,
    (e) => viewport.onPointerMove(e as PointerMoveEvent),
    null,
  );

  /// A press let go.
  @internal
  void pointerUp(PointerUpEvent event) =>
      _routed(event, (e) => viewport.onPointerUp(e as PointerUpEvent), null);

  /// A gesture cut short.
  @internal
  void pointerCancel(PointerCancelEvent event) => _routed(
    event,
    (e) => viewport.onPointerCancel(e as PointerCancelEvent),
    null,
  );

  /// The wheel.
  @internal
  void pointerScroll(PointerSignalEvent event) => _routed(
    event,
    (e) => viewport.onPointerScroll(e as PointerSignalEvent),
    null,
    begins: true,
  );

  /// Runs [body] with [local] (canvas pixels) as the pane under it sees
  /// it, that pane's view the editor's: what the right-click menu asks.
  @internal
  T atPoint<T>(Offset local, T Function(Offset local) body) {
    final split = activeSplit;
    // Already in a pane: a menu opened from a gesture there.
    if (split == null || _inPaneDepth > 0) return body(local);
    final pane = split.paneAt(local) ?? split.panes.last;
    final canvas = viewport.canvasSize;
    viewport.updateCanvasSize(pane.rect.size);
    try {
      return scope.throughPane(pane, () => body(local - pane.rect.topLeft));
    } finally {
      viewport.updateCanvasSize(canvas);
    }
  }
}
