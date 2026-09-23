/// The interface editor, as a workspace.
///
/// A workspace rather than an overlay over the viewport: editing a HUD is
/// its own job, like the sprite editor's, and it wants the screen and its
/// own keys rather than a frame drawn over the world.
library;

import 'package:flutter/material.dart';

import '../../../extension/editor_contributions.dart';
import 'ui_mode_overlay.dart';

abstract final class BuiltInWorkspaces {
  /// What `scope.openWorkspace` is called with to edit the interface.
  static const String ui = 'ui';

  static final List<WorkspaceDefinition> all = [
    WorkspaceDefinition(
      id: ui,
      label: 'Interface',
      icon: Icons.phone_iphone,
      order: 20,
      build: (context, workspace) => UiModeOverlay(
        scope: workspace.scope,
        session: workspace.scope.uiMode,
        sceneState: workspace.scope.sceneState,
        history: workspace.scope.history,
        onClose: workspace.onClose,
        fullScreen: workspace.fullScreen,
        onToggleFullScreen: workspace.onToggleFullScreen,
      ),
    ),
  ];
}
