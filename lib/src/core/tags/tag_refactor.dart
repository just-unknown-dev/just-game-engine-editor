/// Renaming and deleting a tag everywhere the project uses it.
library;

import 'dart:convert';

import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

import '../prefabs/prefab_rewrites.dart';

/// What a rename or a delete would change, listed before anything does.
class TagChangePlan {
  const TagChangePlan({
    required this.tag,
    required this.renameTo,
    required this.openScene,
    required this.openUses,
    required this.scenes,
    required this.prefabs,
    required this.timelines,
    this.unreadable = const [],
  });

  final String tag;

  /// The new name; null for a delete.
  final String? renameTo;

  bool get isRename => renameTo != null;

  /// The scene being edited, whose changes go on the undo stack instead of
  /// straight to its file. Null when none is open.
  final String? openScene;
  final List<TagUse> openUses;

  /// Every other scene that uses the tag, by name — instances of prefabs
  /// included, for what they change.
  final Map<String, List<TagUse>> scenes;

  /// Every prefab file (`*.prefab.json`) that uses it, by project-relative
  /// path: what every instance of it carries.
  final Map<String, List<TagUse>> prefabs;

  /// Every timeline file that binds a track to it, by path.
  final Map<String, List<TagUse>> timelines;

  /// Scenes whose files could not be read: nothing in them is listed, and
  /// nothing in them changes — they keep the old tag. Said, not skipped.
  final List<String> unreadable;

  /// Every use, wherever it is.
  Iterable<TagUse> get all => [
    ...openUses,
    for (final uses in scenes.values) ...uses,
    for (final uses in prefabs.values) ...uses,
    for (final uses in timelines.values) ...uses,
  ];

  /// What a delete takes off entities; the rest stays, pointing at a tag
  /// nothing carries, for the Problems dock to list.
  Iterable<TagUse> get carried =>
      all.where((u) => u.kind == TagUseKind.carried);

  Iterable<TagUse> get references =>
      all.where((u) => u.kind == TagUseKind.reference);

  /// The files this would write: closed scenes and prefabs, and timelines
  /// on a rename.
  int get fileCount =>
      (isRename
          ? scenes.length + prefabs.length
          : [
              ...scenes.values,
              ...prefabs.values,
            ].where((u) => u.any((x) => x.kind == TagUseKind.carried)).length) +
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

  /// Scene, prefab and timeline files rewritten.
  final List<String> filesWritten;

  /// Files that could not be read or written, and why.
  final Map<String, String> failures;
}

/// Renames a tag — or deletes it — in every scene, prefab and timeline of
/// the project, and in the tag list.
///
/// * **Prefab files** are rewritten on disk first, each backed up (to
///   `.editor_backups/.prefabs/`), and the open scene's instances of them
///   made again from them — so an instance carries the new name from its
///   prefab rather than as a change of its own.
/// * The **open scene** changes through the undo stack, as one step, and is
///   saved when you save it.
/// * **Other scenes** are rewritten on disk, each backed up first (to
///   `.editor_backups/`, like an autosave) — what their instances of
///   prefabs change included.
/// * **Timelines** have their track bindings renamed on disk.
///
/// A delete takes the tag off every entity and out of the list; fields and
/// bindings that name it are left for the Problems dock to point at, rather
/// than silently emptied. When a file cannot be rewritten, the tag list
/// keeps the old name, which that file still uses.
class TagRefactor {
  TagRefactor(this.scope, {String? projectRoot})
    : root = (projectRoot ?? Directory.current.path).replaceAll(r'\', '/');

  final EditorScope scope;

  /// The project: where `assets/` is.
  final String root;

  TagReferences get _references => scope.tagReferences;

  late final PrefabRewrites _prefabs = PrefabRewrites(scope, root: root);

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
    final unreadable = <String>[];
    for (final name in scope.scenes.listSceneNames()) {
      if (name == open) continue;
      try {
        // Listed from the files on disk: null is a file that is not a
        // scene, not one that is missing.
        final raw = scope.scenes.readRawSync(name);
        if (raw == null) {
          unreadable.add(name);
          continue;
        }
        final uses = _references.inScene(
          jge.SceneFormat.migrate(raw, hooks: scope.context.migrations),
          tag: tag,
        );
        if (uses.isNotEmpty) scenes[name] = uses;
      } on Object {
        unreadable.add(name);
      }
    }
    final prefabs = <String, List<TagUse>>{};
    for (final path in _prefabs.files()) {
      final List<TagUse> uses;
      try {
        uses = _references.inScene(_prefabs.read(path).json, tag: tag);
      } on Object {
        continue;
      }
      if (uses.isNotEmpty) prefabs[path] = uses;
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
      prefabs: prefabs,
      timelines: timelines,
      unreadable: unreadable,
    );
  }

