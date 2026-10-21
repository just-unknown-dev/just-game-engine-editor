import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';

/// The parsed model at a path once loaded, or null.
typedef ModelDataOf = ModelData? Function(String path);

/// Inspector sections for the 3-D components, below their fields: what a
/// model holds, what a light does, and sky presets.
abstract final class GraphicsInspectors {
  /// Every section, reading loaded models through [dataOf].
  static List<InspectorSection> all(
    ModelDataOf Function(EditorScope scope) dataOf,
  ) => [
    InspectorSection(
      id: 'graphics.model',
      order: 60,
      appliesTo: (e) => e.hasComponent<ModelComponent>(),
      build: (context, entity, scope) =>
          _ModelFacts(entity: entity, dataOf: dataOf(scope)),
    ),
    InspectorSection(
      id: 'graphics.light',
      order: 61,
      appliesTo: (e) => e.hasComponent<LightComponent>(),
      build: (context, entity, scope) =>
          _Note(lightNote(entity.getComponent<LightComponent>()!)),
    ),
    InspectorSection(
      id: 'graphics.environment',
      order: 62,
      appliesTo: (e) => e.hasComponent<EnvironmentComponent>(),
      build: (context, entity, scope) =>
          _SkyPresets(entity: entity, scope: scope),
    ),
  ];

  /// What a light of [light]'s kind does, in a line.
  static String lightNote(LightComponent light) => switch (light.kind) {
    LightKind.directional =>
      'Lights the whole scene from far away, along the entity\'s forward (+Z) axis, and casts the shadows. Turn the entity to aim it.',
    LightKind.point =>
      light.range > 0
          ? 'Shines every way from the entity, fading out by ${light.range.toStringAsFixed(1)} m.'
          : 'Shines every way from the entity, with no limit to its reach: give it a range to keep it local.',
    LightKind.spot =>
      'A cone along the entity\'s forward (+Z) axis${light.range > 0 ? ', reaching ${light.range.toStringAsFixed(1)} m' : ''}. Full brightness inside the inner angle, none outside the outer.',
  };

  /// Sky looks, as values for the environment's fields by name.
  static const Map<String, Map<String, Object>> skyPresets = {
    'Day': {
      'sky': true,
      'zenith': Color(0xFF8AB4F0),
      'horizon': Color(0xFFE0EAF5),
      'ground': Color(0xFF9E978F),
      'ambientSky': Color(0xFF9EAAC0),
      'ambientGround': Color(0xFF6B655F),
      'exposure': 1.0,
    },
    'Dusk': {
      'sky': true,
      'zenith': Color(0xFF3B4C7A),
      'horizon': Color(0xFFF2A65A),
      'ground': Color(0xFF4A3B36),
      'ambientSky': Color(0xFF6E6A8F),
      'ambientGround': Color(0xFF4A3A30),
      'exposure': 0.9,
    },
    'Night': {
      'sky': true,
      'zenith': Color(0xFF05070F),
      'horizon': Color(0xFF1C2338),
      'ground': Color(0xFF0E0E12),
      'ambientSky': Color(0xFF26304A),
      'ambientGround': Color(0xFF14141A),
      'exposure': 0.8,
    },
    'Overcast': {
      'sky': true,
      'zenith': Color(0xFF9AA3AD),
      'horizon': Color(0xFFC9CED3),
      'ground': Color(0xFF7A7672),
      'ambientSky': Color(0xFFA9B0B8),
      'ambientGround': Color(0xFF77736F),
      'exposure': 1.0,
    },
  };

  /// Sets [entity]'s environment to the preset [name], as one undo step.
  static void applySky(EditorScope scope, Entity entity, String name) {
    final environment = entity.getComponent<EnvironmentComponent>();
    final preset = skyPresets[name];
    if (environment == null) return;
    final definition = scope.definitions.definitionFor(environment);
    if (preset == null || definition == null) return;
    final label = 'Sky: $name';
    final commands = <EditorCommand>[
      for (final MapEntry(:key, :value) in preset.entries)
        if (definition.field(key) case SchemaField(:final write?, :final read))
          ComponentFieldCommand(
            label: label,
            component: environment,
            write: write,
            before: read(environment),
            after: value,
            sceneState: scope.sceneState,
            entity: entity,
          ),
    ];
    if (commands.isEmpty) return;
    scope.history.push(CompositeCommand(label: label, commands: commands));
  }
}

TextStyle get _muted =>
    TextStyle(color: EditorTheme.textMuted, fontSize: 11, height: 1.35);

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
    child: Text(text, style: _muted),
  );
}

/// What a model holds: whether it loaded, its size, meshes, triangles and
/// animations.
class _ModelFacts extends StatelessWidget {
  const _ModelFacts({required this.entity, required this.dataOf});

  final Entity entity;
  final ModelDataOf dataOf;

  @override
  Widget build(BuildContext context) {
    final model = entity.getComponent<ModelComponent>()!;
    if (model.model.isEmpty) {
      return const _Note('No model chosen: pick a .glb or .gltf file above.');
    }
    final data = dataOf(model.model);
    if (data == null) return const _Note('Not loaded yet.');
    final box = Aabb3();
    data.bounds.transformInto(gltfToEngine, box);
    final size = Vector3.zero();
    if (!box.isEmpty) box.sizeInto(size);
    var triangles = 0;
    for (final mesh in data.meshes) {
      for (final p in mesh.primitives) {
        triangles += p.indices.length ~/ 3;
      }
    }
    final clips = [for (final a in data.animations) a.name];
    String m(double v) => v.toStringAsFixed(v < 10 ? 2 : 1);
    return _Note(
      [
        'Size ${m(size.x)} × ${m(size.y)} × ${m(size.z)} m',
        '${data.meshes.length} mesh${data.meshes.length == 1 ? '' : 'es'}, $triangles triangles'
            '${data.skins.isEmpty ? '' : ', skinned'}',
        if (clips.isNotEmpty) 'Animations: ${clips.join(', ')}',
      ].join('\n'),
    );
  }
}

/// Buttons that give the environment a ready-made sky.
class _SkyPresets extends StatelessWidget {
  const _SkyPresets({required this.entity, required this.scope});

  final Entity entity;
  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Sky', style: _muted),
          for (final name in GraphicsInspectors.skyPresets.keys)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 11),
              ),
              onPressed: () => GraphicsInspectors.applySky(scope, entity, name),
              child: Text(name),
            ),
        ],
      ),
    );
  }
}
