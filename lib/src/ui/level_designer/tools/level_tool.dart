import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/scope/editor_scope.dart';
import '../grid/grid_topology.dart';
import '../grid/square_grid.dart';
import '../state/level_designer_controller.dart';
import '../state/modifier_keys.dart';
import '../state/snap_provider.dart';

/// Which mouse button began a gesture.
enum ToolButton { primary, secondary, middle }

/// A part of the tool strip: the tools that do one kind of job, under a
/// caption.
class ToolGroup {
  const ToolGroup({required this.id, required this.label, required this.order});

  final String id;

  /// The caption, e.g. `'TILES'`.
  final String label;

  /// Where the group sits in the strip. Lower is higher up.
  final int order;
}

/// The groups the tool strip divides tools into.
abstract final class ToolGroups {
  /// Tools that pick, move and edit what is already there.
  static const String select = 'select';

  /// Tools that draw and paint shapes and prefabs.
  static const String shapes = 'shapes';

  /// Tools that paint tiles.
  static const String tiles = 'tiles';

  /// Tools that measure.
  static const String measure = 'measure';

  /// The editor's own groups, top to bottom.
  static const List<ToolGroup> builtIn = [
    ToolGroup(id: select, label: 'SELECT', order: 0),
    ToolGroup(id: shapes, label: 'SHAPES', order: 10),
    ToolGroup(id: tiles, label: 'TILES', order: 20),
    ToolGroup(id: measure, label: 'MEASURE', order: 90),
  ];
}

/// What a tool's options are built with, for the left of the designer's
/// status bar.
class ToolOptionsContext {
  const ToolOptionsContext({
    required this.scope,
    required this.controller,
    required this.world,
    required this.setTool,
  });

  final EditorScope scope;
  final LevelDesignerController controller;
  final jge.World world;

  /// Switches the designer's tool.
  final void Function(String toolId) setTool;
}

/// Everything a tool needs to act, without reaching into the plugin.
///
/// Passed fresh on each pointer event rather than stored, so a tool can never
/// act on a stale world or camera — both can change underneath it when a
/// scene is opened.
class ToolContext {
  ToolContext({
    required this.world,
    required this.controller,
    required this.worldPosition,
    required this.gridSize,
    this.snapStep = 0,
    ModifierKeys? modifiers,
    bool isShiftDown = false,
    bool isAltDown = false,
    bool isCtrlDown = false,
    this.unitsPerPixel = 1,
    this.camera,
    this.canvasSize = Size.zero,
    this.screenPosition,
    SnapResolver? snapper,
    T? Function<T extends Object>()? stateOf,
    this.grid = const SquareGrid(),
    this.button = ToolButton.primary,
    this.clickCount = 1,
  }) : modifiers =
           modifiers ??
           ModifierKeys(
             shift: isShiftDown,
             alt: isAltDown,
             control: isCtrlDown,
           ),
       snapper =
           snapper ??
           SnapResolver([const EntitySnapProvider(), GridSnapProvider(grid)]),
       _stateOf = stateOf;

  /// The world being edited.
  final jge.World world;

  /// Designer state: active prefab, layers, guides.
  final LevelDesignerController controller;

  /// Pointer position in world space.
  final Offset worldPosition;

  /// Pointer position on the canvas, when the event came from one.
  final Offset? screenPosition;

  /// Current grid size, for painting cells — and for snapping, unless
  /// [snapStep] says otherwise.
  final double gridSize;

  /// What moving snaps in, when not the grid: the settings' move step. 0 is
  /// the grid's own size.
  final double snapStep;

  /// What moving snaps in now: [snapStep] on a square grid, the cells on
  /// any other.
  double get moveStep =>
      snapStep > 0 && grid is SquareGrid ? snapStep : gridSize;

  /// The modifier keys held.
  final ModifierKeys modifiers;

  /// The viewport camera, when the session has one.
  final jge.Camera? camera;

  /// The canvas the event landed on; zero when unknown.
  final Size canvasSize;

  /// Whoever snaps for this session: built-ins and the modules' providers.
  final SnapResolver snapper;

  /// The shape of the cells: what painting, filling and grid snapping use.
  final GridTopology grid;

  /// The button the gesture began with. Only a tool that
  /// [LevelToolHandler.acceptsSecondaryButton] ever sees anything but
  /// [ToolButton.primary].
  final ToolButton button;

