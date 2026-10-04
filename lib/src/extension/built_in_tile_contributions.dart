import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/constants/editor_constants.dart';
import '../core/scope/editor_scope.dart';
import '../core/level_map/level_map_documents.dart';
import '../core/level_map/level_map_provision.dart';
import '../core/level_map/tiled_export.dart';
import '../core/level_map/tiled_import.dart';
import '../ui/inspector/component_extras.dart';
import '../ui/level_designer/state/editor_commands.dart';
import '../ui/tileset/built_in_workspaces.dart';
import '../ui/timeline/timeline_dialogs.dart';
import 'editor_contributions.dart';

/// What the editor itself contributes for tile maps, through the seams a
/// module uses: a scene-tree icon and the Tile Map inspector's extras.
abstract final class BuiltInTileContributions {
  /// Where "Move to a file" puts a map.
  static const String mapFolder = 'assets/maps';

  /// What the Assets dock offers for tile files: cut a tileset from an
  /// image, edit a tileset.
  static List<AssetAction> get assetActions => [
    AssetAction(
      id: 'tiles.create_tileset',
      label: 'Create tileset from this image',
      icon: Icons.grid_view,
      order: 40,
      appliesTo: (path, {required isDirectory}) {
        final lower = path.toLowerCase();
        return !isDirectory &&
            lower.endsWith('.png') &&
            !lower.endsWith('.original.png');
      },
      run: (scope, path) =>
          scope.openWorkspace(BuiltInWorkspaces.tileset, path: path),
    ),
    AssetAction(
      id: 'tiles.edit_tileset',
      label: 'Edit tileset',
      icon: Icons.grid_view,
      order: 40,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && path.toLowerCase().endsWith('.tileset.json'),
      run: (scope, path) =>
          scope.openWorkspace(BuiltInWorkspaces.tileset, path: path),
    ),
    AssetAction(
      id: 'tiles.import_scene',
      label: 'Import into this scene',
      icon: Icons.download_outlined,
      order: 40,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && TiledImporter.isTiledMap(path),
      run: (scope, path) => unawaited(importIntoScene(scope, path)),
    ),
    AssetAction(
      id: 'tiles.import_file',
      label: 'Import as a map file',
      icon: Icons.file_download_outlined,
      order: 41,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && TiledImporter.isTiledMap(path),
      run: (scope, path) => unawaited(importAsMapFile(scope, path)),
    ),
    AssetAction(
      id: 'tiles.convert_tileset',
      label: 'Convert to a tileset',
      icon: Icons.grid_view,
      order: 40,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && TiledImporter.isTiledTileset(path),
      run: (scope, path) => unawaited(convertTileset(scope, path)),
    ),
    AssetAction(
      id: 'tiles.export_tmx',
      label: 'Export for Tiled (.tmx)',
      icon: Icons.upload_file_outlined,
      order: 42,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && jge.LevelMapFiles.isMapFile(path),
      run: (scope, path) => unawaited(exportMapFile(scope, path)),
    ),
  ];

  // ── Tiled ────────────────────────────────────────────────────────────────

  /// The project's files, for the importer and exporter.
  static TiledFiles files(EditorScope scope) =>
      TiledFiles(root: scope.mapDocs.projectRoot);

  static void _say(EditorScope scope, String message, {bool failed = false}) =>
      scope.log.log(
        message,
        source: 'tiles',
        level: failed ? DebuggerLogLevel.error : DebuggerLogLevel.info,
      );

