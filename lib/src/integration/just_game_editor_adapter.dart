import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../core/plugin/editor_plugin.dart';
import '../ui/overlay/editor_overlay.dart';

/// The game with the editor over it: the widget a game's editor entry point
/// shows in place of its [GameWidget].
///
/// It:
/// - registers [plugin] with [Engine.plugins], which ticks it once per
///   frame on wall-clock time — so the editor keeps working while the game
///   is paused or its time scale is zero — and takes it off again when the
///   widget goes away;
/// - draws the world before the editor: the engine calls the plugin's
///   `renderOverlay` from its overlay hook, after the world's render, which
///   this adds to [RenderingEngine.overlayHooks] if it is missing;
/// - puts the editor's windows over the game, and hands the keyboard
///   between the two as the editor opens and closes
///   ([JustGameEditorPlugin.toggleKey], F1 by default).
///
/// When [plugin] is null — a release build, or a platform the editor does
/// not run on ([JustGameEditorPlugin.supportsPlatform]) — it is a plain
/// [GameWidget] with nothing added.
class JustGameEngineEditor extends StatefulWidget {
  /// Shows [engine]'s game, with [plugin] over it when there is one. The
  /// rest is passed to the [GameWidget] underneath.
  const JustGameEngineEditor({
    super.key,
    required this.engine,
    required this.plugin,
    this.overlay,
    this.showFPS = false,
    this.showDebug = false,
    this.showTerminal = false,
  });

  /// The game's engine, the one [plugin] was made for.
  final Engine engine;

  /// The editor, from [JustGameEditorPlugin.register]; null shows the game
  /// alone.
  final JustGameEditorPlugin? plugin;

  /// The game's own widgets over its canvas: [GameWidget.overlay].
  final Widget? overlay;

  /// Whether the game shows its frame-rate counter: [GameWidget.showFPS].
  final bool showFPS;

  /// Whether the game shows the engine's debug overlay:
  /// [GameWidget.showDebug].
  final bool showDebug;

  /// Whether the game's developer terminal opens on the backquote key:
  /// [GameWidget.showTerminal].
  final bool showTerminal;

  @override
  State<JustGameEngineEditor> createState() => _JustGameEngineEditorState();
}

class _JustGameEngineEditorState extends State<JustGameEngineEditor> {
  // The editor draws as an engine plugin: the engine calls every plugin's
  // renderOverlay over the world (overlay hook order 100).

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _install(widget.engine, widget.plugin);
  }

  @override
  void didUpdateWidget(JustGameEngineEditor old) {
    super.didUpdateWidget(old);
    if (!kDebugMode) return;
    if (old.plugin != widget.plugin || old.engine != widget.engine) {
      // Off the engine it was on, which may not be the new one.
      _uninstall(old.engine, old.plugin);
      _install(widget.engine, widget.plugin);
    }
  }

  /// Registers [plugin] with [engine], which then draws it over the world.
  /// Keyed, so this is safe to call again for the same plugin. A plugin
  /// that fails to attach says so in the log rather than as an error
  /// nothing catches.
  void _install(Engine engine, JustGameEditorPlugin? plugin) {
    if (plugin == null) return;
    unawaited(
      engine.plugins.register(plugin).catchError((Object error, StackTrace s) {
        debugPrint('[JustGameEditor] could not attach the editor: $error');
        debugPrintStack(stackTrace: s);
      }),
    );
    // The world must draw before the editor. GameWidget adds it when its
    // painter is built, which can be after this; add it here too so the
    // order holds whichever comes first.
    engine.rendering.overlayHooks.addIfAbsent(engine.world.render);
  }

  /// Takes [plugin] off [engine]: the engine detaches it, and the editor
  /// lets go of the game until it is put back (`JustGameEditorPlugin.detach`).
  void _uninstall(Engine engine, JustGameEditorPlugin? plugin) {
    if (plugin != null && engine.plugins.byId(plugin.id) == plugin) {
      engine.plugins.unregister(plugin.id);
    }
  }

  @override
  void dispose() {
    _uninstall(widget.engine, widget.plugin);
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
