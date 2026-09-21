import '../timeline/motion_path.dart';
import '../timeline/timeline_session.dart';
import 'dart:math' as math;

export 'state/modifier_keys.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import '../../extension/editor_module.dart';
import 'commands/designer_command.dart';
import 'overlays/built_in_overlays.dart';
import 'overlays/designer_overlay.dart';
import 'overlays/measurement_overlay.dart';
import 'overlays/minimap_overlay.dart';
import 'overlays/transform_overlays.dart';
import 'painters/level_designer_painter.dart';
import 'state/built_in_prefabs.dart';
import 'state/modifier_keys.dart';
import 'state/prefab_registry.dart';
import 'state/snap_provider.dart';
import 'state/level_designer_controller.dart';
import 'state/editor_history.dart';
import 'state/selection_ops.dart';
import 'tools/draw_rect_tool.dart';
import 'tools/eyedropper_tool.dart';
import 'tools/level_tool.dart';
import 'tools/tool_registry.dart';
import 'tools/measure_tool.dart';
import 'tools/paint_tool.dart';
import 'tools/select_tool.dart';
import '../overlay/camera_rig_painter.dart';
import 'tools/path_tool.dart';

/// Owns the Level Designer's runtime: state, tools, history and painting.
///
/// The plugin delegates pointer events and canvas painting here when the
/// designer is open, and keeps its existing behaviour when it is closed. That
/// split is deliberate — with the designer off, the overlay behaves exactly as
/// it always has, so this feature cannot regress the base editor.
class LevelDesignerSession {
  LevelDesignerSession({
    required this.scope,
    required String Function(String prefix) uniqueName,
    required this.onDuplicate,
    required this.onDelete,
    required this.onArray,
    ModifierKeys Function()? readModifiers,
    jge.Camera Function()? camera,
  }) : history = EditorHistory(),
       _uniqueName = uniqueName,
       _readModifiers = readModifiers ?? ModifierKeys.fromHardwareKeyboard,
       _camera = camera {
    controller = LevelDesignerController(
      sceneState: sceneState,
      history: history,
      tools: tools,
      prefabs: scope.prefabs,
      sessionPrefabs: sessionPrefabs,
    );

    // Descriptors, prefabs and layers are the scope's: registered once,
    // rebuilt on reload. Tools and overlays are per session, because a tool
    // edits *this* session's selection and pushes onto *this* history.
    reloadModules();
    // A designer switch swaps the tools and overlays under this session.
    _stopWatchingDesigner = scope.activeDesigner.watch(reloadModules);
  }

  late final VoidCallback _stopWatchingDesigner;

  /// The editor this session belongs to: its prefabs, layers, codec, log.
  final EditorScope scope;

  /// The world being edited.
  jge.World get world => scope.world;

  /// Selection and grid state shared with the rest of the editor.
  EditorSceneState get sceneState => scope.sceneState;

  /// This session's viewport tools: the built-ins, then each module's.
  final ToolRegistry tools = ToolRegistry();

  /// This session's overlays, in paint order.
  final OverlayRegistry overlays = OverlayRegistry();

  /// Prefabs that exist only for this session: the eyedropper's samples.
  final PrefabRegistry sessionPrefabs = PrefabRegistry();

  /// Whoever snaps for this session: the built-ins and the modules'
  /// providers, by priority.
  SnapResolver snapper = SnapResolver(const [
    EntitySnapProvider(),
    GridSnapProvider(),
  ]);

  final Map<String, Object> _moduleStates = {};

  /// The session state a module created, by type; null when none did.
  T? stateOf<T extends Object>() =>
      _moduleStates.values.whereType<T>().firstOrNull;

