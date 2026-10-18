import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// What the Problems dock says about a scene's materials — beyond a file
/// that isn't there, which the editor's own checks say for every file
/// field:
/// - a material whose parents are missing or loop, or with a value out of
///   its range;
/// - a 2-D material of the wrong kind for where it is (a screen material
///   on a sprite, a sprite material on the frame);
/// - a 2-D material on an entity that draws nothing it can go on;
/// - normal maps or glow in a scene with no Scene lighting;
/// - more than one screen material on at once (only one draws);
/// - a Level Map layer, or one of a model's materials, naming a file that
///   isn't there;
/// - an entity's own values for keys its material cannot change.
///
/// Each with a fix where one is clear, as one undo step.
abstract final class MaterialChecks {
  /// Every check.
  static List<SceneValidator> get all => const [materials2D, materials3D];

  /// The 2-D checks: sprites, shapes and tile layers, and the frame.
  static List<SceneProblem> materials2D(ValidationContext context) {
    final world = context.world;
    final scope = context.scope;
    final out = <SceneProblem>[];
    final files = _Files(context);
    final lit = world
        .query(const [Lighting2D])
        .any((e) => e.getComponent<Lighting2D>()!.enabled);
    Entity? needsLight;

    for (final e in world.query(const [Material2D])) {
      final m = e.getComponent<Material2D>()!;
      final path = m.material.trim();
      if (path.isEmpty || !context.fileExists(path)) continue;
      final file = files.resolved2D(path, e, out);
      if (file == null) continue;
      if (file.kind == Material2DKind.screen) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_name(e)} draws with $path, a screen material: it is drawn '
                'over the whole frame, not on a sprite.',
            hint: 'Put it in a Screen material instead.',
            fixes: [
              if (!e.hasComponent<ScreenMaterial>())
                ProblemFix(
                  label: 'Make it the screen material',
                  apply: () => scope.history.push(
                    CompositeCommand(
                      label: 'Use as the screen material',
                      commands: [
                        RemoveComponentCommand(
                          entity: e,
                          component: m,
                          sceneState: scope.sceneState,
                        ),
                        AddComponentCommand(
                          entity: e,
                          component: ScreenMaterial(material: path),
                          sceneState: scope.sceneState,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
        continue;
      }
      if (!e.hasComponent<RenderableComponent>()) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_name(e)} has a 2D material but draws nothing it can go '
                'on: no sprite or shape.',
            fixes: [
              ProblemFix(
                label: 'Remove the 2D material',
                apply: () => scope.history.push(
                  RemoveComponentCommand(
                    entity: e,
                    component: m,
                    sceneState: scope.sceneState,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      if (!lit && (file.isOn('normalMap') || file.isOn('emissive'))) {
        needsLight ??= e;
      }
      out.addAll(_unknown2D(scope, e, m.overrides, m.remove));
    }

    final screens = [
      for (final e in world.query(const [ScreenMaterial]))
        if (e.getComponent<ScreenMaterial>()!.enabled) e,
    ];
    for (final e in screens) {
      final s = e.getComponent<ScreenMaterial>()!;
      final path = s.material.trim();
      if (path.isEmpty || !context.fileExists(path)) continue;
      final file = files.resolved2D(path, e, out);
      if (file != null && file.kind == Material2DKind.sprite) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_name(e)}: $path is a sprite material; a screen material '
                'draws only the effects that work on the whole frame.',
            hint: 'Pick a screen material (New screen material in a folder).',
          ),
        );
      }
      out.addAll(_unknown2D(scope, e, s.overrides, s.remove));
    }
    if (screens.length > 1) {
      final top = screens.reduce(
        (a, b) =>
            a.getComponent<ScreenMaterial>()!.order >=
                b.getComponent<ScreenMaterial>()!.order
            ? a
            : b,
      );
      for (final e in screens) {
        if (identical(e, top)) continue;
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_name(e)}: only one screen material is drawn — the one of '
                'the highest order, on ${_name(top)}.',
            hint: 'Turn the others off, or raise this one\'s order.',
          ),
        );
      }
    }

    // Level Map layers drawn through a material.
    for (final e in world.query(const [LevelMapComponent])) {
      final c = e.getComponent<LevelMapComponent>()!;
      for (final (layer, material) in _layerMaterials(context, c)) {
        if (!context.fileExists(material)) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: e,
              message:
                  '${_name(e)}: its layer $layer draws with "$material", '
                  'which does not exist.',
              hint: "Pick another in the layer's settings.",
            ),
          );
          continue;
        }
        final file = files.resolved2D(material, e, out);
        if (file != null && file.kind == Material2DKind.screen) {
          out.add(
            SceneProblem(
              entity: e,
              message:
                  '${_name(e)}: its layer $layer draws with $material, a '
                  'screen material: it is drawn on nothing.',
              hint: "Pick a sprite material in the layer's settings.",
            ),
          );
        } else if (file != null &&
            !lit &&
            (file.isOn('normalMap') || file.isOn('emissive'))) {
          needsLight ??= e;
        }
      }
    }

    if (needsLight != null) {
      out.add(
        SceneProblem(
          entity: needsLight,
          message:
              '${_name(needsLight)} draws with a normal map or glow, which '
              'shows only under Scene lighting — and the scene has none on.',
          hint: 'Scene lighting (Add menu, Lighting) turns 2-D lighting on.',
          fixes: [
            ProblemFix(
              label: 'Add Scene lighting',
              apply: () => _addLighting(scope),
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// The 3-D checks: shapes and models.
  static List<SceneProblem> materials3D(ValidationContext context) {
    final world = context.world;
    final scope = context.scope;
    final out = <SceneProblem>[];
    final files = _Files(context);
    for (final e in world.query(const [ModelComponent])) {
      final model = e.getComponent<ModelComponent>()!;
      for (final MapEntry(key: slot, value: path) in model.materials.entries) {
        if (path.trim().isEmpty) continue;
        if (!context.fileExists(path.trim())) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: e,
              message:
                  '${_name(e)}: its model draws ${slot == '*' ? 'all over' : slot} '
                  'with "$path", which does not exist.',
              fixes: [
                ProblemFix(
                  label: slot == '*'
                      ? "Draw it with the model's own materials"
                      : "Draw $slot with the model's own",
                  apply: () {
                    final edit = ComponentEdit.begin(scope, model);
                    model.materials = {...model.materials}..remove(slot);
                    edit.commit('Material dropped');
                  },
                ),
              ],
            ),
          );
          continue;
        }
        files.resolved3D(path.trim(), e, out);
      }
    }
    for (final e in world.query(const [Primitive3D])) {
      final path = e.getComponent<Primitive3D>()!.material.trim();
      if (path.isEmpty || !context.fileExists(path)) continue;
      files.resolved3D(path, e, out);
    }
    for (final e in world.query(const [MaterialOverrides3D])) {
      final overrides = e.getComponent<MaterialOverrides3D>()!;
      final unknown = [
        for (final key in overrides.values.keys)
          if (!_known3D(key)) key,
      ];
      if (unknown.isEmpty) continue;
      out.add(
        SceneProblem(
          entity: e,
          message:
              '${_name(e)}: its own material values for '
              '${unknown.join(', ')} change nothing — a game can change '
              '${MaterialFile.animatableKeys.join(', ')}.',
          fixes: [
            ProblemFix(
              label: 'Remove them',
              apply: () {
                final edit = ComponentEdit.begin(scope, overrides);
                for (final k in unknown) {
                  overrides.remove(k);
                }
                edit.commit('Material values removed');
              },
            ),
          ],
        ),
      );
    }
    return out;
  }

  static bool _known3D(String key) {
    final hash = key.indexOf('#');
    if (hash < 0) return MaterialFile.animatableKeys.contains(key);
    final pair = key.substring(0, hash);
    final i = key.substring(hash + 1);
    return (pair == 'tiling' || pair == 'offset') && (i == '0' || i == '1');
  }

  static List<SceneProblem> _unknown2D(
    EditorScope scope,
    Entity e,
    Map<String, Object> overrides,
    void Function(String key) remove,
  ) {
    final unknown = [
      for (final MapEntry(:key, :value) in overrides.entries)
        if (!Material2DShader.overrides(key, value)) key,
    ];
    if (unknown.isEmpty) return const [];
    final component =
        e.getComponent<Material2D>() as Component? ??
        e.getComponent<ScreenMaterial>();
    return [
      SceneProblem(
        entity: e,
        message:
            '${_name(e)}: its own values for ${unknown.join(', ')} change '
            'nothing: no effect has them, or they are the wrong kind.',
        fixes: [
          if (component != null)
            ProblemFix(
              label: 'Remove them',
              apply: () {
                final edit = ComponentEdit.begin(scope, component);
                unknown.forEach(remove);
                edit.commit('Material values removed');
              },
            ),
        ],
      ),
    ];
  }

  // Each layer's name and material, of a map in the scene or in its file.
  static List<(String, String)> _layerMaterials(
    ValidationContext context,
    LevelMapComponent c,
  ) {
    final inline = c.inline;
    if (inline != null) {
      return [
        for (final l in inline.layers)
          if (l.material.trim().isNotEmpty) (l.name, l.material.trim()),
      ];
    }
    if (!c.usesFile) return const [];
    final json = context.readJson(c.mapPath.trim());
    final layers = json?['layers'];
    if (layers is! List) return const [];
    return [
      for (final l in layers)
        if (l is Map &&
            l['material'] is String &&
            (l['material'] as String).trim().isNotEmpty)
          ('${l['name'] ?? '?'}', (l['material'] as String).trim()),
    ];
  }

  static void _addLighting(EditorScope scope) {
    final names = {for (final e in scope.world.entities) e.name};
    var name = 'Lighting';
    for (var n = 2; names.contains(name); n++) {
      name = 'Lighting $n';
    }
    scope.history.push(
      CreateEntitiesCommand(
        label: 'Add Scene lighting',
        world: scope.world,
        sceneState: scope.sceneState,
        specs: [
          EntitySpec(
            name: name,
            componentsJson: [
              for (final c in <Component>[
                TransformComponent(),
                LayerComponent(),
                Lighting2D(),
              ])
                ?scope.codec.encode(c),
            ],
            codec: scope.codec,
          ),
        ],
      ),
    );
  }

  static String _name(Entity e) => e.name ?? 'An entity';
}

// Material files read once per check, their own problems said once each.
final class _Files {
  _Files(this.context);

  final ValidationContext context;
  final Map<String, Object?> _twoD = {};
  final Map<String, Object?> _threeD = {};

  Material2DFile? resolved2D(String path, Entity e, List<SceneProblem> out) {
    if (_twoD.containsKey(path)) return _twoD[path] as Material2DFile?;
    Material2DFile? read(String p) {
      final text = context.readText(p);
      return text == null ? null : Material2DFile.parse(text);
    }

    try {
      final r = MaterialChain.resolve2D(path, read);
      _problems(path, e, [...r.problems, ...r.value.validate()], out);
      return _twoD[path] = r.value;
    } on Object catch (error) {
      _unreadable(path, e, error, out);
      return _twoD[path] = null;
    }
  }

  MaterialFile? resolved3D(String path, Entity e, List<SceneProblem> out) {
    if (_threeD.containsKey(path)) return _threeD[path] as MaterialFile?;
    MaterialFile? read(String p) {
      final text = context.readText(p);
      return text == null ? null : MaterialFile.parse(text);
    }

    try {
      final r = MaterialChain.resolve3D(path, read);
      _problems(path, e, [...r.problems, ...r.value.validate()], out);
      return _threeD[path] = r.value;
    } on Object catch (error) {
      _unreadable(path, e, error, out);
      return _threeD[path] = null;
    }
  }

  void _problems(
    String path,
    Entity e,
    List<String> problems,
    List<SceneProblem> out,
  ) {
    if (problems.isEmpty) return;
    out.add(
      SceneProblem(
        entity: e,
        message: '$path: ${problems.join(' ')}',
        hint: 'Open it to put it right.',
      ),
    );
  }

  void _unreadable(
    String path,
    Entity e,
    Object error,
    List<SceneProblem> out,
  ) => out.add(
    SceneProblem(
      severity: ProblemSeverity.error,
      entity: e,
      message: "$path can't be read as a material: $error",
    ),
  );
}