  /// Which press of a quick run the gesture began with: 2 for the second of
  /// a double-click. The session counts — the same button, pressed again
  /// soon and close by.
  final int clickCount;

  /// The gesture began with the second press of a double-click, or later.
  bool get isDoubleClick => clickCount >= 2;

  final T? Function<T extends Object>()? _stateOf;

  /// Shift held — constrains a drag to its dominant axis.
  bool get isShiftDown => modifiers.shift;

  /// Alt held. At the start of a drag in the select tool it duplicates the
  /// selection; while resizing it grows both sides about the centre.
  bool get isAltDown => modifiers.alt;

  /// Ctrl held. At the start of a gesture it adds to the selection; during a
  /// drag it suspends snapping, so something can be placed off the grid
  /// without turning snapping off and back on.
  bool get isCtrlDown => modifiers.control;

  /// World units per screen pixel at the current zoom. Hit areas and snap
  /// distances are defined in pixels, so they feel the same at any zoom.
  final double unitsPerPixel;

  /// The session state a module created with `createSessionState`, by type.
  T? stateOf<T extends Object>() => _stateOf?.call<T>();

  /// Whether snapping applies right now, folding in the Ctrl override.
  bool get snapping => controller.snapEnabled.value && !isCtrlDown;

  /// Whether snapping to other entities applies right now.
  bool get smartSnapping => snapping && controller.smartSnap.value;

  /// [pixels] screen pixels, in world units.
  double pixels(double pixels) => pixels * unitsPerPixel;

  /// Snaps [value] to the grid when snapping is active.
  double snap(double value) {
    if (!snapping || moveStep <= 0) return value;
    return grid.snapValue(value, moveStep);
  }

  /// Snaps a point to the grid when snapping is active.
  Offset snapPoint(Offset point) =>
      snapping && moveStep > 0 ? grid.snapPoint(point, moveStep) : point;
}

/// A viewport tool: something that interprets pointer drags as an edit.
///
/// Tools own no state that outlives a gesture beyond what they need to track
/// the drag in progress, and they never paint directly — they describe what
/// should be drawn through [LevelDesignerController] so all designer painting
/// stays on the single canvas pass the plugin owns.
///
/// A tool is identified by a plain string rather than an enum value, so a
/// project can add one without the editor package having to know it exists.
/// The palette renders whatever is registered, using the metadata below.
abstract class LevelToolHandler {
  /// Stable identifier, e.g. `'select'` or `'platformer.path'`.
  ///
  /// Prefix project tools with something of your own; an id collision silently
  /// replaces the earlier tool.
  String get id;

  /// Short palette label.
  String get label;

  /// Palette icon.
  IconData get icon;

  /// Single-key shortcut, shown in the tooltip. Null for no shortcut.
  String? get shortcut => null;

  /// Longer explanation for the tooltip.
  String? get description => null;

  /// Palette ordering. Lower sorts first.
  int get order => 100;

  /// Which part of the strip it sits in: one of [ToolGroups], or a group of
  /// a module's own (`EditorModule.toolGroups`). The strip captions each
  /// group.
  String get group => ToolGroups.select;

  /// Whether a right-button press is this tool's. Otherwise it opens the
  /// viewport's context menu, which Shift+right-click always does.
  bool get acceptsSecondaryButton => false;

  /// Pointer pressed. Return true to claim the gesture; returning false lets
  /// the default gizmo handling take over.
  bool onPointerDown(ToolContext context) => false;

  /// Pointer moved while the gesture is active.
  void onPointerMove(ToolContext context) {}

  /// Pointer released — commit the edit here, as one undoable command.
  void onPointerUp(ToolContext context) {}

  /// Gesture abandoned (pointer cancelled, tool switched). Discard any
  /// in-progress state without committing.
  void onCancel() {}

  /// Pointer moved with no button down — for showing what a click would
  /// do, like a brush under the cursor.
  void onPointerHover(ToolContext context) {}

  /// Pointer left the viewport.
  void onPointerExit() {}

  /// A key pressed while this tool is active, before the designer's own
  /// commands and the editor's. Return true to keep it. [context] is at the
  /// pointer's last position.
  bool onKey(LogicalKeyboardKey key, ToolContext context) => false;

  /// Became the active tool.
  void onActivate() {}

  /// Stopped being the active tool.
  void onDeactivate() {}

  /// The tool's settings — modes, sizes, switches — for the left of the
  /// designer's status bar. Null when it has none; the bar then says what
  /// the tool does.
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) =>
      null;
}
