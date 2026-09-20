import 'level_tool.dart';

/// The tools available in the designer's left-hand palette.
///
/// Mirrors [PrefabRegistry] and [OverlayRegistry] so every kind of designer
/// extension is registered the same way.
class ToolRegistry {
  ToolRegistry();

  final Map<String, LevelToolHandler> _tools = {};

  /// All registered tools, in palette order.
  List<LevelToolHandler> get all {
    final sorted = _tools.values.toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
      });
    return List.unmodifiable(sorted);
  }

  /// Looks up a tool by [LevelToolHandler.id].
  LevelToolHandler? byId(String id) => _tools[id];

  /// The tool bound to [shortcut], if any.
  LevelToolHandler? byShortcut(String shortcut) {
    final wanted = shortcut.toUpperCase();
    for (final tool in _tools.values) {
      if (tool.shortcut?.toUpperCase() == wanted) return tool;
    }
    return null;
  }

  /// Registers [tool], replacing any existing one with the same id.
  void register(LevelToolHandler tool) => _tools[tool.id] = tool;

  /// Registers several tools.
  void registerAll(Iterable<LevelToolHandler> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Removes every registration, ahead of rebuilding from extensions.
  void clear() => _tools.clear();
}

/// Ids of the tools the editor itself provides.
///
/// A project can replace one by registering its own tool with the same id —
/// the same override path definitions already use.
abstract final class BuiltInTools {
  /// Select, marquee and manipulate.
  static const String select = 'select';

  /// Drag out a rectangle to place the active prefab.
  static const String draw = 'draw';

  /// Brush, rectangle fill and eraser on the grid.
  static const String paint = 'paint';

  /// Measure a distance in world units.
  static const String measure = 'measure';

  /// Sample an entity as the thing to draw and paint.
  static const String eyedropper = 'eyedropper';

  /// Edits the track of the selected dolly camera.
  static const String dolly = 'camera.dolly';
}
