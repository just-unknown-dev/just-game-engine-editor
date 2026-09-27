import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/state/editor_scene_state.dart';
import '../../../core/state/editor_view_state.dart';
import '../tools/level_tool.dart';
import '../tools/tool_registry.dart';
import 'prefab_registry.dart';
import 'smart_snap.dart';
import 'editor_history.dart';

/// What the paint tool does on drag.
enum PaintMode {
  /// Stamp the active prefab into each grid cell.
  brush,

  /// Remove whatever occupies each grid cell.
  eraser,

  /// Fill a dragged rectangle.
  rectangle,

  /// Flood-fill the empty region under the pointer, bounded by what is
  /// already there.
  fill,
}

/// A horizontal or vertical alignment guide.
class DesignerGuide {
  const DesignerGuide({required this.isVertical, required this.position});

  /// True for a vertical guide (constant world X).
  final bool isVertical;

  /// World-space X for a vertical guide, Y for a horizontal one.
  final double position;

  @override
  bool operator ==(Object other) =>
      other is DesignerGuide &&
      other.isVertical == isVertical &&
      other.position == position;

  @override
  int get hashCode => Object.hash(isVertical, position);
}

/// Live state for the Level Designer workspace.
///
/// Everything here is a signal so panels bind to exactly the slice they care
/// about — the layer list should not rebuild because the pointer moved.
///
/// Deliberately *not* holding per-frame values. Camera position, pointer
/// position and entity transforms change every tick; routing those through
/// signals would mean a widget rebuild per frame. They stay on the canvas
/// painting path, which is already running at frame rate.
class LevelDesignerController {
  LevelDesignerController({
    required this.sceneState,
    required this.history,
    EditorViewState? view,
    ToolRegistry? tools,
    PrefabRegistry? prefabs,
    PrefabRegistry? sessionPrefabs,
  }) : view = view ?? EditorViewState(),
       tools = tools ?? ToolRegistry(),
       prefabs = prefabs ?? PrefabRegistry(),
       sessionPrefabs = sessionPrefabs ?? PrefabRegistry();

  /// What is hidden and what is locked. The scope's, so the scene tree's
  /// eye and padlock mean the same thing with the designer shut.
  final EditorViewState view;

  /// The tools [toolId] resolves against — the session's.
  final ToolRegistry tools;

  /// The prefabs [activePrefabId] resolves against — the scope's.
  final PrefabRegistry prefabs;

  /// Prefabs that exist only for this session: the eyedropper's samples.
  final PrefabRegistry sessionPrefabs;

  /// Shared editor selection and grid state.
  final EditorSceneState sceneState;

  /// The designer's undo stack.
  final EditorHistory history;

  // ── Tool state ────────────────────────────────────────────────────────────

  /// Id of the active viewport tool.
  ///
  /// A plain string rather than an enum so a project can register a tool the
  /// editor package has never heard of. Resolve it through [ToolRegistry].
  final Signal<String> toolId = Signal(BuiltInTools.select, debugLabel: 'tool');

  /// The active tool handler, resolved from [toolId].
  LevelToolHandler? get activeTool => tools.byId(toolId.value);

  /// The group of the tool in hand: one of [ToolGroups], or a module's own.
  String get activeGroup => activeTool?.group ?? ToolGroups.select;

  /// Side-panel sections the author opened or closed, by tool group and
  /// section id. A section otherwise follows the tools in hand: the tile
  /// sections open with a tile tool, the prefab ones with the others.
  final Signal<Map<String, Map<String, bool>>> sectionsOpen = Signal(
    const {},
    debugLabel: 'sectionsOpen',
  );

  /// Whether side-panel [section] is open with the tools in hand; when the
  /// author has not said, whether it belongs to them — [groups] null means
  /// every group.
  bool isSectionOpen(String section, {Set<String>? groups}) =>
      sectionsOpen.value[activeGroup]?[section] ??
      (groups == null || groups.contains(activeGroup));

  /// Opens or closes [section] for the tools in hand, remembered for them.
  void setSectionOpen(String section, {required bool open}) {
    final group = activeGroup;
    sectionsOpen.value = {
      ...sectionsOpen.value,
      group: {...?sectionsOpen.value[group], section: open},
    };
  }

  /// Active paint mode, when [tool] is [LevelTool.paint].
  final Signal<PaintMode> paintMode = Signal(
    PaintMode.brush,
    debugLabel: 'paintMode',
  );

