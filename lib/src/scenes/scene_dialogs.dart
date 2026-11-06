import 'package:flutter/material.dart';

import 'package:just_editor_core/host.dart';

/// Asks before deleting [sceneName]. True when the user went ahead.
///
/// The scene goes to the project's trash, not away for good: the Scenes
/// list offers Undo straight after, and the file stays in
/// `.editor_trash/` until it is emptied.
Future<bool> confirmDeleteScene(BuildContext context, String sceneName) =>
    showEditorConfirm(
      context,
      title: 'Delete scene?',
      message:
          'This deletes "$sceneName" '
          '(assets/scenes/$sceneName.scene.json) and takes it out of the '
          'play order. The file goes to ${AssetIndex.trashFolder}/ in the '
          'project; Undo, straight after, brings it back.',
      confirmLabel: 'Delete',
    );
