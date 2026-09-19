import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../core/plugin/editor_plugin.dart';
import '../ui/overlay/editor_overlay.dart';

/// Layers the runtime editor over a [GameWidget] without manual overlay
/// composition.
///
/// Handles:
/// - Registering the [JustGameEditorPlugin] with [Engine.plugins], which
///   ticks it once per frame on wall-clock time — so it keeps working while
///   the game is paused or its time scale is zero.
/// - Adding [JustGameEditorPlugin.onRender] to [RenderingEngine.overlayHooks]
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

class _JustGameEngineEditorState extends State<JustGameEngineEditor> {
  // Drawn through the rendering engine's overlay hook chain, after the world
  // (which GameWidget adds itself). A chain, so nothing else that renders an
  // overlay is displaced.
  void _gizmoHook(Canvas canvas, Size size) {
    final plugin = widget.plugin;
    if (plugin != null && plugin.isVisible.value) plugin.onRender(canvas, size);
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _install(widget.plugin);
  }

  @override
  void didUpdateWidget(JustGameEngineEditor old) {
    super.didUpdateWidget(old);
    if (!kDebugMode) return;
    if (old.plugin != widget.plugin) {
      _uninstall(old.plugin);
      _install(widget.plugin);
    }
  }

  /// Registers [plugin] with the engine and adds the gizmo hook. Both are
  /// keyed, so this is safe to call again for the same plugin.
  void _install(JustGameEditorPlugin? plugin) {
    if (plugin == null) return;
    widget.engine.plugins.register(plugin);
    final hooks = widget.engine.rendering.overlayHooks;
    // The world must draw before the gizmos. GameWidget adds it when its
    // painter is built, which can be after this; add it here too so the
    // order holds whichever comes first.
    hooks
      ..addIfAbsent(widget.engine.world.render)
      ..addIfAbsent(_gizmoHook, order: 100);
  }

  void _uninstall(JustGameEditorPlugin? plugin) {
    widget.engine.rendering.overlayHooks.remove(_gizmoHook);
    if (plugin != null && widget.engine.plugins.byId(plugin.id) == plugin) {
      widget.engine.plugins.unregister(plugin.id);
    }
  }

  @override
  void dispose() {
    _uninstall(widget.plugin);
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

    return JustGameEditorOverlay(plugin: widget.plugin!, gameChild: gameWidget);
  }
}