  /// Id of the prefab the draw and paint tools will place.
  ///
  /// Starts unset: which prefab is sensible depends entirely on what the
  /// project registered, and defaulting to one of them would be a guess. The
  /// session picks the first registered prefab once the palette is known.
  final Signal<String?> activePrefabId = Signal(
    null,
    debugLabel: 'activePrefab',
  );

  /// The active prefab, resolved from [activePrefabId].
  PrefabDefinition? get activePrefab {
    final id = activePrefabId.value;
    return id == null ? null : prefabs.byId(id) ?? sessionPrefabs.byId(id);
  }

  // ── Layers ────────────────────────────────────────────────────────────────

  /// Layer new entities are placed on.
  final Signal<String> activeLayerId = Signal(
    'main',
    debugLabel: 'activeLayer',
  );

  /// Layers hidden in the viewport. Editor-only: hiding must never change what
  /// the level actually does.
  final Signal<Set<String>> hiddenLayers = Signal(
    <String>{},
    debugLabel: 'hiddenLayers',
  );

  /// Layers excluded from picking, so finished work cannot be dragged by
  /// accident while building on top of it.
  final Signal<Set<String>> lockedLayers = Signal(
    <String>{},
    debugLabel: 'lockedLayers',
  );

  /// Whether [layerId] is currently hidden.
  bool isLayerHidden(String layerId) => hiddenLayers.value.contains(layerId);

  /// Whether [layerId] is currently locked.
  bool isLayerLocked(String layerId) => lockedLayers.value.contains(layerId);

  /// Shows or hides [layerId].
  void setLayerHidden(String layerId, {required bool hidden}) {
    final next = Set<String>.from(hiddenLayers.value);
    hidden ? next.add(layerId) : next.remove(layerId);
    hiddenLayers.value = next;
  }

  /// Locks or unlocks [layerId].
  void setLayerLocked(String layerId, {required bool locked}) {
    final next = Set<String>.from(lockedLayers.value);
    locked ? next.add(layerId) : next.remove(layerId);
    lockedLayers.value = next;
  }

  /// The layer of its parent's map [entity] is on, if it is on one: set by
  /// the session, which knows the world. An entity on a map layer is hidden
  /// and locked with that layer, not with its depth.
  jge.MapLayerData? Function(jge.Entity entity)? mapLayerOf;

  /// Whether [entity] can be picked in the viewport right now.
  bool isPickable(jge.Entity entity) {
    if (!isShownInViewport(entity)) return false;
    if (lockedEntities.value.contains(entity.id)) return false;
    final layer = entity.getComponent<jge.LayerComponent>();
    if (layer?.mapLayer != null) {
      return !(mapLayerOf?.call(entity)?.locked ?? false);
    }
    return layer == null || !isLayerLocked(layer.layerId);
  }

  // ── Viewport affordances ──────────────────────────────────────────────────

  /// The in-progress marquee or draw rectangle, in world space.
  ///
  /// A signal rather than plain state because the status bar shows its size as
  /// you drag; the canvas reads it directly during paint.
  final Signal<Rect?> dragRect = Signal(null, debugLabel: 'dragRect');

  /// Alignment guides dragged out from the rulers.
  final Signal<List<DesignerGuide>> guides = Signal(
    const [],
    debugLabel: 'guides',
  );

  /// Whether rulers are drawn along the viewport edges.
  final Signal<bool> showRulers = Signal(true, debugLabel: 'showRulers');

  /// Ids of registered overlays currently hidden.
  ///
  /// Replaces the fixed `showRegions` / `showPaths` flags, which only existed
  /// because the overlays they gated were hardcoded. Each registered overlay
  /// now owns its own toggle, including ones a project adds.
  final Signal<Set<String>> hiddenOverlays = Signal(
    <String>{},
    debugLabel: 'hiddenOverlays',
  );

  /// Snap positions to the grid. Mirrors [EditorSceneState.gridSnappingEnabled]
  /// so the designer's own toggle and the overlay settings agree.
  final Signal<bool> snapEnabled = Signal(true, debugLabel: 'snapEnabled');

  /// Snap to other entities' edges and centres, and to ruler guides, as
  /// well as to the grid.
  ///
  /// Levels are built by lining things up with each other, and the grid only
  /// helps when both things happen to sit on it.
  final Signal<bool> smartSnap = Signal(true, debugLabel: 'smartSnap');

