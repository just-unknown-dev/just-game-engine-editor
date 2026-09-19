import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../grid/grid_topology.dart';
import '../grid/square_grid.dart';
import '../state/level_designer_controller.dart';
import '../state/modifier_keys.dart';
import '../state/snap_provider.dart';

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

  /// Current grid size, for snapping and painting.
  final double gridSize;

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
    if (!snapping || gridSize <= 0) return value;
    return grid.snapValue(value, gridSize);
  }

  /// Snaps a point to the grid when snapping is active.
  Offset snapPoint(Offset point) =>
      snapping && gridSize > 0 ? grid.snapPoint(point, gridSize) : point;
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
}
