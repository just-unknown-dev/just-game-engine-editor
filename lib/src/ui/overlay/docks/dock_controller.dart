import 'package:just_signals/just_signals.dart';

/// Which dock is open and how tall each one is.
///
/// One dock at a time: opening one closes the other, and the settings panel
/// is a dock like any other under [settingsId]. Built-in and module docks go
/// through the same controller, so the compact strip has one code path.
class DockController {
  DockController();

  /// The settings panel's dock id.
  static const String settingsId = 'settings';

  /// The open dock's id, or null when every dock is closed.
  final Signal<String?> openId = Signal(null, debugLabel: 'openDock');

  /// Each dock's height once it has been resized. Replaced, never mutated,
  /// so a watcher sees every change.
  final Signal<Map<String, double>> heights = Signal(
    const {},
    debugLabel: 'dockHeights',
  );

  bool isOpen(String id) => openId.value == id;

  /// Opens [id], or closes it when it is the open one.
  void toggle(String id) => openId.value = openId.value == id ? null : id;

  void close() => openId.value = null;

  double heightOf(String id, {required double fallback}) =>
      heights.value[id] ?? fallback;

  /// Drags the top edge of [id] by [dy] screen pixels (up is negative).
  void resize(
    String id,
    double dy, {
    required double fallback,
    double min = 180,
    required double max,
  }) {
    heights.value = Map.unmodifiable({
      ...heights.value,
      id: (heightOf(id, fallback: fallback) - dy).clamp(min, max),
    });
  }

  void dispose() {
    openId.dispose();
    heights.dispose();
  }
}
