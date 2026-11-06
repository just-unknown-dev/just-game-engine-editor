/// The ids of the editor's own docks, for what opens one: the inspector's
/// tag and layer links, the status bar, the commands that open a dock.
abstract final class DockIds {
  static const String console = 'logs';
  static const String assets = 'assets';
  static const String timeline = 'timeline';
  static const String profiler = 'fps';
  static const String world = 'entities';
  static const String problems = 'problems';
  static const String history = 'history';
  static const String animator = 'animator';
  static const String search = 'search';
  static const String tags = 'tags';
  static const String physics = 'physics';

  /// The arg a readout passes to open the Console on one level.
  static const String levelArg = 'level';
}
