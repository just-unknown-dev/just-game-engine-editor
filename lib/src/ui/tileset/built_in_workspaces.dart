/// The workspaces the editor itself brings.
library;

import 'package:flutter/material.dart';

import 'package:just_editor_core/host.dart';
import 'tileset_workspace.dart';
import '../json_viewer/json_viewer.dart';
import '../../core/scope/editor_scope_services.dart';

abstract final class BuiltInWorkspaces {
  /// The Tileset Editor: opens `.tileset.json` files, and cuts a new
  /// tileset from an image it is opened on.
  static const String tileset = 'tileset';

  /// A JSON file no other window opens, shown as it is and never written:
  /// `json` is the shortest ending, so any window with a longer one —
  /// `material2d.json` — wins.
  static const String json = 'json';

  static List<WorkspaceDefinition> get all => [
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
    WorkspaceDefinition(
      id: json,
      label: 'JSON',
      icon: Icons.data_object,
      order: 900,
      fileExtensions: const ['json'],
      build: (context, workspace) =>
          JsonViewer(path: workspace.path!, workspace: workspace),
    ),
  ];
}