  /// Imports the Tiled map at [path] into the open scene with its origin at
  /// [at] (the middle of the view by default): the map kept in the scene
  /// as its Level Map, its objects entities on its layers, its tilesets as
  /// `.tileset.json` files. One undo step. Returns how many entities were
  /// made, the map's included.
  static Future<int> importIntoScene(
    EditorScope scope,
    String path, {
    Offset? at,
    TiledFiles? using,
  }) async {
    if (!scope.sceneState.hasScene) {
      _say(scope, 'Open a scene to import $path into', failed: true);
      return 0;
    }
    try {
      // A scene has one map. With none, the import makes it; an empty one
      // takes the imported map's place; one painted on is kept.
      final existing = jge.LevelMaps.primaryEntity(scope.world);
      final existingMap = existing?.getComponent<jge.LevelMapComponent>();
      final blank =
          existingMap != null &&
          !existingMap.usesFile &&
          existingMap.inline != null &&
          LevelMapProvision.isBlank(existingMap.inline!);
      if (existing != null && !blank) {
        _say(
          scope,
          'The scene already has a map, ${existing.name}, with something on '
          'it: import $path as a map file instead',
          failed: true,
        );
        return 0;
      }
      final importer = TiledImporter(using ?? files(scope));
      final plan = await importer.read(path);
      await importer.writeTilesets(plan);
      final at0 = existing?.getComponent<jge.TransformComponent>()?.position;
      final origin = at0 != null
          ? Offset(at0.x, at0.y)
          : (at ?? scope.mainCamera.position);
      final specs = TiledImporter.entities(
        plan,
        origin: origin,
        codec: scope.codec,
        uniqueName: scope.entities.uniqueName.call,
        mappers: scope.tiledObjectMappers,
        prefabs: scope.prefabs,
        mapName: jge.LevelMaps.primaryName,
      );
      void select(List<jge.Entity> created) {
        final map = existing ?? created.firstOrNull;
        if (map == null) return;
        scope.sceneState.selectEntity(map);
        scope.tiles.selectMap(map);
      }

      if (existing == null) {
        scope.history.push(
          CreateEntitiesCommand(
            label: 'Import ${plan.stem}',
            world: scope.world,
            sceneState: scope.sceneState,
            specs: specs,
            onCreated: select,
          ),
        );
      } else {
        scope.history.push(
          CompositeCommand(
            label: 'Import ${plan.stem}',
            commands: [
              MapSourceCommand(
                label: 'Import ${plan.stem}',
                docs: scope.mapDocs,
                entityId: existing.id,
                before: (path: '', inline: existingMap!.inline!.toJson()),
                after: (path: '', inline: plan.map.toJson()),
              ),
              CreateEntitiesCommand(
                label: 'Import ${plan.stem}',
                world: scope.world,
                sceneState: scope.sceneState,
                specs: specs.skip(1).toList(),
                onCreated: select,
              ),
            ],
          ),
        );
      }
      _report(
        scope,
        'Imported $path: a map and ${specs.length - 1} objects',
        plan,
      );
      return specs.length;
    } catch (e) {
      _say(scope, 'Could not import $path: $e', failed: true);
      return 0;
    }
  }

  /// Converts the Tiled map at [path] into a `.map.json` under
  /// [mapFolder] (and its tilesets); nothing in the scene changes. Returns
  /// the map file, or null.
  static Future<String?> importAsMapFile(
    EditorScope scope,
    String path, {
    TiledFiles? using,
  }) async {
    try {
      final f = using ?? files(scope);
      final importer = TiledImporter(f);
      final plan = await importer.read(path);
      var to = '$mapFolder/${plan.stem}${jge.LevelMapFiles.suffix}';
      for (var n = 2; f.exists(to); n++) {
        to = '$mapFolder/${plan.stem}_$n${jge.LevelMapFiles.suffix}';
      }
      await importer.writeMap(plan, to);
      _report(scope, 'Imported $path as $to', plan);
      return to;
    } catch (e) {
      _say(scope, 'Could not import $path: $e', failed: true);
      return null;
    }
  }

  static void _report(EditorScope scope, String done, TiledImportPlan plan) {
    _say(scope, done);
    for (final w in plan.warnings) {
      scope.log.log(w, source: 'tiles', level: DebuggerLogLevel.warning);
    }
  }

  /// Converts a Tiled tileset to a `.tileset.json`. Returns its path.
  static Future<String?> convertTileset(
    EditorScope scope,
    String path, {
    TiledFiles? using,
  }) async {
    try {
      final to = await TiledImporter(
        using ?? files(scope),
      ).convertTileset(path);
      _say(scope, 'Converted $path to $to');
      return to;
    } catch (e) {
      _say(scope, 'Could not convert $path: $e', failed: true);
      return null;
    }
  }

  /// Writes [map] for Tiled at [to] (`.tmx` or `.tmj`), its tilesets
  /// beside it.
  static Future<List<String>> exportMap(
    EditorScope scope,
    jge.LevelMapData map,
    String to, {
    TiledFiles? using,
  }) async {
    try {
      final tiles = scope.context.tiles;
      final written = await TiledExporter(using ?? files(scope), tiles: tiles)
          .export(
            map,
            to: to,
            tilesetAt: (slot) {
              final path = map.tilesets[slot];
              return path == null ? null : tiles.loadedTileset(path);
            },
          );
      _say(scope, 'Exported $to for Tiled (${written.length} files)');
      return written;
    } catch (e) {
      _say(scope, 'Could not export $to: $e', failed: true);
      return const [];
    }
  }

  /// Exports the `.map.json` at [path] as a `.tmx` beside it.
  static Future<List<String>> exportMapFile(
    EditorScope scope,
    String path, {
    TiledFiles? using,
  }) async {
    try {
      final tiles = scope.context.tiles;
      final map = await tiles.map(path);
      for (final ts in map.tilesets.whereType<String>()) {
        await tiles.tileset(ts);
      }
      final to = '${jge.TileAssets.directoryOf(path)}/${tiledStem(path)}.tmx';
      return await exportMap(scope, map, to, using: using);
    } catch (e) {
      _say(scope, 'Could not export $path: $e', failed: true);
      return const [];
    }
  }

