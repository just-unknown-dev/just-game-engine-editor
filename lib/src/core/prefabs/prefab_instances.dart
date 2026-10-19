import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

import '../scope/editor_scope_services.dart';

/// What the editor does with prefab files (`*.prefab.json`) and their
/// instances in the open scene: places them, works out what each changes,
/// makes them again when their prefab changes, and writes changes back
/// into the prefab (Apply) — or takes them away (Revert).
///
/// An instance is its top entity (with a [PrefabInstanceComponent]) and the
/// entities it made (each with a [PrefabLink]); entities of the scene's own
/// may sit inside it. What an instance changes is not kept as it is edited
/// but worked out when asked ([changesOf]), as a save does.
final class PrefabInstances {
  /// Prefabs of the project at [root] (the working folder when null), in
  /// [scope]'s scene.
  PrefabInstances(this.scope, {String? root})
    : root = (root ?? Directory.current.path).replaceAll(r'\', '/');

  /// The editor.
  final EditorScope scope;

  /// The project folder prefab paths are under.
  final String root;

  World get world => scope.world;
  EditorSceneState get sceneState => scope.sceneState;

  /// The prefab files the edited engine has read.
  PrefabLibrary get library => PrefabLibrary.of(scope.context);

  /// Where prefabs made from a selection go.
  static const String folder = 'assets/prefabs';

  // ── Reading ─────────────────────────────────────────────────────────────

  /// The top of the instance [entity] belongs to — itself for a top — or
  /// null for an entity of the scene's own.
  static Entity? topOf(Entity entity) {
    if (entity.hasComponent<PrefabInstanceComponent>()) return entity;
    final link = entity.getComponent<PrefabLink>();
    if (link == null) return null;
    final top = entity.world?.getEntity(link.instance);
    return top != null && top.hasComponent<PrefabInstanceComponent>()
        ? top
        : null;
  }

  /// Every instance's top in the scene.
  List<Entity> tops() => [
    for (final e in world.entities)
      if (e.isAlive && e.hasComponent<PrefabInstanceComponent>()) e,
  ];

  /// The entities [top]'s instance made, by their paths in its prefab.
  Map<String, Entity> membersOf(Entity top) => {
    for (final e in world.entities)
      if (e.isAlive)
        if (e.getComponent<PrefabLink>() case final link?
            when link.instance == top.id)
          link.path: e,
  };

  /// [entity] and everything under it, parents first.
  List<Entity> subtreeOf(Entity entity) {
    final out = <Entity>[entity];
    for (var i = 0; i < out.length; i++) {
      for (final id
          in out[i].getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null && child.isAlive) out.add(child);
      }
    }
    return SceneCodec.inTreeOrder(out);
  }

  /// What [top]'s instance changes now — against its prefab, as a save
  /// would write it — and the entries of the scene's own entities inside
  /// it (world placed, under it by `parentTarget`).
  ({PrefabInstance block, List<Map<String, dynamic>> inside}) changesOf(
    Entity top,
  ) {
    final instance = top.getComponent<PrefabInstanceComponent>()!;
    if (instance.missing) return (block: instance.block, inside: const []);
    final collapsed = scope.codec.collapseMarked(
      scope.codec.encodeForSave(subtreeOf(top)),
    );
    final block = collapsed.first['prefab'];
    return (
      block: block is Map ? PrefabInstance.fromJson(block) : instance.block,
      inside: collapsed.skip(1).toList(),
    );
  }

  /// The overrides of [top]'s instance that are not where it was placed:
  /// its top's position, turn and size are where the instance stands, not
  /// changes to the prefab.
  static List<PrefabOverride> changesBeyondPlacement(
    PrefabInstance block,
    String topPath,
  ) => [
    for (final o in block.overrides)
      if (!(o.target == topPath && o.component == 'TransformComponent')) o,
  ];

  /// [top]'s transform where its prefab has it, decoded; null when the
  /// prefab has not been read or has none.
  TransformComponent? homeOf(String path) {
    final saved = PrefabExpander.expand(
      PrefabInstance(path: path),
      library.loaded,
    )?.first.componentOf('TransformComponent');
    final home = saved == null ? null : scope.codec.decode(saved);
    return home is TransformComponent ? home : null;
  }

  // ── Making ──────────────────────────────────────────────────────────────

