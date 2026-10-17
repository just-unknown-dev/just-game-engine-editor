import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import '../scope/editor_scope_services.dart';

/// Prefab files (`*.prefab.json`) in the editor's file lists: a kind of
/// asset — dropped on the viewport, an instance of it is placed there —
/// and entries in the Level Designer's palette.
abstract final class PrefabFiles {
  /// Their accent colour.
  static const Color color = Color(0xFF5C9DFF);

  /// Where they are listed in the palette.
  static const String category = 'Prefab files';

  /// The kind of asset they are.
  static const AssetKind kind = AssetKind(
    'prefab',
    'Prefabs',
    icon: Icons.inventory_2_outlined,
    color: color,
    endings: [PrefabFile.ending],
    filterable: true,
    drop: drop,
  );

  /// Places an instance of the prefab [asset] carries where it landed —
  /// on the surface under the pointer in 3-D, under the Level Map in 2-D —
  /// as one undo step, once the file is read (at once when it has been).
  static Entity? drop(AssetDrop asset) {
    final instances = asset.scope.prefabInstances;
    final world = asset.scope.world;
    Entity? place() => instances.place(
      asset.path,
      at: asset.surface?.position ?? asset.at,
      under: asset.surface == null ? LevelMaps.primaryEntity(world) : null,
    );
    if (instances.library.loaded(asset.path) != null) return place();
    instances.library.load(asset.path).then<void>(
      (_) => place(),
      onError: (Object error) {
        asset.scope.log.log(
          'Could not read the prefab ${asset.path}: $error',
          source: 'editor',
          category: 'prefab',
        );
      },
    );
    return null;
  }

  /// The project's prefab files as palette entries: placing one places an
  /// instance ([PrefabDefinition.instanceOf]). Reading them starts here,
  /// so they are ready when placed.
  static List<PrefabDefinition> paletteEntries(EditorScope scope) {
    final library = scope.prefabInstances.library;
    final out = <PrefabDefinition>[];
    for (final entry in scope.assetIndex.entries) {
      if (entry.isDirectory || !PrefabFile.isPrefabPath(entry.path)) continue;
      if (library.loaded(entry.path) == null && library.errorOf(entry.path) == null) {
        library.load(entry.path).ignore();
      }
      final stem = entry.name.substring(0, entry.name.length - PrefabFile.ending.length);
      final name = library.loaded(entry.path)?.name ?? stem;
      out.add(
        PrefabDefinition(
          id: 'file:${entry.path}',
          name: name,
          category: category,
          icon: Icons.inventory_2_outlined,
          color: color,
          description: '${entry.path}: an instance, kept in step with the file',
          namePrefix: name,
          placement: PrefabPlacement.point,
          dimensions: Dimensions.both,
          instanceOf: entry.path,
          build: (_, _) => const [],
        ),
      );
    }
    return out;
  }
}
