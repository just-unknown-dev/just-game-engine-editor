part of 'just_game_editor_plugin.dart';

/// Project files changed on disk: what the editor reads again — sprites,
/// materials, fonts, sounds, animators, Level Maps, timelines.
extension PluginAssetReloads on JustGameEditorPlugin {
  /// A sprite file changed on disk: show the new one. [atlasPath] limits it
  /// to one atlas (and the sheet beside it); without it everything reloads.
  @internal
  void reloadSprites([String? atlasPath]) {
    if (atlasPath == null) spriteAssets.clear();
    for (final system in engine.world.systems) {
      if (system is SpriteAnimationSystem) system.reload(atlasPath);
      if (system is SpriteLoadSystem) system.reload();
    }
  }

  /// A file a tool wrote changed: whatever in the level shows it, shows the
  /// new version.
  @internal
  void reloadAsset(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.animator.json')) {
      reloadAnimators(path);
    } else if (lower.endsWith('.timeline.json')) {
      reloadTimelines(path);
    } else if (lower.endsWith('.tileset.json') ||
        LevelMapFiles.isMapFile(lower) ||
        lower.endsWith('.tmx') ||
        lower.endsWith('.tmj') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.tsj')) {
      reloadLevelMaps(path);
    } else if (PrefabFile.isPrefabPath(lower)) {
      _refreshPrefab(path);
    } else if (JustGameEditorPlugin.isSpriteAtlasPath(path, scope: scope)) {
      reloadSprites(path);
    } else if (lower.endsWith('.json')) {
      // Some other data file: nothing a sprite shows.
    } else if (!JustGameEditorPlugin._isFont(lower) &&
        !JustGameEditorPlugin._isAudio(lower)) {
      reloadSprites();
    }
    // After the sprites: a material reads its maps through the sprite
    // loader, whose cache now has the new picture.
    _reloadMaterials(path);
    // And whatever a module shows from it — a theme, a font, a screen —
    // the editor's own built-in modules (its materials) among them.
    for (final module in scope.modules.withBuiltIns) {
      module.onAssetChanged(path);
    }
  }

  // The engine's materials: a changed one — or a map, a layer or a normal
  // map one uses — read again, 2-D (its variants follow) and 3-D, with the
  // 3-D shapes' textures and the skybox. Each is drawn again once read; a
  // path nothing uses is passed over.
  void _reloadMaterials(String path) {
    engine.context.material2DLibrary.reload(path);
    if (!engine.isInitialized) return;
    final graphics = engine.services.maybe<g3.Graphics3D>();
    if (graphics != null && graphics.isStarted) {
      graphics.sceneRenderer.reload(path);
    }
  }

  /// An animator graph changed on disk: animators running it start over
  /// with the new one.
  @internal
  void reloadAnimators([String? graphPath]) {
    for (final system in engine.world.systems) {
      if (system is AnimatorSystem) system.reload(graphPath);
    }
  }

  /// A tileset or map file changed on disk: every map using it reads it
  /// again. A Tiled `.tsx` could belong to any `.tmx`, so it reloads all.
  @internal
  void reloadLevelMaps([String? path]) {
    final lower = path?.toLowerCase() ?? '';
    final all =
        path == null || lower.endsWith('.tsx') || lower.endsWith('.tsj');
    // A map file being edited here is the document: re-reading it would
    // throw the edits away. It is written by a save, not read back.
    if (!all && scope.mapDocs.dirtyPaths.value.contains(path)) return;
    for (final system in engine.world.systems) {
      if (system is LevelMapSystem) system.reload(all ? null : path);
    }
    // A tileset's images may have changed with it.
    if (all || lower.endsWith('.tileset.json')) spriteAssets.clear();
  }

  /// A timeline changed on disk: players of it start over with the new one.
  @internal
  void reloadTimelines([String? timelinePath]) {
    for (final system in engine.world.systems) {
      if (system is TimelineSystem) system.reload(timelinePath);
    }
  }
}