  /// Makes the entities [entries] — scene entries, instances among them —
  /// make: linked (the batch's roots under [under] when given), marked
  /// where they came from, each instance placed. Returns them in order.
  List<Entity> build(List<Map<String, dynamic>> entries, {Entity? under}) {
    final expanded = PrefabExpander.expandScene(entries, library.loaded);
    final made = List<Entity?>.filled(expanded.length, null);
    for (var i = 0; i < expanded.length; i++) {
      final entry = expanded[i];
      final components = scope.codec.decodeAll(
        entry['components'] as List? ?? const [],
      );
      if (components.isEmpty && entry['prefabRef'] == null) continue;
      final e = world.createEntityWithComponents(
        components,
        name: entry['name'] as String?,
      );
      if (entry['enabled'] == false) e.isActive = false;
      sceneState.registerEntity(e);
      made[i] = e;
    }
    final parents = SceneLoader.parentIndices(expanded);
    for (var i = 0; i < expanded.length; i++) {
      final child = made[i];
      if (child == null) continue;
      final at = parents[i];
      final parent = at == null ? under : made[at];
      if (parent == null) continue;
      _link(child, parent);
      // Placed against its parent from where the file has it, as a scene
      // load places it.
      child.getComponent<ParentComponent>()?.needsLocal = true;
    }
    for (var i = 0; i < expanded.length; i++) {
      final ref = expanded[i]['prefabRef'];
      final entity = made[i];
      if (ref is! Map || entity == null) continue;
      final top = made[ref['instance'] as int];
      if (top == null) continue;
      entity.addComponent(
        PrefabLink(instance: top.id, path: ref['path'] as String),
      );
      if (ref['block'] case final Map block) {
        entity.addComponent(
          PrefabInstanceComponent(
            block: PrefabInstance.fromJson(block),
            missing: ref['missing'] != null,
          ),
        );
      }
    }
    for (var i = 0; i < expanded.length; i++) {
      final ref = expanded[i]['prefabRef'];
      final top = made[i];
      if (ref is! Map || ref['instance'] != i || top == null) continue;
      if (ref['home'] case final Map home) {
        final at = scope.codec.decode(home.cast<String, dynamic>());
        if (at is TransformComponent) SceneLoader.placeFromHome(world, top, at);
      }
    }
    final out = [for (final e in made) ?e];
    for (final e in out) {
      if (e.getComponent<ParentComponent>()?.parentId == null ||
          e.getComponent<ParentComponent>()?.parentId == under?.id) {
        world.transformHierarchy.propagateFrom(e);
      }
    }
    sceneState
      ..markDirty()
      ..refresh();
    return out;
  }

  void _link(Entity child, Entity parent) => placeEntity(
    child,
    world: world,
    sceneState: sceneState,
    slot: HierarchySlot(parentId: parent.id, index: -1),
  );

  /// The scene entry of an instance of the prefab at [path] named [name],
  /// its top at [at] — turned by [turn] and sized by [size] on top of how
  /// the prefab has it — when given.
  Map<String, dynamic> entryFor(
    String path, {
    required String name,
    Vector3? at,
    Quaternion? turn,
    double size = 1,
  }) {
    final home = homeOf(path);
    final overrides = <Map<String, dynamic>>[];
    if (home != null && (at != null || turn != null || size != 1)) {
      final placed = TransformComponent(
        position: Vector3.copy(at ?? home.position),
        scale: Vector3.copy(home.scale),
      );
      final own = Quaternion.identity();
      home.rotationInto(own);
      placed.setRotation(
        turn == null ? own : (Quaternion.copy(turn)..multiply(own)),
      );
      placed.scale.scale(size);
      final before = scope.codec.encode(home)?['fields'] as Map? ?? const {};
      final after = scope.codec.encode(placed)?['fields'] as Map? ?? const {};
      final topId = library.loaded(path)?.root.id ?? '';
      for (final key in const ['position', 'rotation', 'scale']) {
        if (after[key] != null && '${after[key]}' != '${before[key]}') {
          overrides.add({
            'target': topId,
            'component': 'TransformComponent',
            'field': key,
            'value': after[key],
          });
        }
      }
    }
    return {
      'name': name,
      'prefab': {
        'path': path,
        if (overrides.isNotEmpty) 'overrides': overrides,
      },
    };
  }

