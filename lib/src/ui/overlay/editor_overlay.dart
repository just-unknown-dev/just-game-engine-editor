import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../core/plugin/editor_plugin.dart';
import '../../core/entity/entity_ops.dart';
import 'chrome/editor_chrome.dart';
import 'viewport_menu.dart';
import 'start/scene_loading_view.dart';
import 'start/start_card.dart';
import '../../core/scope/editor_scope_services.dart';

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
          gizmos: widget.settings.gizmos,
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
/// The docks, panels, floating controls and messages — the "chrome" — are
/// projected into the ambient [Overlay] via [OverlayPortal] rather than
/// painted inline. Apps typically
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
  State<JustGameEditorOverlay> createState() => _JustGameEditorOverlayState();
}

class _JustGameEditorOverlayState extends State<JustGameEditorOverlay> {
  final OverlayPortalController _chromeController = OverlayPortalController();
  final List<void Function()> _stop = [];

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    _chromeController.show();
    final scope = widget.plugin.scope;
    _stop
      ..add(scope.prefs.settings.watch(_syncTheme))
      ..add(scope.theme.current.watch(() => _applyTheme()));
    // The questions only the editor's window can ask.
    widget.plugin
      ..askToRecover = _askToRecover
      ..askToLeaveScene = _askToLeaveScene;
    _entities = scope.entities..confirmDelete = _confirmDelete;
    scope.prefs.load().then((_) {
      if (!mounted) return;
      scope.chrome.rightPanelWidth.value = scope.prefs
          .get(EditorChromeState.rightPanelWidthPref)
          .clamp(
            OverlayLayout.rightPanelMinWidth,
            OverlayLayout.rightPanelMaxWidth,
          );
      // Where the last session left off, as the settings ask.
      unawaited(widget.plugin.reopenLastSession());
    });
    _syncTheme();
    _applyTheme();
  }

  /// A hot reload. The one place the editor hears of it: everything it
  /// built from code once — registries, definitions, docks, the palette —
  /// is built again from the code as it now is, before the frame that
  /// shows it.
  @override
  void reassemble() {
    super.reassemble();
    if (!kDebugMode) return;
    widget.plugin.reassemble();
    // The palette, as the code now makes it: a picked preset was made again
    // by the plugin; an accent of the settings' own is made again here.
    final scope = widget.plugin.scope;
    if (scope.theme.currentId.value == null) {
      scope.theme.set(
        EditorThemeData.classic.withAccent(scope.prefs.settings.value.accent),
      );
    }
    _themeSource = null;
    _syncTheme();
  }

  EntityOps? _entities;

  Future<bool?> _askToRecover(String sceneName, DateTime when) {
    if (!mounted) return Future.value();
    String two(int v) => v.toString().padLeft(2, '0');
    final at = '${two(when.hour)}:${two(when.minute)}';
    return askToRecover(
      context,
      title: 'Recover unsaved changes to $sceneName?',
      message:
          'A backup from $at holds changes to $sceneName that were never '
          'saved. Recover them, or open the scene as it was last saved; '
          'the backup stays in .editor_backups either way.',
    );
  }

  Future<UnsavedChoice?> _askToLeaveScene(String leaving, String opening) {
    if (!mounted) return Future.value();
    return askToSaveChanges(
      context,
      title: 'Save changes to $leaving?',
      message:
          'Opening $opening closes $leaving, and loses what has not been '
          'saved.',
    );
  }

  Future<bool> _confirmDelete(String what) {
    if (!mounted) return Future.value(false);
    return showEditorConfirm(
      context,
      title: 'Delete $what?',
      message: 'Undo brings it back.',
      confirmLabel: 'Delete',
    );
  }

  @override
  void dispose() {
    if (widget.plugin.askToRecover == _askToRecover) {
      widget.plugin.askToRecover = null;
    }
    if (widget.plugin.askToLeaveScene == _askToLeaveScene) {
      widget.plugin.askToLeaveScene = null;
    }
    // Held from the start: the scope may already be closed by now.
    final entities = _entities;
    if (entities != null && entities.confirmDelete == _confirmDelete) {
      entities.confirmDelete = null;
    }
    for (final stop in _stop) {
      stop();
    }
    // The focus outlines were the editor's setting: give the app back its
    // own way of showing them.
    if (_focusStrategySet) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    }
    super.dispose();
  }

  bool _focusStrategySet = false;

  /// Always-visible focus, for everything under the editor: Flutter's own
  /// highlights too, not only the kit's outlines.
  void _syncFocusStrategy(bool always) {
    if (always == _focusStrategySet) return;
    _focusStrategySet = always;
    FocusManager.instance.highlightStrategy = always
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;
  }

  /// The settings name a theme — a built-in accent or a module's preset —
  /// and the sizes the chrome is drawn at.
  void _syncTheme() {
    final scope = widget.plugin.scope;
    final settings = scope.prefs.settings.value;
    if (scope.theme.preset(settings.themeId) != null) {
      scope.theme.select(settings.themeId);
    } else if (scope.theme.currentId.value != null ||
        scope.theme.current.value.primary != settings.accent) {
      // A preset that has gone — its module removed: the accent it had.
      scope.theme.set(EditorThemeData.classic.withAccent(settings.accent));
    }
    _syncFocusStrategy(settings.alwaysShowFocus);
    final sized = EditorMetrics.apply(settings);
    // High contrast and colour-blind safe colours are the palette's to show,
    // over whichever theme is picked.
    if (!_applyTheme() && sized) _rebuildAll();
  }

  EditorThemeData? _themeSource;
  (bool, bool)? _themeFlags;

  /// Applies the picked theme, as the accessibility settings adjust it.
  /// True when it changed — and everything was built again.
  bool _applyTheme() {
    final scope = widget.plugin.scope;
    final source = scope.theme.current.value;
    final settings = scope.prefs.settings.value;
    final flags = (settings.highContrast, settings.colourBlindSafe);
    if (identical(source, _themeSource) && flags == _themeFlags) return false;
    _themeSource = source;
    _themeFlags = flags;
    var data = source;
    if (settings.highContrast) data = data.highContrast();
    if (settings.colourBlindSafe) data = data.colourBlindSafe();
    // From the picked theme: `EditorTheme.of(context)` then hands out the
    // adjusted palette too, not the preset beneath it.
    EditorTheme.apply(data, from: source);
    _rebuildAll();
    return true;
  }

  /// Every colour and size is read as the chrome builds, so a new theme or
  /// density means building all of it again. Its state — scroll positions,
  /// open menus, typed text — stays. The game's own widgets are left alone:
  /// they read none of the editor's look.
  void _rebuildAll() {
    if (!mounted) return;
    final game = widget.gameChild;
    void mark(Element element) {
      if (identical(element.widget, game)) return;
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  /// Whether the editor steps aside for the game: a play-test running —
  /// not paused, which brings it back — with the settings asking for that.
  bool _steppedAside(OverlayUiSettings settings) =>
      settings.hideChromeWhilePlaying &&
      widget.plugin.playController.state.value == EditorPlayState.playing;

  /// The chrome's ambient look — its text at the size and weight the
  /// settings ask for, the game's left alone; motion as they allow; one style
  /// of tooltip — rebuilt when they change.
  Widget _chromeLook(Widget child) => SignalBuilder<OverlayUiSettings>(
    signal: widget.plugin.scope.prefs.settings,
    builder: (context, _, _) => EditorLook(child: child),
  );

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
                  return _chromeLook(
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        SignalBuilder2<bool, bool>(
                          signal1: plugin.isVisible,
                          signal2: plugin.isStatusPanelVisible,
                          builder: (context, _, _, _) {
                            if (!plugin.isVisible.value) {
                              if (!plugin.isStatusPanelVisible.value) {
                                return const SizedBox.shrink();
                              }
                              return CompactChrome(plugin: plugin);
                            }

                            return SignalBuilder2<
                              OverlayUiSettings,
                              EditorPlayState
                            >(
                              signal1: widget.plugin.scope.prefs.settings,
                              signal2: plugin.playController.state,
                              builder: (context, settings, _, _) =>
                                  _steppedAside(settings)
                                  ? PlayTestChrome(
                                      plugin: plugin,
                                      settings: settings,
                                    )
                                  : FullEditorChrome(
                                      plugin: plugin,
                                      settings: settings,
                                    ),
                            );
                          },
                        ),
                        // Over everything while a scene opens.
                        SceneLoadingBarrier(plugin: plugin),
                      ],
                    ),
                  );
                },
                child: SignalBuilder2<bool, bool>(
                  signal1: plugin.isVisible,
                  signal2: plugin.isStatusPanelVisible,
                  builder: (context, _, _, _) {
                    if (!plugin.isVisible.value) {
                      return AbsorbPointer(absorbing: false, child: gameChild);
                    }

                    return SignalBuilder2<OverlayUiSettings, EditorPlayState>(
                      signal1: widget.plugin.scope.prefs.settings,
                      signal2: plugin.playController.state,
                      builder: (context, settings, _, _) {
                        return OverlayUiSettingsWatcher(
                          plugin: plugin,
                          settings: settings,
                          child: _steppedAside(settings)
                              ? gameChild
                              : _GameInWhatIsLeft(
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
  void _openMenu(BuildContext context, PointerDownEvent event) =>
      _openMenuAt(context, event.localPosition, event.position);

  void _openMenuAt(BuildContext context, Offset local, Offset global) {
    final plugin = widget.plugin;
    if (plugin.playController.isRunning || !plugin.isVisible.value) return;
    showViewportMenu(
      context,
      plugin,
      // In a split viewport, what the pane under the pointer sees there.
      entity: plugin.atPoint(local, plugin.viewport.entityAt),
      globalPosition: global,
      worldPoint: plugin.atPoint(local, plugin.viewport.worldPointAt),
      surface: plugin.scope.editorView.isPlanar
          ? null
          : plugin.atPoint(local, plugin.surfaceAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleCanvasSizeUpdate(size);

        // In 3-D a right-press looks around; one that never moved opens
        // the menu when it lets go.
        widget.plugin.viewport.openMenu = (local, global) {
          if (mounted) _openMenuAt(context, local, global);
        };
        final canvas = MouseRegion(
          onExit: (_) => widget.plugin.viewport.onPointerExit(),
          child: Listener(
            onPointerDown: (event) {
              // A press on the game view mid-play means "back to the game".
              if (widget.plugin.playController.isRunning) {
                widget.plugin.focusGame();
                widget.plugin.pressedPlayingGame(event);
              }
              final claimed = widget.plugin.pointerDown(event);
              // A right-press is the context menu's unless a tool took it —
              // a tile brush picking tiles up.
              if ((event.buttons & kSecondaryButton) != 0 && !claimed) {
                _openMenu(context, event);
              }
            },
            onPointerHover: widget.plugin.pointerHover,
            onPointerMove: widget.plugin.pointerMove,
            onPointerUp: widget.plugin.pointerUp,
            onPointerCancel: widget.plugin.pointerCancel,
            onPointerSignal: widget.plugin.pointerScroll,
            // An asset dragged out of the Assets dock lands here: an image
            // becomes a sprite where it was dropped.
            child: DragTarget<String>(
              onWillAcceptWithDetails: (d) =>
                  widget.plugin.sceneState.hasScene &&
                  JustGameEditorPlugin.canDropAsset(
                    d.data,
                    mode: widget.plugin.sceneState.editingMode,
                    scope: widget.plugin.scope,
                  ),
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
                child: AbsorbPointer(
                  absorbing: true,
                  // What the colour picker's eyedropper reads pixels from.
                  child: RepaintBoundary(
                    key: widget.plugin.scope.viewportCaptureKey,
                    child: widget.gameChild,
                  ),
                ),
              ),
            ),
          ),
        );
        // With no scene open there is no level to show: the start card
        // covers the game as it booted, and takes the presses. While one
        // opens, the backdrop covers the level being built.
        final plugin = widget.plugin;
        return SignalConsumer(
          signals: [plugin.sceneState.activeScene],
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              canvas,
              if (!plugin.sceneState.hasScene) EditorStartCover(plugin: plugin),
              // Keyed: the start card goes from under it as the scene
              // opens, and its fade must carry on.
              SceneLoadingCover(
                key: const ValueKey('sceneLoadingCover'),
                plugin: plugin,
              ),
            ],
          ),
        );
      },
    );
  }
}
