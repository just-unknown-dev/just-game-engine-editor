/// Renaming and deleting a tag everywhere the project uses it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// What a rename or a delete would change, listed before anything does.
class TagChangePlan {
  const TagChangePlan({
    required this.tag,
    required this.renameTo,
    required this.openScene,
    required this.openUses,
    required this.scenes,
    required this.timelines,
  });

  final String tag;

  /// The new name; null for a delete.
  final String? renameTo;

  bool get isRename => renameTo != null;

  /// The scene being edited, whose changes go on the undo stack instead of
  /// straight to its file. Null when none is open.
  final String? openScene;
  final List<TagUse> openUses;

  /// Every other scene that uses the tag, by name.
  final Map<String, List<TagUse>> scenes;

  /// Every timeline file that binds a track to it, by path.
  final Map<String, List<TagUse>> timelines;

  /// Every use, wherever it is.
  Iterable<TagUse> get all => [
    ...openUses,
    for (final uses in scenes.values) ...uses,
    for (final uses in timelines.values) ...uses,
  ];

  /// What a delete takes off entities; the rest stays, pointing at a tag
  /// nothing carries, for the Problems dock to list.
  Iterable<TagUse> get carried =>
      all.where((u) => u.kind == TagUseKind.carried);

  Iterable<TagUse> get references =>
      all.where((u) => u.kind == TagUseKind.reference);

  /// The files this would write: closed scenes, and timelines on a rename.
  int get fileCount =>
      (isRename
          ? scenes.length
          : scenes.values
                .where((u) => u.any((x) => x.kind == TagUseKind.carried))
                .length) +
      (isRename ? timelines.length : 0);
}

/// What applying a [TagChangePlan] did.
class TagChangeResult {
  const TagChangeResult({
    required this.openChanges,
    required this.filesWritten,
    required this.failures,
  });

  /// Fields changed in the open scene — one undo step.
  final int openChanges;

  /// Scene and timeline files rewritten.
  final List<String> filesWritten;

  /// Files that could not be read or written, and why.
  final Map<String, String> failures;
}

/// Renames a tag — or deletes it — in every scene and timeline of the
/// project, and in the tag list.
///
/// * The **open scene** changes through the undo stack, as one step, and is
///   saved when you save it.
/// * **Other scenes** are rewritten on disk, each backed up first (to
///   `.editor_backups/`, like an autosave).
/// * **Timelines** have their track bindings renamed on disk.
///
/// A delete takes the tag off every entity and out of the list; fields and
/// bindings that name it are left for the Problems dock to point at, rather
/// than silently emptied.
class TagRefactor {
  TagRefactor(this.scope, {String? projectRoot})
    : root = (projectRoot ?? Directory.current.path).replaceAll(r'\', '/');

  final EditorScope scope;

  /// The project: where `assets/` is.
  final String root;

  TagReferences get _references => scope.tagReferences;

  String? get _openScene => scope.sceneState.activeScene.value?.name;

  /// What renaming [tag] to [renameTo] — or deleting it, without one —
  /// would change.
  TagChangePlan plan(String tag, {String? renameTo}) {
    final open = _openScene;
    final openUses = <TagUse>[];
    if (open != null) {
      for (final entity in scope.world.entities) {
        final owner = entity.name ?? 'Entity ${entity.id}';
        for (final component in entity.components) {
          final json = scope.definitions
              .definitionFor(component)
              ?.encode(component);
          if (json == null) continue;
          openUses.addAll(
            _references
                .inComponent(json, owner: owner)
                .where((u) => u.tag == tag),
          );
        }
      }
    }
    final scenes = <String, List<TagUse>>{};
    for (final name in scope.scenes.listSceneNames()) {
      if (name == open) continue;
      final raw = scope.scenes.readRawSync(name);
      if (raw == null) continue;
      final uses = _references.inScene(
        jge.SceneFormat.migrate(raw, hooks: scope.context.migrations),
        tag: tag,
      );
      if (uses.isNotEmpty) scenes[name] = uses;
    }
    final timelines = <String, List<TagUse>>{};
    for (final path in timelineFiles()) {
      final json = _readJson('$root/$path');
      if (json == null) continue;
      final uses = _references.inTimeline(json, file: path, tag: tag);
      if (uses.isNotEmpty) timelines[path] = uses;
    }
    return TagChangePlan(
      tag: tag,
      renameTo: renameTo,
      openScene: open,
      openUses: openUses,
      scenes: scenes,
      timelines: timelines,
    );
  }

  /// Carries [plan] out.
  Future<TagChangeResult> apply(TagChangePlan plan) async {
    final from = plan.tag;
    final to = plan.renameTo;
    final written = <String>[];
    final failures = <String, String>{};

    final openChanges = _applyToOpenScene(from, to);

    for (final name in plan.scenes.keys) {
      try {
        final raw = scope.scenes.readRawSync(name);
        if (raw == null) continue;
        final before = scope.scenes.encodeRawText(raw);
        final migrated = jge.SceneFormat.migrate(
          raw,
          hooks: scope.context.migrations,
        );
        final changed = to == null
            ? _references.removeFromScene(migrated, from)
            : _references.renameInScene(migrated, from, to);
        if (changed == 0) continue;
        await scope.scenes.writeBackup(name, before, keep: 20);
        await scope.scenes
            .writeSceneJson(name, EditorScene.fromJson(migrated), [
              for (final e in migrated['entities'] as List? ?? const [])
                (e as Map).cast<String, dynamic>(),
            ], editor: (migrated['editor'] as Map?)?.cast<String, dynamic>());
        written.add('${scope.scenes.scenesRoot}/$name.scene.json');
      } on Object catch (e) {
        failures[name] = '$e';
      }
    }

    if (to != null) {
      for (final path in plan.timelines.keys) {
        try {
          final json = _readJson('$root/$path');
          if (json == null) continue;
          if (_references.renameInTimeline(json, from, to) == 0) continue;
          await File('$root/$path').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(json)}\n',
          );
          written.add(path);
          for (final module in scope.modules.all) {
            module.onAssetChanged(path);
          }
        } on Object catch (e) {
          failures[path] = '$e';
        }
      }
    }

