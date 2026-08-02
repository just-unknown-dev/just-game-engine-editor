import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../core/plugin/editor_plugin.dart';
import '../ui/overlay/editor_overlay.dart';

/// Convenience wrapper that layers the runtime editor over a [GameWidget]
/// without requiring manual overlay composition.
///
/// Handles:
/// - Debug-gated plugin creation and lifecycle.
/// - A shared [Ticker] that drives [JustGameEditorPlugin.onUpdate] at vsync
///   rate while the editor is visible.
/// - Chaining [JustGameEditorPlugin.onRender] into [RenderingEngine.onRenderOverlay]
///   so gizmos draw on top of all ECS entities in world space.
/// - [JustGameEditorOverlay] focus-scope integration.
///
/// When [plugin] is null (release builds) the widget degrades to a plain
/// [GameWidget] with zero overhead.
class JustGameEngineEditor extends StatefulWidget {
  const JustGameEngineEditor({
    super.key,
    required this.engine,
    required this.plugin,
    this.overlay,
    this.showFPS = true,
    this.showDebug = false,
    this.showTerminal = false,
  });

  final Engine engine;
  final JustGameEditorPlugin? plugin;
  final Widget? overlay;
  final bool showFPS;
  final bool showDebug;
  final bool showTerminal;

  @override
  State<JustGameEngineEditor> createState() => _JustGameEngineEditorState();
}

class _JustGameEngineEditorState extends State<JustGameEngineEditor>
    with SingleTickerProviderStateMixin {
  late final Ticker _editorTicker;
  Duration _prevElapsed = Duration.zero;

  // We own onRenderOverlay completely. Our hook calls world.render() directly
  // (not via a captured previous hook) because our initState() runs before
  // GameWidget builds its _GamePainter — which means the ??= guard in
  // _GamePainter would see our hook already installed and never set
  // world.render. Capturing _previousOverlayHook here always yields null.
  void Function(Canvas canvas, Size size)? _installedOverlayHook;

  @override
  void initState() {
    super.initState();

    // Always read widget.plugin *inside* the callback (not a value captured
    // at creation time): a Ticker's callback closure can't be swapped after
    // createTicker(), so if this were built once from whatever widget.plugin
    // is right now, a plugin assigned later (e.g. via an async
    // `await JustGameEditorPlugin.register(...)` that starts as null) would
    // never actually get its onUpdate called for the rest of the session.
    _editorTicker = createTicker((elapsed) {
      final plugin = widget.plugin;
      if (!kDebugMode || plugin == null) return;
      final elapsedSeconds = elapsed.inMicroseconds / 1e6;
      final prevSeconds = _prevElapsed.inMicroseconds / 1e6;
      // Ticker.start() resets `elapsed` back to zero on every restart (e.g.
      // toggling editor visibility stops/starts this ticker), so guard
      // against a stale, larger _prevElapsed producing a negative dt.
      final dt = elapsedSeconds >= prevSeconds
          ? elapsedSeconds - prevSeconds
          : 0.0;
      _prevElapsed = elapsed;
      plugin.onUpdate(dt);
    });

    if (kDebugMode && widget.plugin != null) {
      _installGizmoHook();
    }
  }

  @override
  void didUpdateWidget(JustGameEngineEditor old) {
    super.didUpdateWidget(old);
    if (!kDebugMode) return;

    if (old.plugin != widget.plugin) {
      _removeGizmoHook();
      _installGizmoHook();
    }

    if (widget.plugin != null && widget.plugin!.isVisible) {
      if (!_editorTicker.isActive) _editorTicker.start();
    } else {
      if (_editorTicker.isActive) _editorTicker.stop();
    }
  }

  void _installGizmoHook() {
    final plugin = widget.plugin;
    if (plugin == null) return;

    void hook(Canvas canvas, Size size) {
      // Call world.render directly — capturing onRenderOverlay at initState()
      // time always yields null because _GamePainter (which sets it via ??=)
      // hasn't been constructed yet when initState() runs.
      widget.engine.world.render(canvas, size);
      if (plugin.isVisible) plugin.onRender(canvas, size);
    }

    _installedOverlayHook = hook;
    widget.engine.rendering.onRenderOverlay = hook;
  }

  void _removeGizmoHook() {
    if (widget.engine.rendering.onRenderOverlay == _installedOverlayHook) {
      // Restore to world.render so entities keep drawing if the adapter
      // is rebuilt without a plugin.
      widget.engine.rendering.onRenderOverlay = widget.engine.world.render;
    }
    _installedOverlayHook = null;
  }

  @override
  void dispose() {
    _editorTicker.dispose();
    _removeGizmoHook();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameWidget = GameWidget(
      engine: widget.engine,
      overlay: widget.overlay,
      showFPS: widget.showFPS,
      showDebug: widget.showDebug,
      showTerminal: widget.showTerminal,
    );

    if (!kDebugMode || widget.plugin == null) return gameWidget;

    return _PluginVisibilityListener(
      plugin: widget.plugin!,
      ticker: _editorTicker,
      child: JustGameEditorOverlay(
        plugin: widget.plugin!,
        gameChild: gameWidget,
      ),
    );
  }
}

/// Starts / stops the update ticker in sync with overlay visibility.
class _PluginVisibilityListener extends StatefulWidget {
  const _PluginVisibilityListener({
    required this.plugin,
    required this.ticker,
    required this.child,
  });

  final JustGameEditorPlugin plugin;
  final Ticker ticker;
  final Widget child;

  @override
  State<_PluginVisibilityListener> createState() =>
      _PluginVisibilityListenerState();
}

class _PluginVisibilityListenerState extends State<_PluginVisibilityListener> {
  @override
  void initState() {
    super.initState();
    widget.plugin.addListener(_onPluginChanged);
    _syncTicker();
  }

  @override
  void dispose() {
    widget.plugin.removeListener(_onPluginChanged);
    super.dispose();
  }

  void _onPluginChanged() => _syncTicker();

  void _syncTicker() {
    if (widget.plugin.isVisible) {
      if (!widget.ticker.isActive) widget.ticker.start();
    } else {
      if (widget.ticker.isActive) widget.ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