  /// Carries [plan] out — not during a play-test: the open scene is the
  /// running game then, and Stop would put the old tag back on it while
  /// every other file had the new one. Nothing changes, and that is said.
  ///
  /// Refused too, with nothing changed, while the tag file cannot be read:
  /// the list could not follow, and the files would name a tag it lacks.
  Future<TagChangeResult> apply(TagChangePlan plan) async {
    final from = plan.tag;
    final to = plan.renameTo;
    final written = <String>[];
    final failures = <String, String>{};

    if (scope.isPlayTesting.value) {
      const why = 'Stop the play-test first: nothing was changed.';
      scope.log.log(
        '${to == null ? 'Did not delete' : 'Did not rename'} the tag "$from": '
        '$why',
        source: 'editor',
        category: 'tags',
        level: DebuggerLogLevel.warning,
      );
      return const TagChangeResult(
        openChanges: 0,
        filesWritten: [],
        failures: {'play-test': why},
      );
    }

    if (scope.tags.isUnreadable) {
      final why = scope.tags.loadError ?? 'The tag file cannot be read.';
      scope.log.log(
        'The tag "$from" was not ${to == null ? 'deleted' : 'renamed'}: '
        '$why',
        source: 'editor',
        category: 'tags',
        level: DebuggerLogLevel.warning,
      );
      return TagChangeResult(
        openChanges: 0,
        filesWritten: const [],
        failures: {scope.tags.path: why},
      );
    }
    for (final name in plan.unreadable) {
      failures[name] = 'could not be read, so it keeps the tag "$from"';
    }

    // The prefabs first, and the open scene's instances of them made again
    // from them: an instance then carries the new name from its prefab, and
    // the open scene's own change below finds nothing left to do there.
    final prefabsWritten = <String>[];
    for (final path in plan.prefabs.keys) {
      try {
        final (:json, :before) = _prefabs.read(path);
        final changed = to == null
            ? _references.removeFromScene(json, from)
            : _references.renameInScene(json, from, to);
        if (changed == 0) continue;
        await _prefabs.write(path, json, before: before);
        prefabsWritten.add(path);
      } on Object catch (e) {
        failures[path] = '$e';
      }
    }
    written.addAll(prefabsWritten);
    try {
      await _prefabs.refresh(prefabsWritten);
    } on Object catch (e) {
      failures['the open scene\'s prefab instances'] = '$e';
    }

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
          final file = File('$root/$path');
          final text = file.readAsStringSync();
          final json = _decode(text);
          if (json == null) {
            failures[path] = 'could not be read';
            continue;
          }
          if (_references.renameInTimeline(json, from, to) == 0) continue;
          // The version replaced kept first, as the scenes are; then
          // written whole or not at all, in the line endings it had.
          await ProjectFiles.writeString(
            '$root/$timelineBackups/${_stamp()}-'
            '${path.substring(path.lastIndexOf('/') + 1)}',
            text,
          );
          var out = '${const JsonEncoder.withIndent('  ').convert(json)}\n';
          if (text.contains('\r\n')) out = out.replaceAll('\n', '\r\n');
          await ProjectFiles.writeString(file.path, out);
          written.add(path);
          // The editor's own modules too (its materials, its timelines).
          for (final module in scope.modules.withBuiltIns) {
            module.onAssetChanged(path);
          }
        } on Object catch (e) {
          failures[path] = '$e';
        }
      }
    }

    // A file that could not be rewritten still uses the old name, so the
    // list keeps it — beside the new one, on a rename.
    if (failures.isNotEmpty) {
      if (to != null) scope.tags.adopt([to]);
    } else if (!(to == null
        ? scope.tags.remove(from)
        : scope.tags.rename(from, to))) {
      if (scope.tags.writeError case final error?) {
        failures[scope.tags.path] = error;
      }
    }
    scope.log.log(
      failures.isNotEmpty
          ? '${to == null ? 'Deleting' : 'Renaming'} the tag "$from" could '
                'not change ${failures.length} files, which still name it; '
                '${written.length} files rewritten.'
          : to == null
          ? 'Deleted the tag "$from": ${plan.carried.length} entities no '
                'longer carry it; ${written.length} files rewritten.'
          : 'Renamed the tag "$from" to "$to" in ${plan.all.length} places; '
                '${written.length} files rewritten.',
      source: 'editor',
      category: 'tags',
      level: failures.isEmpty
          ? DebuggerLogLevel.info
          : DebuggerLogLevel.warning,
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
              entity: entity,
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
      return _decode(File(path).readAsStringSync());
    } on Object {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// Where a timeline a rename rewrites is kept first, in the project
  /// (never under `assets/`, which ships).
  static const String timelineBackups = '.editor_backups/timelines';

  static String _stamp() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }
}