  /// Rebuilds [tools] and [overlays] from the built-ins and the scope's
  /// modules. Called on construction and after a hot reload, so an edited
  /// module takes effect without reopening the designer.
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
      tools.registerAll(module.createTools(context));
      overlays.registerAll(module.overlays);
      providers.addAll(module.createSnapProviders(context));
      // State survives a reload: a route half-edited is still being edited.
      if (!_moduleStates.containsKey(module.id)) {
        final state = module.createSessionState(context);
        if (state != null) _moduleStates[module.id] = state;
      }
    }
    final live = {for (final module in scope.designerModules) module.id};
    _moduleStates.removeWhere((id, _) => !live.contains(id));
    snapper = SnapResolver(providers);
    if (tools.byId(active) == null && tools.all.isNotEmpty) {
      controller.toolId.value = tools.all.first.id;
    }
    _ensureActivePrefab();
  }

  /// Keeps a valid prefab selected: the plain rectangle by preference, which
  /// is the least surprising thing to stamp into an empty scene, else the
  /// first there is. Only a preference: a project that unregisters the
  /// built-ins still gets a valid selection.
  void _ensureActivePrefab() {
    final active = controller.activePrefabId.value;
    if (active != null &&
        (scope.prefabs.byId(active) ?? sessionPrefabs.byId(active)) != null) {
      return;
    }
    final all = scope.prefabs.all;
    controller.activePrefabId.value = all.isEmpty
        ? null
        : scope.prefabs.byId(BuiltInPrefabs.rectangleId)?.id ?? all.first.id;
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
      SelectTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
        layout: scope.handleLayout,
      ),
      DrawRectTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
      ),
      PaintTool(
        sceneState: sceneState,
        history: history,
        uniqueName: _uniqueName,
        codec: scope.codec,
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
    ]);
  }

  /// Undo stack for every designer edit.
  final EditorHistory history;

  /// Designer state, exposed as signals for the UI.
  late final LevelDesignerController controller;

  /// Duplicates the current selection. Supplied by the plugin, which owns
  /// entity naming and the scene graph — the session should not be reaching
  /// into either.
  final VoidCallback onDuplicate;

  /// Deletes the current selection.
  final VoidCallback onDelete;

  /// Repeats the current selection `count` times, each copy `step` further on.
  final void Function(int count, Offset step) onArray;

  /// The entities the current selection covers: the multi-selection when there
  /// is one, otherwise just the primary selection.
  List<jge.Entity> selectionEntities() {
    final ids = sceneState.multiSelectedIds.value;
    if (ids.isNotEmpty) {
      return ids
          .map(world.getEntity)
          .whereType<jge.Entity>()
          .where((e) => e.isActive)
          .toList();
    }
    final selected = sceneState.selectedEntity.value;
    return selected == null ? <jge.Entity>[] : [selected];
  }

  final String Function(String prefix) _uniqueName;

  /// Reads the current modifier keys.
  ///
  /// Injectable so the session can be driven in tests without a Flutter
  /// binding — reaching straight for `HardwareKeyboard.instance` made every
  /// pointer path untestable and tied the session to the binding lifecycle for
  /// the sake of three booleans.
  final ModifierKeys Function() _readModifiers;

  final jge.Camera Function()? _camera;
  late final jge.Camera _detachedCamera = jge.Camera();

  /// The viewport camera. The plugin supplies the engine's; a session built
  /// on its own — in a test, say — gets a private one, so framing and zoom
  /// still work rather than every caller checking for null.
  jge.Camera get camera => _camera?.call() ?? _detachedCamera;
  final MeasureTool _measureTool = MeasureTool();
  late final EyedropperTool _eyedropper = EyedropperTool(
    switchTool: setTool,
    codec: scope.codec,
  );

  /// Whole-selection edits: nudge, turn, flip, resize, replace.
  late final SelectionOps ops = SelectionOps(
    codec: scope.codec,
    world: world,
    sceneState: sceneState,
    history: history,
    uniqueName: _uniqueName,
  );

  /// Saved camera views, by slot 1–9.
  final Map<int, CameraBookmark> bookmarks = {};
  final LevelDesignerPainter _painter = LevelDesignerPainter();

  LevelToolHandler? _activeGesture;

  /// True while a tool is mid-gesture, so the plugin leaves its gizmo handling
  /// alone rather than fighting the tool for the same drag.
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
  }) {
    final handler = controller.activeTool;
    if (handler == null) return false;

    final claimed = handler.onPointerDown(
      _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
    );
    if (claimed) _activeGesture = handler;
    return claimed;
  }

  /// Forwards a pointer move to the tool that claimed the gesture.
  void onPointerMove(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) => _activeGesture?.onPointerMove(
    _context(worldPosition, gridSize, screen: screen, canvasSize: canvasSize),
  );

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
  }

  /// Abandons the gesture without committing.
  void onPointerCancel() {
    _chromeOverlay?.onCancel();
    _chromeOverlay = null;
    _activeGesture?.onCancel();
    _activeGesture = null;
    controller.dragRect.value = null;
  }

  ToolContext _context(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) {
    final zoom = camera.zoom;
    return ToolContext(
      unitsPerPixel: zoom > 0 ? 1 / zoom : 1,
      world: world,
      controller: controller,
      worldPosition: worldPosition,
      screenPosition: screen,
      canvasSize: canvasSize ?? camera.viewportSize,
      camera: camera,
      gridSize: gridSize,
      modifiers: _readModifiers(),
      snapper: snapper,
      stateOf: stateOf,
      grid: scope.grid,
    );
  }

  /// Switches tool, abandoning any gesture in progress.
  ///
  /// Abandoning rather than committing: a half-drawn rectangle is not
  /// something the author asked to place.
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
    controller.toolId.value = toolId;
  }

  /// Switches to whichever tool claims [shortcut], if any.
  bool selectToolByShortcut(String shortcut) {
    final tool = tools.byShortcut(shortcut);
    if (tool == null) return false;
    setTool(tool.id);
    return true;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Centres and zooms the view on the selection (F).
  void frameSelection() {
    final entities = selectionEntities();
    if (entities.isEmpty) {
      controller.setStatus('Nothing selected to frame');
      return;
    }
    _frame(SelectionOps.boundsOf(entities));
  }

  /// Centres and zooms the view on everything visible (Shift+F).
  void frameAll() => _frame(
    SelectionOps.boundsOf([
      for (final e in world.query([jge.TransformComponent]))
        if (e.isActive && controller.isShownInViewport(e)) e,
    ]),
  );

  void _frame(Rect? bounds) {
    if (bounds == null) return;
    final cam = camera;
    cam.setPosition(bounds.center);
    final viewport = cam.viewportSize;
    if (viewport.isEmpty) return;
    // A margin so the edges are not flush with the viewport, and a ceiling
    // so framing a lone marker does not zoom in until it fills the screen.
    const margin = 1.25;
    final zoom = math.min(
      viewport.width / (math.max(bounds.width, 64) * margin),
      viewport.height / (math.max(bounds.height, 64) * margin),
    );
    cam.setZoom(zoom.clamp(cam.minZoom, math.min(cam.maxZoom, 4.0)));
  }

  /// Saves the current view in [slot] (Ctrl+1-9).
  void storeBookmark(int slot) {
    bookmarks[slot] = CameraBookmark(camera.position, camera.zoom);
    controller.setStatus('View saved to $slot');
  }

  /// Returns to the view saved in [slot] (1-9).
  void recallBookmark(int slot) {
    final bookmark = bookmarks[slot];
    if (bookmark == null) {
      controller.setStatus('No view saved in $slot - Ctrl+$slot saves one');
      return;
    }
    camera
      ..setPosition(bookmark.position)
      ..setZoom(bookmark.zoom);
  }

  // ── Visibility ────────────────────────────────────────────────────────────

  /// Hides the selection in the viewport (H). Editor-only.
  void hideSelection() {
    final ids = [for (final e in selectionEntities()) e.id];
    if (ids.isEmpty) return;
    controller.setEntitiesHidden(ids, hidden: true);
    sceneState.clearSelection();
    controller.setStatus('Hidden ${ids.length} - Alt+H shows everything');
  }

  /// Hides everything except the selection (Shift+H), to work on it alone.
  void isolateSelection() {
    final keep = {for (final e in selectionEntities()) e.id};
    if (keep.isEmpty) return;
    controller.setEntitiesHidden([
      for (final e in world.query([jge.TransformComponent]))
        if (!keep.contains(e.id)) e.id,
    ], hidden: true);
    controller.setStatus('Isolated ${keep.length} - Alt+H shows everything');
  }

  /// Shows every hidden entity (Alt+H).
  void unhideAll() => controller.hiddenEntities.value = <jge.EntityId>{};

  /// Locks the selection against picking (L).
  void lockSelection() {
    final ids = [for (final e in selectionEntities()) e.id];
    if (ids.isEmpty) return;
    controller.setEntitiesLocked(ids, locked: true);
    sceneState.clearSelection();
    controller.setStatus('Locked ${ids.length} - Alt+L unlocks everything');
  }

  /// Unlocks every locked entity (Alt+L).
  void unlockAll() => controller.lockedEntities.value = <jge.EntityId>{};

  /// Selects everything that can be picked (Ctrl+A).
  void selectAll() {
    sceneState.clearSelection();
    for (final e in world.query([jge.TransformComponent])) {
      if (e.isActive && controller.isPickable(e)) {
        sceneState.toggleMultiSelect(e);
      }
    }
  }

  /// Replaces the selection with the active prefab (R).
  void replaceSelection() {
    final prefab = controller.activePrefab;
    final entities = selectionEntities();
    if (prefab == null || entities.isEmpty) return;
    ops.replaceWith(entities, prefab);
  }

  // ── Viewport chrome: rulers and minimap ───────────────────────────────────

  InteractiveOverlay? _chromeOverlay;

  /// Whether an overlay (rulers, minimap, a module's) owns the pointer.
  bool get hasChromeGesture => _chromeOverlay != null;

  OverlayPointerContext _chromeContext(
    Offset screen,
    Size canvasSize,
    double gridSize,
  ) => OverlayPointerContext(
    screen: screen,
    canvasSize: canvasSize,
    area: controller.visibleViewport(canvasSize),
    camera: camera,
    world: world,
    controller: controller,
    history: history,
    modifiers: _readModifiers(),
    gridSize: gridSize,
  );

  /// Offers a press to the interactive overlays, topmost first, before any
  /// tool sees it. Screen-space chrome sits on top of the level, so it gets
  /// first refusal.
  bool onChromePointerDown(
    Offset screen,
    Size canvasSize, {
    double gridSize = 0,
  }) {
    final context = _chromeContext(screen, canvasSize, gridSize);
    for (final overlay in overlays.all.reversed) {
      if (overlay is! InteractiveOverlay) continue;
      if (!controller.isOverlayVisible(overlay.id)) continue;
      if (overlay.onPointerDown(context)) {
        _chromeOverlay = overlay;
        return true;
      }
    }
    return false;
  }

  /// Continues the overlay's drag.
  void onChromePointerMove(Offset screen, Size canvasSize, double gridSize) =>
      _chromeOverlay?.onPointerMove(
        _chromeContext(screen, canvasSize, gridSize),
      );

  /// Ends the overlay's drag.
  void onChromePointerUp(
    Offset screen,
    Size canvasSize, {
    double gridSize = 0,
  }) {
    _chromeOverlay?.onPointerUp(_chromeContext(screen, canvasSize, gridSize));
    _chromeOverlay = null;
  }

  /// The designer in use, ruler guides and camera bookmarks, for the scene
  /// file's `editor` section. Authoring aids, not level content: the game never reads them.
  Map<String, dynamic> editorData() => {
    'designer': ?scope.activeDesigner.value,
    'guides': [
      for (final g in controller.guides.value)
        {'vertical': g.isVertical, 'position': g.position},
    ],
    'bookmarks': {
      for (final entry in bookmarks.entries)
        '${entry.key}': entry.value.toJson(),
    },
    'modules': {
      for (final module in scope.modules.all)
        module.id: ?module.saveEditorData(this),
    },
  };

  /// Restores what [editorData] saved. Tolerates a missing or partial section
  /// — every scene saved before this existed has none.
  void restoreEditorData(Map<String, dynamic>? data) {
    // The designer the level was authored in, first: what follows is
    // restored into it.
    final designer = data?['designer'];
    scope.selectDesigner(designer is String ? designer : null);
    bookmarks.clear();
    final byModule = data?['modules'];
    for (final module in scope.modules.all) {
      final saved = byModule is Map ? byModule[module.id] : null;
      if (saved is Map) {
        module.restoreEditorData(this, saved.cast<String, Object?>());
      }
    }
    final guides = <DesignerGuide>[];
    if (data != null) {
      for (final g in (data['guides'] as List? ?? const []).whereType<Map>()) {
        final position = g['position'];
        if (position is! num) continue;
        guides.add(
          DesignerGuide(
            isVertical: g['vertical'] == true,
            position: position.toDouble(),
          ),
        );
      }
      final saved = data['bookmarks'];
      if (saved is Map) {
        for (final entry in saved.entries) {
          final slot = int.tryParse('${entry.key}');
          final value = entry.value;
          if (slot == null || value is! Map) continue;
          try {
            bookmarks[slot] = CameraBookmark.fromJson(
              value.cast<String, dynamic>(),
            );
          } on Object {
            // A malformed bookmark is not worth failing a scene load over.
          }
        }
      }
    }
    controller.guides.value = guides;
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

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
    final context = CommandContext(
      scope: scope,
      session: this,
      modifiers: mods,
      gridSize: gridSize,
    );
    if (scope.commands.dispatch(
      key,
      context,
      scopes: const {CommandScope.designer},
      isRepeat: isRepeat,
    )) {
      return true;
    }
    // A bare letter is a tool shortcut; a chord is somebody else's.
    if (isRepeat || mods.control || mods.alt) return false;
    final label = key.keyLabel;
    return label.length == 1 && selectToolByShortcut(label.toUpperCase());
  }

  // ── Painting ──────────────────────────────────────────────────────────────

  /// Draws every designer overlay. Called from the plugin's render hook, after
  /// the world and before the base editor's gizmos.
  void paint(Canvas canvas, Size canvasSize, jge.Camera camera) => _painter
      .paint(canvas, canvasSize, camera, world, controller, overlays.all);

  /// Releases signals and drops history.
  void dispose() {
    _stopWatchingDesigner();
    history.dispose();
    controller.dispose();
  }
}

/// A saved view: where the camera was and how far it was zoomed.
class CameraBookmark {
  const CameraBookmark(this.position, this.zoom);

  /// Restores one from [toJson]'s output.
  factory CameraBookmark.fromJson(Map<String, dynamic> json) => CameraBookmark(
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
