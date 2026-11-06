import 'package:just_editor_core/host.dart';

import 'dock_controller.dart';

/// The docks' state, on the scope it belongs to: made the first time it is
/// asked for, in the scope's container, so it is disposed with the scope.
extension ScopeDocks on EditorScope {
  /// Which dock is open and how tall each one is.
  DockController get dockController =>
      service(DockController.new, dispose: (d) => d.dispose());
}
