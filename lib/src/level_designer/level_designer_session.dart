import '../timeline/motion_path.dart';
import '../timeline/timeline_session.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'level_designer_2d/overlays/built_in_overlays.dart';
import 'level_designer_2d/overlays/measurement_overlay.dart';
import 'level_designer_2d/overlays/minimap_overlay.dart';
import 'level_designer_2d/overlays/tile_overlays.dart';
import 'level_designer_2d/overlays/transform_overlays.dart';
import 'level_designer_painter.dart';
import 'state/built_in_prefabs.dart';
import 'state/selection_ops.dart';
import 'level_designer_2d/tools/draw_rect_tool.dart';
import 'level_designer_2d/tools/eyedropper_tool.dart';
import 'level_designer_2d/tools/measure_2d_tool.dart';
import 'level_designer_2d/tools/paint_tool.dart';
import 'level_designer_2d/tools/select_2d_tool.dart';
import 'level_designer_2d/tools/tiles/tile_brush_tools.dart';
import 'level_designer_2d/tools/tiles/tile_select_tool.dart';
import 'level_designer_2d/tools/tiles/tile_terrain_tool.dart';
import 'level_designer_2d/tools/tiles/tile_tool_base.dart' show TileTools;
import '../camera/camera_rig_painter.dart';
import 'level_designer_3d/overlays/marquee_3d_overlay.dart';
import 'level_designer_3d/overlays/place_ghost_3d_overlay.dart';
import 'level_designer_3d/aids/ruler_3d.dart';
import 'level_designer_3d/tools/material_paint_3d_tool.dart';
import 'level_designer_3d/tools/place_3d_tool.dart';
import '../viewport/split_views.dart';
import 'package:just_game_engine/just_game_engine_3d.dart' as g3;
import 'level_designer_3d/tools/select_3d_tool.dart';
import '../entities/scope_entities.dart';
import 'level_designer_3d/built_in_designer_3d_contributions.dart';
import '../level_map/scope_level_maps.dart';
import '../prefabs/prefab_placement.dart';

part 'level_designer_session_pointer.dart';
part 'level_designer_session_chrome.dart';

/// Owns the Level Designer's runtime: state, tools, history and painting.
///
/// While the designer is open, the plugin hands its pointer events and
/// canvas painting here; with it closed, the editor works without one. A
/// module's tests drive a session over a scope made with
/// `builtIns: const [BuiltInEditorModule.new]`, the way the designer runs
/// the module's tools, overlays and commands.
class LevelDesignerSession implements DesignerSession {
  /// A session over [scope]. [uniqueName] names what its tools make — the
  /// scope's own entity namer when null, as a module's tests can leave it.
  LevelDesignerSession({
    required this.scope,
    String Function(String prefix)? uniqueName,
    required this.onDuplicate,
    required this.onDelete,
    required this.onArray,
    this.onArray3D,
    ModifierKeys Function()? readModifiers,
    EditorView Function()? camera,
    this.splitViews,
    bool Function(GizmoKind kind)? showsGizmo,
  }) : history = scope.history,
       _uniqueName = uniqueName ?? scope.entities.uniqueName.call,
       _readModifiers = readModifiers ?? ModifierKeys.fromHardwareKeyboard,
       _camera = camera,
       _showsGizmo = showsGizmo {
    controller = LevelDesignerController(
      sceneState: sceneState,
      history: history,
      view: scope.view,
      tools: tools,
      prefabs: scope.prefabs,
      sessionPrefabs: sessionPrefabs,
    )..mapLayerOf = (entity) => jge.LevelMaps.memberLayer(world, entity);

    // Descriptors, prefabs and layers are the scope's: registered once,
    // rebuilt on reload. Tools and overlays are per session, because a tool
    // edits *this* session's selection and pushes onto *this* history.
    reloadModules();
    // A designer switch swaps the tools and overlays under this session.
    _stopWatchingDesigner = scope.activeDesigner.watch(reloadModules);
  }

  late final VoidCallback _stopWatchingDesigner;

  /// Whether gizmos of a kind are drawn now, in the editor's mode (the
  /// plugin's `showsGizmo`); always, when the session was made without it.
  final bool Function(GizmoKind kind)? _showsGizmo;