    if (to == null) {
      scope.tags.remove(from);
    } else {
      scope.tags.rename(from, to);
    }
    scope.log.log(
      to == null
          ? 'Deleted the tag "$from": ${plan.carried.length} entities no '
                'longer carry it; ${written.length} files rewritten.'
          : 'Renamed the tag "$from" to "$to" in ${plan.all.length} places; '
                '${written.length} files rewritten.',
      source: 'editor',
      category: 'tags',
      details: [
        ...written,
        for (final f in failures.entries) 'FAILED ${f.key}: ${f.value}',
      ].join('\n'),
    );
    return TagChangeResult(
      openChanges: openChanges,
      filesWritten: written,
      failures: failures,
    );
  }

  /// The change in the open world, as one undoable step: each field whose
  /// saved form names the tag is decoded again with the new name.
  int _applyToOpenScene(String from, String? to) {
    if (_openScene == null) return 0;
    final commands = <EditorCommand>[];
    for (final entity in scope.world.entities) {
      for (final component in entity.components) {
        final definition = scope.definitions.definitionFor(component);
        if (definition == null) continue;
        final json = definition.encode(component);
        final copy = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
        final changed = to == null
            ? _references.removeFromComponent(copy, from)
            : _references.renameInComponent(copy, from, to);
        if (changed == 0) continue;
        final was = json['fields'] as Map;
        final now = copy['fields'] as Map;
        for (final field in definition.fields) {
          final write = field.write;
          if (write == null) continue;
          if (jsonEncode(was[field.name]) == jsonEncode(now[field.name])) {
            continue;
          }
          commands.add(
            ComponentFieldCommand(
              label: 'Tag ${field.name}',
              component: component,
              write: (c, v) => write(c, v),
              before: field.kind.decodeAny(was[field.name], field.constraints),
              after: field.kind.decodeAny(now[field.name], field.constraints),
              sceneState: scope.sceneState,
            ),
          );
        }
      }
    }
    if (commands.isEmpty) return 0;
    scope.history.push(
      CompositeCommand(
        label: to == null
            ? 'Delete the tag "$from"'
            : 'Rename the tag "$from" to "$to"',
        commands: commands,
      ),
    );
    return commands.length;
  }

  /// Every timeline file under `assets/`, project-relative.
  List<String> timelineFiles() {
    final dir = Directory('$root/assets');
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.timeline.json'))
          f.path.replaceAll(r'\', '/').substring(root.length + 1),
    ]..sort();
  }

  static Map<String, dynamic>? _readJson(String path) {
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      return json is Map<String, dynamic> ? json : null;
    } on Object {
      return null;
    }
  }
}