  /// Places an instance of the loaded prefab at [path] (see [entryFor]) —
  /// under [under] when given — selected, as one undo step. Its top.
  Entity? place(
    String path, {
    Vector3? at,
    Quaternion? turn,
    double size = 1,
    Entity? under,
  }) {
    final file = library.loaded(path);
    if (file == null) return null;
    final entry = entryFor(
      path,
      name: scope.entities.uniqueName(file.name),
      at: at,
      turn: turn,
      size: size,
    );
    var made = <Entity>[];
    final underId = under?.id;
    scope.history.push(
      CallbackCommand(
        label: 'Place ${file.name}',
        onRedo: () {
          made = build([
            entry,
          ], under: underId == null ? null : world.getEntity(underId));
          if (made.isNotEmpty) sceneState.selectEntity(made.first);
        },
        onUndo: () => _remove(made),
      ),
    );
    return made.isEmpty ? null : made.first;
  }

  // Takes [entities] out of the scene, children before parents.
  void _remove(List<Entity> entities) {
    for (final e in entities.reversed) {
      if (!e.isAlive) continue;
      detachEntity(e, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(e.id);
      world.destroyEntity(e);
    }
    sceneState
      ..clearSelection()
      ..markDirty()
      ..refresh();
  }

  // ── Making again ────────────────────────────────────────────────────────

  /// Makes [top]'s instance again from its prefab as [block] changes it —
  /// in place: an entity it still makes keeps its identity, one it no
  /// longer makes goes (what the scene put under it moving to the top), a
  /// new one is made. The top stays where it stands.
  void rebuild(Entity top, PrefabInstance block) {
    final instance = top.getComponent<PrefabInstanceComponent>();
    final nodes = PrefabExpander.expand(block, library.loaded);
    if (instance == null || nodes == null || nodes.isEmpty) return;
    if (instance.missing) {
      top.addComponent(PrefabInstanceComponent(block: block));
    } else {
      instance.block = block;
    }
    final members = membersOf(top)..removeWhere((_, e) => identical(e, top));
    final byPath = <String, Entity>{};
    final placement = scope.codec.encode(
      top.getComponent<TransformComponent>() ?? TransformComponent(),
    );
    for (final node in nodes) {
      final isTop = node.parent == null;
      // The top keeps where it stands.
      final json = isTop
          ? [
              for (final c in node.components)
                if (c['type'] == 'TransformComponent') ?placement else c,
            ]
          : node.components;
      var e = isTop ? top : members.remove(node.path);
      if (e == null) {
        e = world.createEntityWithComponents(
          scope.codec.decodeAll(json),
          name: node.name,
        )..addComponent(PrefabLink(instance: top.id, path: node.path));
        sceneState.registerEntity(e);
      } else {
        EntitySpec(
          name: isTop ? top.name : node.name,
          componentsJson: json,
          codec: scope.codec,
        ).applyTo(e);
      }
      if (isTop) {
        e.getComponent<PrefabLink>() ??
            e.addComponent(PrefabLink(instance: top.id, path: node.path));
      } else {
        e.isActive = node.enabled;
        final parent = byPath[node.parent];
        if (parent != null &&
            e.getComponent<ParentComponent>()?.parentId != parent.id) {
          _link(e, parent);
        }
        e.getComponent<ParentComponent>()?.needsLocal = true;
      }
      byPath[node.path] = e;
    }
    // What it no longer makes goes; what the scene put under that moves to
    // the top.
    final gone = members.values.toSet();
    for (final e in gone) {
      for (final id in [...?e.getComponent<ChildrenComponent>()?.childIds]) {
        final child = world.getEntity(id);
        if (child != null && !gone.contains(child)) _link(child, top);
      }
    }
    _remove(SceneCodec.inTreeOrder(gone.toList()));
    final home = homeOf(block.path);
    if (home != null) {
      SceneLoader.placeFromHome(world, top, home);
    } else {
      world.transformHierarchy.propagateFrom(top);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  /// After the prefab at [path] changed on disk: reads it again and makes
  /// every instance that uses it — itself, or a prefab nested in it —
  /// again, each keeping what it changes ([blocks] when given for one).
  /// Instances of other prefabs are left as they are.
  ///
  /// The new file is read before the old one is let go of: one that cannot
  /// be read (caught half-written, say) leaves the instances, and what they
  /// change, as they were.
  Future<void> refresh(
    String path, {
    Map<Entity, PrefabInstance> blocks = const {},
  }) async {
    try {
      // Read once to see it parses; the library reads it again below.
      await scope.context.prefabs(path);
    } on Object catch (error) {
      scope.log.log(
        'Could not read the prefab $path: $error — its instances are kept '
        'as they were.',
        source: 'editor',
        category: 'prefab',
      );
      return;
    }
    final before = <Entity, PrefabInstance>{
      for (final top in tops())
        if (_uses(top.getComponent<PrefabInstanceComponent>()!.path, path))
          top: blocks[top] ?? changesOf(top).block,
    };
    library.reload(path);
    try {
      await library.load(path);
    } on Object catch (error) {
      scope.log.log(
        'Could not read the prefab $path: $error',
        source: 'editor',
        category: 'prefab',
      );
      return;
    }
    for (final MapEntry(key: top, value: block) in before.entries) {
      if (top.isAlive) rebuild(top, block);
    }
  }

  /// Whether an instance of the prefab at [prefab] is made from [path]:
  /// it is that prefab, or one nested in it (at any depth) is.
  bool _uses(String prefab, String path, [Set<String>? seen]) {
    if (prefab == path) return true;
    final visited = seen ?? <String>{};
    if (!visited.add(prefab)) return false;
    final file = library.loaded(prefab);
    if (file == null) return false;
    for (final nested in PrefabExpander.pathsInPrefab(file)) {
      if (_uses(nested, path, visited)) return true;
    }
    return false;
  }

  // ── Revert and Apply ────────────────────────────────────────────────────

  /// Takes back everything [top]'s instance changes but where it stands,
  /// as one undo step.
  void revertAll(Entity top) {
    final instance = top.getComponent<PrefabInstanceComponent>();
    if (instance == null || instance.missing) return;
    final before = changesOf(top).block;
    final topPath = library.loaded(instance.path)?.root.id ?? '';
    final after = PrefabInstance(
      path: instance.path,
      overrides: [
        for (final o in before.overrides)
          if (o.target == topPath && o.component == 'TransformComponent') o,
      ],
    );
    scope.history.push(
      CallbackCommand(
        label: 'Revert ${top.name ?? 'instance'} to its prefab',
        onRedo: () => rebuild(top, after),
        onUndo: () => rebuild(top, before),
      ),
    );
  }

  /// Takes back one change of [top]'s instance: [field] of [component] on
  /// the entity at [target]; one undo step.
  void revertField(Entity top, String target, String component, String field) {
    final before = changesOf(top).block;
    final after = PrefabInstance(
      path: before.path,
      overrides: [
        for (final o in before.overrides)
          if (!(o.target == target &&
              o.component == component &&
              o.field == field))
            o,
      ],
      removed: before.removed,
      addedComponents: before.addedComponents,
      removedComponents: before.removedComponents,
      names: before.names,
      enabled: before.enabled,
    );
    scope.history.push(
      CallbackCommand(
        label: 'Revert $field to the prefab',
        onRedo: () => rebuild(top, after),
        onUndo: () => rebuild(top, before),
      ),
    );
  }

  /// Writes what [top]'s instance changes — but where it stands — into its
  /// prefab, with the scene's own entities inside it joining the prefab;
  /// then makes every instance again. [only] limits it to one field
  /// (`target`, `component`, `field`). Whether it went through. A file
  /// written is not undone.
  Future<bool> apply(Entity top, {(String, String, String)? only}) async {
    final instance = top.getComponent<PrefabInstanceComponent>();
    if (instance == null || instance.missing) return false;
    final file = library.loaded(instance.path);
    if (file == null) return false;
    final (:block, :inside) = changesOf(top);
    final topPath = file.root.id;
    final changes = only == null
        ? PrefabInstance(
            path: block.path,
            overrides: changesBeyondPlacement(block, topPath),
            removed: block.removed,
            addedComponents: block.addedComponents,
            removedComponents: block.removedComponents,
            names: block.names,
            enabled: block.enabled,
          )
        : PrefabInstance(
            path: block.path,
            overrides: [
              for (final o in block.overrides)
                if (o.target == only.$1 &&
                    o.component == only.$2 &&
                    o.field == only.$3)
                  o,
            ],
          );
    // The scene's own entities inside it, in the prefab's space.
    final joining = only == null ? _insideEntities(top) : const <Entity>[];
    final added = joining.isEmpty
        ? const <PrefabEntity>[]
        : _asPrefabEntities(top, joining, file);
    final next = PrefabApply.apply(
      file,
      changes,
      added: added,
      resolve: library.loaded,
    );
    try {
      await _writePrefab(instance.path, next.encode());
    } on Object catch (error) {
      scope.log.log(
        'Could not write ${instance.path}: $error',
        source: 'editor',
        category: 'prefab',
      );
      return false;
    }
    // What joined the prefab comes back as part of every instance.
    if (added.isNotEmpty) _remove(SceneCodec.inTreeOrder(joining));
    final placed = PrefabInstance(
      path: block.path,
      overrides: [
        for (final o in block.overrides)
          if (o.target == topPath && o.component == 'TransformComponent') o,
      ],
    );
    await refresh(instance.path, blocks: {if (only == null) top: placed});
    return true;
  }

  /// Where the version of a prefab file that Apply replaces is kept: in
  /// the project, never under `assets/`, which ships.
  static const String backupFolder = '.editor_backups/prefabs';

  /// Writes [text] as the prefab file [path] — whole or not at all, the
  /// version it replaces kept in [backupFolder] first. A path read out of a
  /// scene that leaves the project, or a package that cannot be written,
  /// is refused.
  Future<void> _writePrefab(String path, String text) async {
    final paths = PackageAssetPaths.of(root);
    if (!ProjectFiles.isContained(path) || !paths.isWritable(path)) {
      throw FileSystemException(
        'Not a prefab file this project can write',
        path,
      );
    }
    final file = paths.file(path);
    if (await file.exists()) {
      final t = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${t.year}${two(t.month)}${two(t.day)}-'
          '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
          '${t.millisecond.toString().padLeft(3, '0')}';
      final name = path.substring(path.lastIndexOf('/') + 1);
      await ProjectFiles.writeBytes(
        '$root/$backupFolder/$stamp-$name',
        await file.readAsBytes(),
      );
    }
    await ProjectFiles.writeString(file.path, text);
  }

  // The scene's own entities under entities of [top]'s instance — those
  // directly under one the prefab makes at its top level, and theirs.
  List<Entity> _insideEntities(Entity top) {
    final out = <Entity>[];
    for (final e in subtreeOf(top)) {
      if (e.hasComponent<PrefabLink>() ||
          e.hasComponent<PrefabInstanceComponent>()) {
        continue;
      }
      out.add(e);
    }
    return out;
  }

  // [entities] — the scene's own, inside [top]'s instance — as entities of
  // [file], placed in its space: as though [top] stood where [file] has it.
  List<PrefabEntity> _asPrefabEntities(
    Entity top,
    List<Entity> entities,
    PrefabFile file,
  ) {
    final home = homeOf(top.getComponent<PrefabInstanceComponent>()!.path);
    final t = top.getComponent<TransformComponent>();
    TransformSnapshot? was;
    if (home != null && t != null) {
      world.transformHierarchy.propagateFrom(top);
      was = TransformSnapshot.of(top);
      final turn = Quaternion.identity();
      home.rotationInto(turn);
      t
        ..position.setFrom(home.position)
        ..scale.setFrom(home.scale)
        ..setRotation(turn);
      world.transformHierarchy.propagateFrom(top);
    }
    final ordered = SceneCodec.inTreeOrder(entities);
    final records = scope.codec.encodeInOrder(ordered);
    if (was != null) {
      was.applyTo(top);
      world.transformHierarchy.propagateFrom(top);
    }
    final ids = <EntityId, String>{};
    final taken = <String>{};
    final out = <PrefabEntity>[];
    for (var i = 0; i < ordered.length; i++) {
      final e = ordered[i];
      final id = PrefabApply.newId(file, taken);
      taken.add(id);
      ids[e.id] = id;
      final parentId = e.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : world.getEntity(parentId);
      final link = parent?.getComponent<PrefabLink>();
      final String? parentPrefabId =
          ids[parentId] ??
          (link != null && link.instance == top.id ? link.path : null);
      // Under an entity of a nested prefab: that cannot be one of this
      // file's; it stays in the scene.
      if (parentPrefabId == null || parentPrefabId.contains('/')) continue;
      out.add(
        PrefabEntity(
          id: id,
          name: e.name ?? id,
          parent: parentPrefabId,
          enabled: e.isActive,
          components: [
            for (final c in records[i]['components'] as List)
              if (!PrefabCollapse.links.contains((c as Map)['type']))
                c.cast<String, dynamic>(),
          ],
        ),
      );
    }
    return out;
  }

  // ── Prefab mode ─────────────────────────────────────────────────────────

  /// The instance being edited as its prefab (prefab mode): shown alone,
  /// its changes applied to the prefab when it is left with Apply. Null
  /// when none is.
  final Signal<EntityId?> editing = Signal(null, debugLabel: 'prefabEditing');

  Set<EntityId>? _hiddenBefore;

  /// The instance's top being edited, by identity: its id may be another
  /// entity's once it is gone.
  Entity? _editingTop;

  /// Edits [top]'s instance as its prefab: the rest of the scene hidden,
  /// the instance selected.
  void edit(Entity top) {
    if (!top.hasComponent<PrefabInstanceComponent>()) return;
    if (editing.value != null) leave();
    _hiddenBefore = {...scope.view.hidden.value};
    scope.view.isolate(world, [top.id]);
    _editingTop = top;
    editing.value = top.id;
    sceneState.selectEntity(top);
  }

  /// Leaves prefab mode — with [apply], writing the instance's changes
  /// into its prefab first — and shows the scene again. Whether the apply
  /// (when asked for) went through.
  Future<bool> leave({bool apply = false}) async {
    if (editing.value == null) return true;
    final top = _editingTop;
    var applied = true;
    if (apply) {
      // Gone, or its id now another entity's: nothing of it to apply.
      applied = top != null && top.isAlive && await this.apply(top);
    }
    scope.view.hidden.value = _hiddenBefore ?? <EntityId>{};
    forgetEditing();
    return applied;
  }

  /// Drops prefab mode as it is: nothing applied, and nothing it hid shown
  /// again by id. For a scene being left — its ids are another scene's in
  /// the next.
  void forgetEditing() {
    _hiddenBefore = null;
    _editingTop = null;
    if (editing.value != null) editing.value = null;
  }

  /// Lets go of its signals.
  void dispose() => editing.dispose();

  // ── Unpack and Make ─────────────────────────────────────────────────────

  /// Makes [top]'s instance plain entities of the scene, no longer kept in
  /// step with the prefab; one undo step.
  void unpack(Entity top) {
    final instance = top.getComponent<PrefabInstanceComponent>();
    if (instance == null) return;
    final links = {
      for (final e in membersOf(top).values) e: e.getComponent<PrefabLink>()!,
    };
    scope.history.push(
      CallbackCommand(
        label: 'Unpack ${top.name ?? 'instance'}',
        onRedo: () {
          top.removeComponent<PrefabInstanceComponent>();
          for (final e in links.keys) {
            e.removeComponent<PrefabLink>();
          }
          // What a save writes changed: the instance is plain entities.
          sceneState
            ..markDirty()
            ..refresh();
        },
        onUndo: () {
          top.addComponent(instance);
          for (final MapEntry(key: e, value: link) in links.entries) {
            if (e.isAlive) e.addComponent(link);
          }
          sceneState
            ..markDirty()
            ..refresh();
        },
      ),
    );
  }

  /// Makes a prefab file of [entity] and everything under it — at
  /// [folder], named after it — and puts an instance of it where they
  /// were, as one undo step (the file stays). Its path, or null when
  /// [entity] is part of an instance already.
  Future<String?> makePrefab(Entity entity) async {
    if (topOf(entity) != null) return null;
    final ordered = subtreeOf(entity);
    final entries = scope.codec.collapseMarked(
      scope.codec.encodeForSave(ordered),
    );
    final parents = SceneLoader.parentIndices(entries);
    final rootPosition = Vector3.copy(
      entity.getComponent<TransformComponent>()?.position ?? Vector3.zero(),
    );
    final ids = <String>[];
    final taken = <String>{};
    for (var i = 0; i < entries.length; i++) {
      final id = PrefabApply.newId(null, taken);
      taken.add(id);
      ids.add(id);
    }
    final entities = <PrefabEntity>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final parent = parents[i] == null || i == 0 ? null : ids[parents[i]!];
      if (i != 0 && parent == null) continue;
      final block = entry['prefab'];
      if (block is Map) {
        entities.add(
          PrefabEntity(
            id: ids[i],
            name: entry['name'] as String? ?? ids[i],
            parent: parent,
            enabled: entry['enabled'] != false,
            prefab: _shifted(PrefabInstance.fromJson(block), rootPosition),
          ),
        );
        continue;
      }
      entities.add(
        PrefabEntity(
          id: ids[i],
          name: entry['name'] as String? ?? ids[i],
          parent: parent,
          enabled: entry['enabled'] != false,
          components: [
            for (final c in entry['components'] as List? ?? const [])
              if (!PrefabCollapse.links.contains((c as Map)['type']))
                _shiftedComponent(c.cast<String, dynamic>(), rootPosition),
          ],
        ),
      );
    }
    final name = entity.name ?? 'Prefab';
    final path = await _freePath(name);
    final file = PrefabFile(name: name, entities: entities);
    // A free path ([_freePath]): nothing is replaced, so nothing to keep.
    await ProjectFiles.writeString('$root/$path', file.encode());
    await library.load(path);

    // An instance where they were.
    final specs = [
      for (final e in ordered) EntitySpec.of(e, scope.codec, world: world),
    ];
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final entry = entryFor(path, name: name, at: rootPosition);
    var originals = ordered;
    var made = <Entity>[];
    scope.history.push(
      CallbackCommand(
        label: 'Make prefab $name',
        onRedo: () {
          _remove(originals);
          made = build([
            entry,
          ], under: parentId == null ? null : world.getEntity(parentId));
          if (made.isNotEmpty) sceneState.selectEntity(made.first);
        },
        onUndo: () {
          _remove(made);
          final command = CreateEntitiesCommand(
            label: 'Make prefab $name',
            world: world,
            sceneState: sceneState,
            specs: specs,
            onCreated: (created) => originals = created,
          );
          command.redo();
        },
      ),
    );
    return path;
  }

  // [block] moved by -[by]: its top's position against the new prefab's
  // top, at the origin.
  PrefabInstance _shifted(PrefabInstance block, Vector3 by) {
    final file = library.loaded(block.path);
    final home = homeOf(block.path);
    if (file == null || home == null) return block;
    final topId = file.root.id;
    final overrides = [...block.overrides];
    final at = overrides.indexWhere(
      (o) =>
          o.target == topId &&
          o.component == 'TransformComponent' &&
          o.field == 'position',
    );
    final p = at < 0
        ? home.position
        : Vector3(
            ((overrides[at].value as Map)['x'] as num).toDouble(),
            ((overrides[at].value as Map)['y'] as num).toDouble(),
            ((overrides[at].value as Map)['z'] as num? ?? 0).toDouble(),
          );
    final moved = PrefabOverride(
      target: topId,
      component: 'TransformComponent',
      field: 'position',
      value: {'x': p.x - by.x, 'y': p.y - by.y, 'z': p.z - by.z},
    );
    if (at < 0) {
      overrides.add(moved);
    } else {
      overrides[at] = moved;
    }
    return PrefabInstance(
      path: block.path,
      overrides: overrides,
      removed: block.removed,
      addedComponents: block.addedComponents,
      removedComponents: block.removedComponents,
      names: block.names,
      enabled: block.enabled,
    );
  }

  static Map<String, dynamic> _shiftedComponent(
    Map<String, dynamic> c,
    Vector3 by,
  ) {
    if (c['type'] != 'TransformComponent') return c;
    final fields = c['fields'];
    final position = fields is Map ? fields['position'] : null;
    if (position is! Map) return c;
    return {
      ...c,
      'fields': {
        ...fields as Map<String, dynamic>,
        'position': {
          'x': (position['x'] as num).toDouble() - by.x,
          'y': (position['y'] as num).toDouble() - by.y,
          'z': ((position['z'] as num?) ?? 0).toDouble() - by.z,
        },
      },
    };
  }

  // A path in [folder] named after [name] that no file has yet.
  Future<String> _freePath(String name) async {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').toLowerCase();
    final stem = safe.isEmpty ? 'prefab' : safe;
    for (var n = 1; ; n++) {
      final path = '$folder/$stem${n == 1 ? '' : '_$n'}${PrefabFile.ending}';
      if (!await File('$root/$path').exists()) return path;
    }
  }
}