  /// The editor this session belongs to: its prefabs, layers, codec, log.
  @override
  final EditorScope scope;

  /// The world being edited.
  @override
  jge.World get world => scope.world;

  /// Selection and grid state shared with the rest of the editor.
  @override
  EditorSceneState get sceneState => scope.sceneState;

  /// This session's viewport tools: the built-ins, then each module's —
  /// those that belong in the scene's mode.
  late final ToolRegistry tools = ToolRegistry()
    ..modeOf = () => scope.sceneState.editingMode;

  /// This session's overlays, in paint order — those that belong in the
  /// scene's mode.
  late final OverlayRegistry overlays = OverlayRegistry()
    ..modeOf = () => scope.sceneState.editingMode;

  /// Prefabs that exist only for this session: the eyedropper's samples.
  @internal
  final PrefabRegistry sessionPrefabs = PrefabRegistry();

  /// Whoever snaps for this session: the built-ins and the modules'
  /// providers, by priority.
  @internal
  SnapResolver get snapper => _snapper;
  SnapResolver _snapper = SnapResolver(const [
    EntitySnapProvider(),
    GridSnapProvider(),
  ]);

  /// Each module's session state, by module id, with the module that made
  /// it — which is what releases it.
  final Map<String, (EditorModule, Object)> _moduleStates = {};

  /// The session state a module created, by type; null when none did.
  @override
  T? stateOf<T extends Object>() =>
      _moduleStates.values.map((s) => s.$2).whereType<T>().firstOrNull;

  /// Rebuilds [tools] and [overlays] from the built-ins and the scope's
  /// modules. Called on construction and after a hot reload, so an edited
  /// module takes effect without reopening the designer.
  @internal
  void reloadModules() {
    final active = controller.toolId.value;
    tools.clear();
    _registerBuiltInTools();
    overlays.clear();
    _registerBuiltInOverlays();
    // Modules contribute after the built-ins, so a project can replace one
    // by reusing its id.
    final context = DesignerToolContext(
      scope: scope,
      world: world,
      sceneState: sceneState,
      history: history,
      uniqueName: _uniqueName,
    );
    final providers = <SnapProvider>[
      const EntitySnapProvider(),
      GridSnapProvider(scope.grid),
    ];
    for (final module in scope.designerModules) {
      module.toolGroups.forEach(tools.registerGroup);
      tools.registerAll(module.createTools(context));
      overlays.registerAll(module.overlays);
      providers.addAll(module.createSnapProviders(context));
      // State survives a reload: a route half-edited is still being edited.
      if (!_moduleStates.containsKey(module.id)) {
        final state = module.createSessionState(context);
        if (state != null) _moduleStates[module.id] = (module, state);
      }
    }
    // What a module that has left the session kept goes with it.
    final live = {for (final module in scope.designerModules) module.id};
    for (final id in [..._moduleStates.keys]) {
      if (live.contains(id)) continue;
      final (module, state) = _moduleStates.remove(id)!;
      module.disposeSessionState(state);
    }
    _snapper = SnapResolver(providers);
    if (tools.byId(active) == null && tools.all.isNotEmpty) {
      controller.toolId.value = tools.all.first.id;
    }
    _ensureActivePrefab();
  }

  /// Keeps a valid prefab selected, one that places in the scene's mode:
  /// in 2-D the plain rectangle by preference, which is the least
  /// surprising thing to stamp into an empty scene; in 3-D the cube; else
  /// the first there is. Only a preference: a project that unregisters the
  /// built-ins still gets a valid selection.
  void _ensureActivePrefab() {
    final mode = sceneState.editingMode;
    bool fits(PrefabDefinition? p) => p != null && p.dimensions.allows(mode);
    final active = controller.activePrefabId.value;
    if (active != null &&
        fits(scope.prefabs.byId(active) ?? sessionPrefabs.byId(active))) {
      return;
    }
    final preferred = scope.prefabs.byId(
      mode == jge.SceneMode.twoD
          ? BuiltInPrefabs.rectangleId
          : BuiltInDesigner3DContributions.cubeId,
    );
    controller.activePrefabId.value = fits(preferred)
        ? preferred!.id
        : scope.prefabs.all.where(fits).firstOrNull?.id;
  }