  /// Brush width in cells for the paint tool: 1, 3 or 5.
  final Signal<int> brushSize = Signal(1, debugLabel: 'brushSize');

  /// Entities hidden in the viewport (H, or everything else under
  /// isolate). Editor-only, like hidden layers: nothing about the entity
  /// changes and nothing is saved.
  Signal<Set<jge.EntityId>> get hiddenEntities => view.hidden;

  /// Entities excluded from picking (L).
  Signal<Set<jge.EntityId>> get lockedEntities => view.locked;

  /// Hides or shows [ids].
  void setEntitiesHidden(Iterable<jge.EntityId> ids, {required bool hidden}) =>
      view.setHidden(ids, hidden: hidden);

  /// Locks or unlocks [ids].
  void setEntitiesLocked(Iterable<jge.EntityId> ids, {required bool locked}) =>
      view.setLocked(ids, locked: locked);

  /// Whether [entity] is drawn in the viewport while authoring — neither it
  /// nor its layer is hidden, and it is within the designer's reach.
  bool isShownInViewport(jge.Entity entity) {
    if (hiddenEntities.value.contains(entity.id)) return false;
    // Everything but the Level Map, while designing: out of reach, and out
    // of sight with it.
    if (!sceneState.canSelect(entity)) return false;
    final layer = entity.getComponent<jge.LayerComponent>();
    if (layer?.mapLayer != null) {
      return mapLayerOf?.call(entity)?.visible ?? true;
    }
    return layer == null || !isLayerHidden(layer.layerId);
  }

  /// How much of the canvas the editor's panels cover on each side.
  ///
  /// The canvas runs under the tool palette, the side panels and the status
  /// bar; rulers, the minimap and anything else drawn in screen space belong
  /// in the part that is actually visible. Published by the overlay that lays
  /// those panels out, on every layout.
  EdgeInsets viewportInsets = EdgeInsets.zero;

  /// Height kept clear beneath the minimap, for anything the overlay places
  /// there. Published alongside [viewportInsets].
  double minimapBottomReserve = 0;

  /// The visible part of a canvas of [canvasSize], in screen pixels.
  Rect visibleViewport(Size canvasSize) =>
      viewportInsets.deflateRect(Offset.zero & canvasSize);

  /// Alignments and gaps from the drag in progress, for the smart guides
  /// overlay. Plain fields rather than signals: they change on every pointer
  /// move and only the canvas, which repaints every frame anyway, reads them.
  List<SnapGuide> snapGuides = const [];

  /// See [snapGuides].
  List<SpacingGuide> spacingGuides = const [];

  /// Whether the overlay with [overlayId] is currently drawn.
  bool isOverlayVisible(String overlayId) =>
      !hiddenOverlays.value.contains(overlayId);

  /// Shows or hides an overlay.
  void setOverlayVisible(String overlayId, {required bool visible}) {
    final next = Set<String>.from(hiddenOverlays.value);
    visible ? next.remove(overlayId) : next.add(overlayId);
    hiddenOverlays.value = next;
  }

  /// Status text shown in the designer's bottom strip.
  final Signal<String> status = Signal('', debugLabel: 'status');

  /// Reports a transient message, e.g. a measured distance.
  void setStatus(String message) => status.value = message;

  /// Resets per-scene state. Called when a different scene is opened, because
  /// history and guides both refer to entities from the old one.
  void resetForScene() {
    batch(() {
      history.clear();
      dragRect.value = null;
      guides.value = const [];
      hiddenLayers.value = <String>{};
      lockedLayers.value = <String>{};
      hiddenEntities.value = <jge.EntityId>{};
      lockedEntities.value = <jge.EntityId>{};
      snapGuides = const [];
      spacingGuides = const [];
      status.value = '';
    });
  }

  /// Releases every signal.
  void dispose() {
    toolId.dispose();
    paintMode.dispose();
    activePrefabId.dispose();
    activeLayerId.dispose();
    hiddenLayers.dispose();
    lockedLayers.dispose();
    dragRect.dispose();
    guides.dispose();
    showRulers.dispose();
    hiddenOverlays.dispose();
    sectionsOpen.dispose();
    snapEnabled.dispose();
    smartSnap.dispose();
    brushSize.dispose();
    // Not the hidden and locked sets: the scope owns those, and they
    // outlive any one designer session.
    status.dispose();
  }
}
