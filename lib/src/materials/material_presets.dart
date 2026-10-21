import 'package:just_game_engine/graphics_3d.dart';

/// A starting look for a material: a few of its values set at once, as
/// one undo step. Its maps, layers and layout stay as they are.
final class MaterialPreset {
  const MaterialPreset(this.id, this.label, this.detail, this.apply);

  /// Stable id: `'gold'`.
  final String id;

  /// Its name in the editor.
  final String label;

  /// What it is for, in a few words.
  final String detail;

  /// The material with this preset's values.
  final MaterialFile Function(MaterialFile m) apply;

  /// The presets the workspace offers, in the order it lists them. A
  /// getter, so an edited preset shows after a hot reload.
  static List<MaterialPreset> get all => [
    MaterialPreset(
      'matte',
      'Matte',
      'No shine: chalk, clay, cloth',
      (m) => _surface(m, metallic: 0, roughness: 0.9),
    ),
    MaterialPreset(
      'plastic',
      'Plastic',
      'A soft shine',
      (m) => _surface(m, metallic: 0, roughness: 0.4),
    ),
    MaterialPreset(
      'glossy',
      'Glossy',
      'Polished paint, lacquer',
      (m) => _surface(m, metallic: 0, roughness: 0.12),
    ),
    MaterialPreset(
      'rubber',
      'Rubber',
      'Dark and dull',
      (m) => _surface(m, color: 0xFF2B2B2E, metallic: 0, roughness: 1),
    ),
    MaterialPreset(
      'steel',
      'Steel',
      'Brushed metal',
      (m) => _surface(m, color: 0xFFC4C8CC, metallic: 1, roughness: 0.35),
    ),
    MaterialPreset(
      'chrome',
      'Chrome',
      'A mirror of metal',
      (m) => _surface(m, color: 0xFFEDEFF2, metallic: 1, roughness: 0.04),
    ),
    MaterialPreset(
      'gold',
      'Gold',
      'Warm, shiny metal',
      (m) => _surface(m, color: 0xFFFFC356, metallic: 1, roughness: 0.22),
    ),
    MaterialPreset(
      'copper',
      'Copper',
      'Reddish metal',
      (m) => _surface(m, color: 0xFFE59A6E, metallic: 1, roughness: 0.3),
    ),
    MaterialPreset(
      'glass',
      'Glass',
      'See-through and smooth',
      (m) => _surface(
        m,
        color: 0xFFE6F2FF,
        metallic: 0,
        roughness: 0.04,
      ).copyWith(alpha: MaterialAlpha.blend, opacity: 0.25),
    ),
    MaterialPreset(
      'foliage',
      'Leaves',
      'Cut out by its colour map, both faces',
      (m) => m.copyWith(
        alpha: MaterialAlpha.cutout,
        alphaCutoff: 0.5,
        doubleSided: true,
        metallic: 0,
        roughness: 0.7,
      ),
    ),
    MaterialPreset(
      'glow',
      'Glow',
      'Gives off light of its own',
      (m) => m.copyWith(emission: m.color, emissionStrength: 4),
    ),
    MaterialPreset(
      'unlit',
      'Unlit',
      'Its colour as it is, whatever the light',
      (m) => m.copyWith(unlit: true),
    ),
  ];

  /// The preset called [id], or null.
  static MaterialPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  // An opaque, lit surface: the look most presets start from.
  static MaterialFile _surface(
    MaterialFile m, {
    int? color,
    required double metallic,
    required double roughness,
  }) => m.copyWith(
    kind: MaterialKind.lit,
    color: color,
    metallic: metallic,
    roughness: roughness,
    alpha: MaterialAlpha.opaque,
    unlit: false,
  );
}