  /// Registers the overlays the editor itself provides.
  ///
  /// All genre-neutral: selection, the drag rectangle, alignment guides,
  /// rulers and the measure readout. Anything that visualises a *game* concept
  /// — a patrol path, a camera region — comes from a module.
  void _registerBuiltInOverlays() {
    overlays.registerAll([
      EntitySelectionOverlay(),
      DragRectOverlay(),
      GuidesOverlay(),
      MeasurementOverlay(_measureTool),
      RulersOverlay(),
      SelectionHandlesOverlay(scope.handleLayout),
      SmartGuidesOverlay(),
      MinimapOverlay(),
      CameraRigOverlay(brain: () => scope.cameraBrain),
      MotionPathOverlay(() => TimelineSession.of(scope)),
      TileGridOverlay(scope),
      TileBrushOverlay(scope),
      // The 3-D default kit's.
      Marquee3DOverlay(),
      PlaceGhost3DOverlay(_place3D),
      Ruler3DOverlay(_measure3D),
      KillHeight3DOverlay(scope),
    ]);
  }

  /// Registers the tools the editor itself provides.
  ///
  /// Re-registered per session rather than once, so an edited tool takes
  /// effect on hot reload. Registration is keyed by id, so a project that
  /// registered a replacement for a built-in keeps it only if it registers
  /// after this runs — which is what the extension pass does.
  void _registerBuiltInTools() {
    tools.registerAll([
      Select2DTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
        layout: scope.handleLayout,
        mapDocs: scope.mapDocs,
        rotationStep: () => scope.prefs.settings.value.rotationStepRadians,
        copySpecs: scope.entities.copySpecs,
      ),
      DrawRectTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
        scope: scope,
      ),
      PaintTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
        scope: scope,
      ),
      _measureTool,
      _eyedropper,
      // The generic path tool, bound to a dolly camera's track.
      PathTool(
        sceneState: sceneState,
        history: history,
        id: BuiltInTools.dolly,
        label: 'Track',
        icon: Icons.linear_scale,
        shortcut: null,
        description:
            'Edit a dolly camera\'s track: click to add a point, drag one to '
            'move it, Alt+click to remove it',
        order: 45,
        binding: PathBinding(
          resolve: (entity) => entity.getComponent<jge.CameraDollyComponent>(),
          read: (c) => List.of((c as jge.CameraDollyComponent).waypoints),
          write: (c, points) =>
              (c as jge.CameraDollyComponent).waypoints = List.of(points),
          isClosed: (c) => (c as jge.CameraDollyComponent).closed,
          emptyMessage: 'Select a dolly camera to edit its track',
        ),
      ),
      // The tile tools, after a divider.
      TileStampTool(scope, switchTool: setTool),
      TileTerrainTool(scope, switchTool: setTool),
      TileFillTool(scope, switchTool: setTool),
      TileEraseTool(scope, switchTool: setTool),
      TileSelectTool(scope, switchTool: setTool),
      // The default kit for 3-D scenes: offered only there, as the tools
      // above are only in 2-D. Select shares its id with the 2-D one.
      Select3DTool(),
      _place3D,
      MaterialPaint3DTool(scope: scope),
      _measure3D,
    ]);
  }

  /// The 3-D Measure tool: one per session, its line drawn by an overlay.
  late final Measure3DTool _measure3D = Measure3DTool();

  /// The 3-D Place tool: one per session, its preview drawn by an overlay.
  late final Place3DTool _place3D = Place3DTool(
    spawn: scope.entities.spawnPrefab,
    record: scope.entities.recordPlaced,
    state: () => scope.designer3D,
  );

  /// A name starting [prefix] that no entity in the scene has yet.
  @override
  String uniqueName(String prefix) => _uniqueName(prefix);

  /// Undo for every edit, shared with the rest of the editor.
  ///
  /// The scope owns it, so closing the designer does not throw away what
  /// was done in it and Ctrl+Z means the same thing everywhere.
  @override
  final EditorHistory history;

  /// Designer state, exposed as signals for the UI.
  @override
  late final LevelDesignerController controller;

  /// Duplicates the current selection. Supplied by the plugin, which owns
  /// entity naming and the scene graph — the session should not be reaching
  /// into either.
  final VoidCallback onDuplicate;

  /// Deletes the current selection.
  final VoidCallback onDelete;

  /// Repeats the current selection `count` times, each copy `step` further on.
  final void Function(int count, Offset step) onArray;

  /// In 3-D: copies the selection as the spec lays them out (ARRAY).
  final void Function(Array3DSpec spec)? onArray3D;

  /// The entities the current selection covers that the designer can move:
  /// see [SelectionOps.selectedIn].
  List<jge.Entity> selectionEntities() =>
      SelectionOps.selectedIn(sceneState, world);

  final String Function(String prefix) _uniqueName;

  /// Reads the current modifier keys.
  ///
  /// Injectable so the session can be driven in tests without a Flutter
  /// binding — reaching straight for `HardwareKeyboard.instance` made every
  /// pointer path untestable and tied the session to the binding lifecycle for
  /// the sake of three booleans.
  final ModifierKeys Function() _readModifiers;

  final EditorView Function()? _camera;

  /// The viewport's four views, where the editor splits it: what the VIEW
  /// section's switch turns on.
  @internal
  final SplitViews Function()? splitViews;
  late final EditorView _detachedCamera = GameCameraEditorView.of(
    jge.OutputCamera(),
  );

  /// The viewport camera. The plugin supplies the engine's; a session built
  /// on its own — in a test, say — gets a private one, so framing and zoom
  /// still work rather than every caller checking for null.
  @override
  EditorView get camera => _camera?.call() ?? _detachedCamera;
  final Measure2DTool _measureTool = Measure2DTool();
  late final EyedropperTool _eyedropper = EyedropperTool(
    switchTool: setTool,
    codec: scope.codec,
  );

  /// Whole-selection edits: nudge, turn, flip, resize, replace.
  @internal
  late final SelectionOps ops = SelectionOps(
    codec: scope.codec,
    world: world,
    sceneState: sceneState,
    history: history,
    uniqueName: _uniqueName,
    deletable: scope.deletable,
  );

  /// Saved camera views, by slot 1–9.
  final Map<int, _CameraBookmark> _bookmarks = {};

  /// Saved views of a 3-D scene, by slot 1–9: where the orbit is and how
  /// it looks.
  final Map<int, View3DPose> _bookmarks3D = {};
  final LevelDesignerPainter _painter = LevelDesignerPainter();

  LevelToolHandler? _activeGesture;

  /// True while a tool is mid-gesture, so the plugin leaves its gizmo handling
  /// alone rather than fighting the tool for the same drag.
  @internal
  bool get hasActiveGesture => _activeGesture != null;

  // ── Pointer routing ───────────────────────────────────────────────────────

  /// Offers a pointer-down to the active tool.
  ///
  /// Returns true when the tool claims the gesture; false lets the plugin fall
  /// back to its normal gizmo behaviour, which is what keeps the single-entity
  /// translate/rotate/scale handles working inside the designer.
  bool onPointerDown(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
    ToolButton button = ToolButton.primary,
    Duration? time,
  }) {
    final handler = controller.activeTool;
    if (handler == null) return false;
    if (button == ToolButton.secondary && !claimsSecondary()) return false;
    // A gesture whose release never came — the window lost focus mid-drag,
    // a second pointer went down — ends as Esc would end it, before this
    // press begins another: never left open for the new one to overwrite.
    final open = _activeGesture;
    if (open != null) {
      _activeGesture = null;
      open.onCancel();
    }

    _gestureButton = button;
    _gestureClicks = _countClick(time, screen ?? worldPosition, button);
    final claimed = handler.onPointerDown(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
    );
    if (claimed) {
      _activeGesture = handler;
    } else {
      _gestureButton = ToolButton.primary;
    }
    return claimed;
  }

  /// The button the gesture in progress began with.
  ToolButton _gestureButton = ToolButton.primary;

  /// Which press of a quick run the gesture began with.
  int _gestureClicks = 1;

  /// How soon a second press must follow the first to make a double-click.
  @internal
  static const Duration doubleClickTime = Duration(milliseconds: 350);

  /// How far apart, in screen pixels, the two presses may be.
  @internal
  static const double doubleClickSlop = 6;

  Duration? _lastPressAt;
  Offset? _lastPressAt2;
  ToolButton? _lastPressButton;

  /// Where the pointer last was over the level, for keys pressed without a
  /// click — a tool flipping its brush where the brush is shown.
  Offset? _hoverWorld;
  Offset? _hoverScreen;
  double _hoverGrid = 0;

  /// The pointer moved with no button down.
  void onPointerHover(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) {
    _hoverWorld = worldPosition;
    _hoverScreen = screen;
    _hoverGrid = gridSize;
    controller.activeTool?.onPointerHover(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
    );
  }

  /// The wheel turned by [delta] over the viewport: the active tool's
  /// first (Place spins what it is about to place while Shift is held).
  /// True when the tool kept it, and the view should not zoom.
  bool onScroll(
    Offset worldPosition,
    double gridSize,
    Offset delta, {
    Offset? screen,
    Size? canvasSize,
  }) {
    final tool = controller.activeTool;
    if (tool == null) return false;
    return tool.onScroll(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
      delta,
    );
  }

  /// The pointer left the viewport.
  void onPointerExit() {
    _hoverWorld = null;
    _hoverScreen = null;
    controller.activeTool?.onPointerExit();
  }

  /// Forwards a pointer move to the tool that claimed the gesture. The
  /// pointer is where keys pressed mid-drag act, as it is when hovering.
  void onPointerMove(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) {
    _hoverWorld = worldPosition;
    _hoverScreen = screen;
    _hoverGrid = gridSize;
    _activeGesture?.onPointerMove(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
    );
  }

  /// Completes the gesture.
  void onPointerUp(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) {
    final handler = _activeGesture;
    _activeGesture = null;
    handler?.onPointerUp(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
    );
    _gestureButton = ToolButton.primary;
  }

  /// Abandons the gesture without committing.
  void onPointerCancel() {
    _chromeOverlay?.onCancel();
    _chromeOverlay = null;
    _activeGesture?.onCancel();
    _activeGesture = null;
    _gestureButton = ToolButton.primary;
    controller
      ..dragRect.value = null
      ..screenRect.value = null
      // A cancelled move's alignment lines and gap readouts with it.
      ..snapGuides = const []
      ..spacingGuides = const [];
  }

  /// Switches tool, abandoning any gesture in progress.
  ///
  /// Abandoning rather than committing: a half-drawn rectangle is not
  /// something the author asked to place.
  @override
  void setTool(String toolId) {
    if (controller.toolId.value == toolId) return;
    if (tools.byId(toolId) == null) return;
    onPointerCancel();
    // The measurement readout belongs to the measure tool; leaving it on
    // screen after switching away would be a stale annotation nobody can
    // dismiss.
    if (toolId != BuiltInTools.measure) _measureTool.clear();
    if (toolId == BuiltInTools.eyedropper) {
      _eyedropper.activatedFrom(controller.toolId.value);
    }
    controller.activeTool?.onDeactivate();
    controller.toolId.value = toolId;
    controller.activeTool?.onActivate();
  }

  // ── Viewport chrome: rulers and minimap ───────────────────────────────────

  InteractiveOverlay? _chromeOverlay;

  // ── Keyboard ──────────────────────────────────────────────────────────────

  /// The key the active tool kept at its last press, whose repeats are
  /// swallowed while it is held.
  LogicalKeyboardKey? _toolKept;

  /// Handles a key pressed while authoring. Returns true when it was used.
  ///
  /// The editor-wide shortcuts — undo, redo, save, duplicate, delete — are the
  /// plugin's; everything specific to building a level is here. Single keys
  /// follow Tiled (X/Y flip, Z rotate) and Blender (H hide, Shift+H isolate).
  /// Tool shortcuts are consulted only after these, so an extension cannot
  /// take one of them by accident.
  bool handleKey(
    LogicalKeyboardKey key, {
    required double gridSize,
    bool isRepeat = false,
  }) {
    final mods = _readModifiers();
    // A ruler guide (or a module's chrome) being pulled: Esc lets it go, as
    // the status bar says, and nothing else — the selection stays.
    if (key == LogicalKeyboardKey.escape && hasChromeGesture) {
      if (!isRepeat) onPointerCancel();
      return true;
    }
    // The active tool first: a tile brush's X flips the brush, not the
    // selected entities; its Ctrl+C copies tiles, not entities. A tool's
    // keys act once a press: held, Z would turn the brush on every repeat,
    // and how it ended up would depend on how long the key was down. The
    // repeats of a key it kept are kept too, so they reach nothing else.
    final tool = controller.activeTool;
    if (isRepeat) {
      if (key == _toolKept) return true;
    } else {
      _toolKept = null;
      if (tool != null &&
          tool.onKey(
            key,
            _context(
              _hoverWorld ?? camera.position,
              _hoverWorld == null ? gridSize : _hoverGrid,
              screen: _hoverScreen,
            ),
          )) {
        _toolKept = key;
        return true;
      }
    }
    final context = CommandContext(
      scope: scope,
      session: this,
      modifiers: mods,
      gridSize: gridSize,
    );
    if (scope.commands.dispatch(
      key,
      context,
      availabilities: const {CommandAvailability.designer},
      isRepeat: isRepeat,
    )) {
      return true;
    }
    // A bare letter is a tool shortcut; a chord is somebody else's — Cmd+S
    // on a Mac too, and a letter with the Mac's Ctrl (or the Windows key).
    if (isRepeat || mods.control || mods.alt || mods.other) return false;
    final label = key.keyLabel;
    return label.length == 1 && selectToolByShortcut(label.toUpperCase());
  }

  // ── Snapping ──────────────────────────────────────────────────────────────

  /// Snapping on or off. One switch for the whole editor: the settings'
  /// Snap to grid, which the magnet over the viewport shows too.
  @internal
  void setSnapping(bool on) {
    controller.snapEnabled.value = on;
    if (scope.prefs.settings.value.gridSnappingEnabled != on) {
      scope.prefs.change((s) => s.copyWith(gridSnappingEnabled: on));
    }
  }

  /// Smart snap on or off, kept in the settings.
  @internal
  void setSmartSnap(bool on) {
    controller.smartSnap.value = on;
    if (scope.prefs.settings.value.smartSnap != on) {
      scope.prefs.change((s) => s.copyWith(smartSnap: on));
    }
  }

  // ── Painting ──────────────────────────────────────────────────────────────

  /// Draws every designer overlay. Called from the plugin's render hook, after
  /// the world and before the base editor's gizmos.
  void paint(Canvas canvas, Size canvasSize, EditorView camera) =>
      _painter.paint(
        canvas,
        canvasSize,
        camera,
        world,
        controller,
        overlays.all,
        isDrawn: isOverlayDrawn,
        showsGizmo: _showsGizmo,
      );

  /// Whether [overlay] is drawn, and offered the pointer, now: its toggle
  /// on, and a gizmo only while its kind is shown in the editor's mode.
  @internal
  bool isOverlayDrawn(DesignerOverlay overlay) {
    if (!controller.isOverlayVisible(overlay.id)) return false;
    final kind = overlay.gizmoKind;
    return kind == null || (_showsGizmo?.call(kind) ?? true);
  }

  /// Releases what this session owns.
  ///
  /// Not the history: the scope owns that, and closing the designer must
  /// not throw away what was done while it was open. A gesture under way —
  /// the designer closed with a button held — is put back as an Esc would,
  /// never left half-applied with no undo step; and the tool in hand lets
  /// go of what it shows on the scope (a tile brush's preview, the area
  /// being dragged), which outlives the session.
  void dispose() {
    // Unless the scope went first (an app closing): then nothing is left
    // to put back.
    if (!scope.container.isClosed) {
      onPointerCancel();
      controller.activeTool?.onDeactivate();
    }
    for (final (module, state) in _moduleStates.values) {
      module.disposeSessionState(state);
    }
    _moduleStates.clear();
    _stopWatchingDesigner();
    controller.dispose();
  }
}

/// A saved view: where the camera was and how far it was zoomed.
class _CameraBookmark {
  const _CameraBookmark(this.position, this.zoom);

  /// Restores one from [toJson]'s output.
  factory _CameraBookmark.fromJson(Map<String, dynamic> json) =>
      _CameraBookmark(
        Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
        (json['zoom'] as num).toDouble(),
      );

  /// Camera centre, in world space.
  final Offset position;

  /// Camera zoom.
  final double zoom;

  /// For saving with the scene.
  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'zoom': zoom,
  };
}