  /// Asks for a name and exports [entity]'s map for Tiled under
  /// [mapFolder].
  static Future<void> exportEntity(
    BuildContext context,
    EditorScope scope,
    jge.Entity entity,
  ) async {
    final target = scope.mapDocs.resolve(entity);
    if (target == null) return;
    final name = await promptTimelineText(
      context,
      title: 'Export for Tiled',
      initial: (entity.name ?? 'map').toLowerCase(),
      hint: 'Saved as $mapFolder/<name>.tmx, tilesets beside it',
    );
    if (name == null || name.trim().isEmpty) return;
    await exportMap(scope, target.data, '$mapFolder/${name.trim()}.tmx');
  }

  static List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'tiles.map',
      order: 50,
      of: (entity) =>
          entity.hasComponent<jge.LevelMapComponent>() ? Icons.grid_on : null,
    ),
  ];

  static List<ComponentEditorExtras> get extras => [
    ComponentEditorExtras(
      type: 'LevelMapComponent',
      summary: (c) {
        final map = c as jge.LevelMapComponent;
        final data = map.usesFile ? map.runtime?.base : map.inline;
        final layers = data?.layers.length ?? 0;
        return [
          '$layers layer${layers == 1 ? '' : 's'}',
          if (map.usesFile) 'in ${map.mapPath}' else 'in the scene',
        ].join(' · ');
      },
      section: (context, component) =>
          _LevelMapSection(component: component as jge.LevelMapComponent),
    ),
  ];

  /// The entity carrying [component], found by identity.
  static jge.Entity? entityOf(EditorScope scope, jge.Component component) {
    for (final e in scope.world.query([jge.LevelMapComponent])) {
      if (identical(e.getComponent<jge.LevelMapComponent>(), component)) {
        return e;
      }
    }
    return null;
  }

  /// Asks for a name and moves [entity]'s map out of the scene into its own
  /// file under [mapFolder]. One undo step.
  static Future<void> extractToFile(
    BuildContext context,
    EditorScope scope,
    jge.Entity entity,
  ) async {
    final name = await promptTimelineText(
      context,
      title: 'Move the map to a file',
      initial: (entity.name ?? 'map').toLowerCase(),
      hint: 'Saved as $mapFolder/<name>${jge.LevelMapFiles.suffix}',
    );
    if (name == null || name.trim().isEmpty) return;
    final path = '$mapFolder/${name.trim()}${jge.LevelMapFiles.suffix}';
    final command = await scope.mapDocs.extractToAsset(entity, path);
    if (command != null) scope.history.pushApplied(command);
    scope.sceneState.refresh();
  }

  /// Brings [entity]'s map file into the scene. One undo step.
  static void keepInScene(EditorScope scope, jge.Entity entity) {
    final command = scope.mapDocs.embed(entity);
    if (command != null) scope.history.pushApplied(command);
    scope.sceneState.refresh();
  }
}

/// Under the Tile Map's fields: what the map holds, and where it is kept.
class _LevelMapSection extends StatelessWidget {
  const _LevelMapSection({required this.component});

  final jge.LevelMapComponent component;

  static final _text = TextStyle(
    color: EditorTheme.textSecondary,
    fontSize: 11,
  );

  @override
  Widget build(BuildContext context) {
    final scope = EditorScopeProvider.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final entity = BuiltInTileContributions.entityOf(scope, component);
    final data = component.usesFile
        ? component.runtime?.base
        : component.inline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data == null)
            Text('Loading…', style: _text)
          else ...[
            Text(
              '${data.orientation.name}, ${data.tileWidth} × ${data.tileHeight} '
              'cells',
              style: _text,
            ),
            for (final layer in data.layers.reversed)
              Text(
                '• ${layer.name}${layer.collides ? '  (collides)' : ''}'
                '${layer.visible ? '' : '  (hidden)'}',
                style: _text,
              ),
            for (final path in data.tilesets.whereType<String>())
              Text('▦ $path', style: _text, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          if (entity != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (component.usesFile)
                  _Button(
                    icon: Icons.move_down,
                    label: 'Keep in the scene',
                    onTap: () =>
                        BuiltInTileContributions.keepInScene(scope, entity),
                  )
                else
                  _Button(
                    icon: Icons.save_as_outlined,
                    label: 'Move to a file…',
                    onTap: () => BuiltInTileContributions.extractToFile(
                      context,
                      scope,
                      entity,
                    ),
                  ),
                _Button(
                  icon: Icons.upload_file_outlined,
                  label: 'Export for Tiled…',
                  onTap: () => BuiltInTileContributions.exportEntity(
                    context,
                    scope,
                    entity,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: EditorTheme.inputBg,
    borderRadius: BorderRadius.circular(4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: EditorTheme.primaryBright),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: EditorTheme.textBright, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
