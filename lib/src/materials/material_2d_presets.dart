import 'package:just_game_engine/just_game_engine.dart';

/// A starting look for a 2-D material: effects switched on with values,
/// as one undo step. What else the material has stays as it is.
final class Material2DPreset {
  const Material2DPreset(
    this.id,
    this.label,
    this.detail,
    this.kind,
    this.effects,
  );

  /// Stable id: `'hitFlash'`.
  final String id;

  /// Its name in the editor.
  final String label;

  /// What it is for, in a few words.
  final String detail;

  /// The kind of material it is for.
  final Material2DKind kind;

  /// The effects it switches on, by id, with the values it gives each (by
  /// name, shaped as a file saves them).
  final Map<String, Map<String, Object>> effects;

  /// [m] with this preset's effects on and values set.
  Material2DFile apply(Material2DFile m) {
    var next = m;
    for (final MapEntry(key: id, value: values) in effects.entries) {
      next = next.withEffect(id, true);
      for (final MapEntry(:key, :value) in values.entries) {
        next = next.withValue('$id.$key', value);
      }
    }
    return next;
  }

  /// The presets for [kind], in the order the workspace lists them.
  static List<Material2DPreset> of(Material2DKind kind) => [
    for (final p in all)
      if (p.kind == kind) p,
  ];

  /// The preset called [id], or null.
  static Material2DPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Every preset.
  static const List<Material2DPreset> all = [
    Material2DPreset(
      'hitFlash',
      'Hit flash',
      'White all over: animate its amount when hit',
      Material2DKind.sprite,
      {
        'flash': {'colour': 0xFFFFFFFF, 'amount': 1.0},
      },
    ),
    Material2DPreset(
      'outline',
      'Outline',
      'A dark line round its edge',
      Material2DKind.sprite,
      {
        'outline': {'colour': 0xFF101014, 'width': 1.0},
      },
    ),
    Material2DPreset(
      'glow',
      'Glow',
      'A soft warm light round it',
      Material2DKind.sprite,
      {
        'glow': {'colour': 0xFFFFD54F, 'radius': 8.0, 'strength': 1.2},
      },
    ),
    Material2DPreset(
      'dropShadow',
      'Drop shadow',
      'A soft shadow below and to the right',
      Material2DKind.sprite,
      {
        'dropShadow': {
          'colour': 0x80000000,
          'offset': [4.0, 4.0],
          'softness': 3.0,
        },
      },
    ),
    Material2DPreset('ghost', 'Ghost', 'Pale and cold', Material2DKind.sprite, {
      'greyscale': {'amount': 0.7},
      'tint': {'colour': 0xFFB3E5FC},
    }),
    Material2DPreset(
      'water',
      'Water',
      'Scrolling, with a gentle wave: for tiles',
      Material2DKind.sprite,
      {
        'scroll': {
          'speed': [12.0, 0.0],
        },
        'wave': {
          'amplitude': 2.0,
          'wavelength': 48.0,
          'speed': 1.5,
          'direction': 'horizontal',
        },
      },
    ),
    Material2DPreset(
      'shine',
      'Shine',
      'A glint sweeping across now and then: pickups',
      Material2DKind.sprite,
      {'shine': {}},
    ),
    Material2DPreset(
      'dissolve',
      'Dissolve',
      'Burning away: animate its amount',
      Material2DKind.sprite,
      {
        'dissolve': {'amount': 0.5, 'edgeColour': 0xFFFF8800},
      },
    ),
    Material2DPreset(
      'glowsInDark',
      'Glows in the dark',
      'Lit by itself when the scene is dark',
      Material2DKind.sprite,
      {
        'emissive': {'amount': 1.0},
      },
    ),
    Material2DPreset(
      'retroTv',
      'Retro TV',
      'A curved old screen with lines',
      Material2DKind.screen,
      {
        'crt': {'curvature': 0.15, 'aberration': 1.0},
        'scanlines': {'amount': 0.3, 'size': 3.0},
        'vignette': {'amount': 0.5, 'softness': 0.5},
      },
    ),
    Material2DPreset(
      'pixelArt',
      'Chunky pixels',
      'The frame drawn in big pixels',
      Material2DKind.screen,
      {
        'pixelate': {'size': 4.0},
      },
    ),
    Material2DPreset(
      'night',
      'Night',
      'Darker, bluer, the corners dim',
      Material2DKind.screen,
      {
        'grade': {'brightness': -0.2, 'saturation': 0.6, 'tint': 0xFFA8B8FF},
        'vignette': {'amount': 0.6, 'softness': 0.6},
      },
    ),
    Material2DPreset(
      'oldPhoto',
      'Old photo',
      'Sepia, faded at the edges',
      Material2DKind.screen,
      {
        'gradientMap': {
          'stops': [
            [0.0, 0xFF2B1D0E],
            [1.0, 0xFFF3E2C3],
          ],
          'amount': 1.0,
        },
        'vignette': {'amount': 0.45, 'softness': 0.7},
      },
    ),
  ];
}
