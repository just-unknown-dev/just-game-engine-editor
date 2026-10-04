/// The workspaces the editor itself brings.
library;

import 'package:flutter/material.dart';

import '../../extension/editor_contributions.dart';
import 'tileset_workspace.dart';

abstract final class BuiltInWorkspaces {
  /// The Tileset Editor: opens `.tileset.json` files, and cuts a new
  /// tileset from an image it is opened on.
  static const String tileset = 'tileset';

  static final List<WorkspaceDefinition> all = [
    WorkspaceDefinition(
      id: tileset,
      label: 'Tileset Editor',
      icon: Icons.grid_view,
      order: 30,
      fileExtensions: const ['tileset.json'],
      build: (context, workspace) => TilesetEditor(
        root: workspace.scope.mapDocs.projectRoot,
        path: workspace.path,
        onClose: workspace.onClose,
        // Every map drawing the tileset reads it again.
        onSaved: (path) => workspace.reloadAssets?.call(path),
        fullScreen: workspace.fullScreen,
        onToggleFullScreen: workspace.onToggleFullScreen,
        setCloseGuard: workspace.setCloseGuard,
        // Through the edited engine's sprite seam: the project's files
        // while the editor runs.
        loadImage: (path) => workspace.scope.context.sprites.loadImage(path),
        collisionKinds: workspace.scope.context.collisionKinds,
      ),
    ),
  ];
}
