// A project on disk, a folder catalog of real (zipped) items, a scope and a
// pub runner that only records — what the store window's tests stand on.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../support/memory_settings_store.dart';

/// A pub runner that succeeds and records its calls.
class FakePub implements PubRunner {
  final List<String> calls = [];

  @override
  Future<PubResult> get(String projectRoot, {bool offline = false}) async {
    calls.add('get');
    return const PubResult(0, 'Got dependencies!', '');
  }
}

/// A fresh folder, deleted after the test.
Directory tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// An editor scope over a bare world, with settings in memory, disposed
/// with the test.
EditorScope storeScope() {
  final scope = EditorScope(
    world: World()..initialize(),
    settingsStore: MemorySettingsStore(),
  );
  addTearDown(scope.dispose);
  return scope;
}

/// One item for [buildCatalog].
class Item {
  const Item(
    this.id, {
    this.name,
    this.kind = ItemKind.content,
    this.category = 'characters',
    this.versions = const ['1.0.0'],
    this.modules = const [],
    this.summary = '',
    ItemStage? stage,
    this.replacedBy,
    this.published,
  }) : _stage = stage;

  final ItemStage? _stage;

  /// Its stage: beta for a plugin unless given (every plugin names one).
  ItemStage? get stage => _stage ?? (kind.isPlugin ? ItemStage.beta : null);

  /// What replaces it, when deprecated.
  final String? replacedBy;

  /// When every version was published (`2026-10-01`), when it says.
  final String? published;

  final String id;
  final String? name;
  final ItemKind kind;
  final String category;
  final List<String> versions;
  final List<String> modules;
  final String summary;
}

/// A folder catalog of [items] in [dir], each version a real archive.
SourceConfig buildCatalog(Directory dir, List<Item> items) {
  final out = <Map<String, Object?>>[];
  for (final item in items) {
    final versions = <Map<String, Object?>>[];
    for (final v in item.versions) {
      final zip = ZipWriter();
      final content = item.kind == ItemKind.content;
      zip
        ..add(
          'pubspec.yaml',
          utf8.encode(
            'name: ${item.id}\nversion: $v\n'
            '${content ? 'flutter:\n  assets:\n    - sprites/\n' : ''}',
          ),
        )
        ..add(
          ItemManifest.fileName,
          utf8.encode(
            jsonEncode({
              'schema': 1,
              'id': item.id,
              'name': item.name ?? item.id,
              'version': v,
              'kind': item.kind.id,
              'category': item.category,
              'stage': ?item.stage?.id,
              'replacedBy': ?item.replacedBy,
              if (content)
                'content': {
                  'assetFolders': ['sprites/'],
                },
              if (item.modules.isNotEmpty)
                'editor': {
                  'modules': [
                    for (final m in item.modules)
                      {'library': 'package:${item.id}/editor.dart', 'class': m},
                  ],
                },
            }),
          ),
        );
      if (content) {
        zip.add('sprites/${item.id}.png', utf8.encode('png $v'));
      } else {
        zip.add('lib/editor.dart', utf8.encode('// ${item.id}'));
      }
      final bytes = zip.close();
      final name = 'archives/${item.id}-$v.zip';
      File('${dir.path}/$name')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      versions.add({
        'version': v,
        'published': ?item.published,
        'archive': {
          'url': name,
          'sha256': Sha256.hexOf(bytes),
          'size': bytes.length,
        },
        'stage': ?item.stage?.id,
        'replacedBy': ?item.replacedBy,
      });
    }
    out.add({
      'id': item.id,
      'name': item.name ?? item.id,
      'kind': item.kind.id,
      'category': item.category,
      'summary': item.summary,
      'author': {'name': 'Tester'},
      'license': {'spdx': 'CC0-1.0'},
      // The store's own items, as a catalog in a folder here may say.
      'trust': 'official',
      'versions': versions,
    });
  }
  File('${dir.path}/index.json').writeAsStringSync(
    jsonEncode({
      'schema': 1,
      'source': {'id': 'test', 'name': 'Test catalog'},
      'categories': [
        {'id': 'characters', 'label': 'Characters', 'order': 10},
        {'id': 'editors', 'label': 'Editor tools', 'order': 20},
      ],
      'items': out,
    }),
  );
  return SourceConfig(dir.path, name: 'Test catalog');
}

/// The standard little catalog: two characters and an editor tool.
SourceConfig standardCatalog() => buildCatalog(tempDir('catalog'), const [
  Item(
    'just_art_knight',
    name: 'Knight',
    versions: ['1.0.0', '1.1.0'],
    summary: 'A pixel knight',
  ),
  Item('just_art_slime', name: 'Slime'),
  Item(
    'just_tool',
    name: 'Handy Tool',
    kind: ItemKind.editorExtension,
    category: 'editors',
    modules: ['HandyModule'],
  ),
]);

/// A Just Game Engine project folder with a pubspec: the store generates
/// its registry files only where the engine and the editor are.
Directory projectDir() {
  final dir = tempDir('project');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(
    'name: app\npublish_to: none\nenvironment:\n  sdk: ^3.0.0\n'
    'dependencies:\n  just_game_engine: any\n'
    'dev_dependencies:\n  just_game_engine_editor: any\n',
  );
  return dir;
}
