import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/plugin/editor_plugin.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/theme/theme_controller.dart';
import 'chrome/editor_chrome.dart';
import 'settings/overlay_ui_settings.dart';
import 'viewport_menu.dart';
import 'shared/snackbar.dart';

// ─ Frame-safe overlay settings watcher ────────────────────────────────────

/// Wrapper that applies overlay settings on the next frame, avoiding
/// FlutterError 'Build scheduled during frame'.
///
/// This defers [plugin.applyOverlaySettings] to post-frame via SchedulerBinding,
/// ensuring it runs outside of build/layout/paint phases.
class OverlayUiSettingsWatcher extends StatefulWidget {
  const OverlayUiSettingsWatcher({
    super.key,
    required this.plugin,
    required this.settings,
    required this.child,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;
  final Widget child;

  @override
  State<OverlayUiSettingsWatcher> createState() =>
      _OverlayUiSettingsWatcherState();
}

class _OverlayUiSettingsWatcherState extends State<OverlayUiSettingsWatcher> {
  @override
  void didUpdateWidget(OverlayUiSettingsWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _scheduleSettingsApplication();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleSettingsApplication();
  }

  void _scheduleSettingsApplication() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.plugin.applyOverlaySettings(
          showGrid: widget.settings.showGrid,
          gridSnappingEnabled: widget.settings.gridSnappingEnabled,
          gridSize: widget.settings.gridSize,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Public overlay host ───────────────────────────────────────────────────────

/// Wraps the game surface with the runtime editor UI.
///
/// When [plugin.isVisible.value] is false the widget keeps the game interactive.
/// If [plugin.isStatusPanelVisible.value] is true, the compact dock can still be
/// shown independently. When visible it switches to a split layout: game
/// canvas on the left, editor panel on the right.
///
/// The dock/panel/badge/snackbar "chrome" is projected into the ambient
/// [Overlay] via [OverlayPortal] rather than painted inline. Apps typically
/// stack pause/game-over dialogs above this widget (see just_zombies'
/// GameScreen); painting chrome inline would put it underneath those
/// dialogs. Routing it through the Overlay makes the editor — a developer
/// tool, not game UI — always render on top, regardless of sibling order
/// elsewhere in the app. Only the game canvas itself stays in its normal
/// tree position, since gameplay must still render beneath the app's own
/// HUD/dialogs as before.
class JustGameEditorOverlay extends StatefulWidget {
  const JustGameEditorOverlay({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<JustGameEditorOverlay> createState() => JustGameEditorOverlayState();
}

class JustGameEditorOverlayState extends State<JustGameEditorOverlay> {
  final OverlayPortalController _chromeController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _chromeController.show();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.gameChild;

    final plugin = widget.plugin;
    final gameChild = widget.gameChild;

    // Everything under here can reach the scope, portal children included.
    return EditorScopeProvider(
      scope: plugin.scope,
      child: EditorThemeScope(
        controller: plugin.scope.theme,
        child: EditorMessenger(
          child: FocusScope(
            node: plugin.gameFocusScopeNode,
            child: Focus(
              // Not autofocus: this wrapper has no onKeyEvent of its own, and
              // claiming focus here at mount races (and wins over) gameChild's
              // own internal autofocus Focus node — silently swallowing all
              // keyboard input into a no-op handler with no way to recover it
              // short of clicking directly on the game canvas. Editor <-> game
              // focus routing on F1 is already handled explicitly via
              // editorFocusNode/gameFocusScopeNode.requestFocus() in
              // JustGameEditorPlugin._onHardwareKey, so this wrapper doesn't
              // need to grab focus itself — leave it to gameChild by default.
              canRequestFocus: true,
              child: OverlayPortal(
                controller: _chromeController,
                overlayChildBuilder: (context) {
                  return SignalBuilder2<bool, bool>(
                    signal1: plugin.isVisible,
                    signal2: plugin.isStatusPanelVisible,
                    builder: (context, _, _, _) {
                      if (!plugin.isVisible.value) {
                        if (!plugin.isStatusPanelVisible.value) {
                          return const SizedBox.shrink();
                        }
                        return CompactChrome(plugin: plugin);
                      }

                      return SignalBuilder<OverlayUiSettings>(
                        signal: widget.plugin.scope.prefs.settings,
                        builder: (context, settings, _) => FullEditorChrome(
                          plugin: plugin,
                          settings: settings,
                        ),
                      );
                    },
                  );
                },
                child: SignalBuilder2<bool, bool>(
                  signal1: plugin.isVisible,
                  signal2: plugin.isStatusPanelVisible,
                  builder: (context, _, _, _) {
                    if (!plugin.isVisible.value) {
                      return AbsorbPointer(absorbing: false, child: gameChild);
                    }

                    return SignalBuilder<OverlayUiSettings>(
                      signal: widget.plugin.scope.prefs.settings,
                      builder: (context, settings, _) {
                        return OverlayUiSettingsWatcher(
                          plugin: plugin,
                          settings: settings,
                          child: _GameInWhatIsLeft(
                            plugin: plugin,
                            gameChild: gameChild,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The game, laid out inside whatever the editor's chrome leaves.
///
/// The canvas is genuinely smaller, so the camera's viewport, the pointer's
/// coordinates and everything painted on the canvas follow by themselves —
/// nothing has to be told where the panels are.
class _GameInWhatIsLeft extends StatefulWidget {
  const _GameInWhatIsLeft({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<_GameInWhatIsLeft> createState() => _GameInWhatIsLeftState();
}

class _GameInWhatIsLeftState extends State<_GameInWhatIsLeft> {
  final List<void Function()> _stop = [];

  @override
  void initState() {
    super.initState();
    void rebuild() {
      if (mounted) setState(() {});
    }

    final plugin = widget.plugin;
    final dock = plugin.scope.dockController;
    for (final signal in <Signal<Object?>>[
      plugin.scope.chrome.rightPanelWidth,
      plugin.isStatusPanelVisible,
      plugin.designer,
      dock.openId,
      dock.heights,
      dock.maximised,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: editorGameInsets(
        window: constraints.biggest,
        plugin: widget.plugin,
        designing: widget.plugin.designer.value != null,
        rightPanelWidth: widget.plugin.scope.chrome.rightPanelWidth.value,
      ),
      child: GameCanvasArea(plugin: widget.plugin, gameChild: widget.gameChild),
    ),
  );
}

// ── Canvas ─────────────────────────────────────────────────────────────────

class GameCanvasArea extends StatefulWidget {
  const GameCanvasArea({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<GameCanvasArea> createState() => _GameCanvasAreaState();
}

class _GameCanvasAreaState extends State<GameCanvasArea> {
  Size? _lastCanvasSize;

  void _scheduleCanvasSizeUpdate(Size size) {
    if (_lastCanvasSize == size) return;
    _lastCanvasSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.plugin.viewport.updateCanvasSize(size);
    });
  }

  /// The right-click menu, on whatever the pointer is over.
  void _openMenu(BuildContext context, PointerDownEvent event) {
    final plugin = widget.plugin;
    if (plugin.playController.isRunning || !plugin.isVisible.value) return;
    showViewportMenu(
      context,
      plugin,
      entity: plugin.viewport.entityAt(event.localPosition),
      globalPosition: event.position,
      worldPoint: plugin.viewport.worldPointAt(event.localPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleCanvasSizeUpdate(size);

        return MouseRegion(
          onExit: (_) => widget.plugin.viewport.onPointerExit(),
          child: Listener(
            onPointerDown: (event) {
              // A press on the game view mid-play means "back to the game".
              if (widget.plugin.playController.isRunning) {
                widget.plugin.focusGame();
              }
              final claimed = widget.plugin.viewport.onPointerDown(event);
              // A right-press is the context menu's unless a tool took it —
              // a tile brush picking tiles up.
              if ((event.buttons & kSecondaryButton) != 0 && !claimed) {
                _openMenu(context, event);
              }
            },
            onPointerHover: widget.plugin.viewport.onPointerHover,
            onPointerMove: widget.plugin.viewport.onPointerMove,
            onPointerUp: widget.plugin.viewport.onPointerUp,
            onPointerCancel: widget.plugin.viewport.onPointerCancel,
            onPointerSignal: widget.plugin.viewport.onPointerScroll,
            // An asset dragged out of the Assets dock lands here: an image
            // becomes a sprite where it was dropped.
            child: DragTarget<String>(
              onWillAcceptWithDetails: (d) =>
                  widget.plugin.sceneState.hasScene &&
                  JustGameEditorPlugin.canDropAsset(d.data),
              onAcceptWithDetails: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                widget.plugin.dropAsset(d.data, box.globalToLocal(d.offset));
              },
              builder: (context, incoming, _) => DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: incoming.isEmpty
                      ? null
                      : Border.all(
                          color: EditorTheme.primaryBright.withValues(
                            alpha: 0.7,
                          ),
                          width: 2,
                        ),
                ),
                child: AbsorbPointer(absorbing: true, child: widget.gameChild),
              ),
            ),
          ),
        );
      },
    );
  }
}
