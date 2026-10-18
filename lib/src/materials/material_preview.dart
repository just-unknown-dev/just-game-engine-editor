import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:just_game_engine/graphics_3d.dart';

/// What a material is shown on in a preview.
enum PreviewShape {
  /// A ball: every angle at once, the default.
  ball('Ball', 0.5),

  /// A cube: flat faces and edges.
  cube('Cube', 0.65),

  /// A cylinder: a curve one way, flat the other.
  cylinder('Cylinder', 0.6),

  /// A ring.
  torus('Torus', 0.56),

  /// A floor tile: how the maps tile and lie.
  plane('Plane', 0.71);

  const PreviewShape(this.label, this.radius);

  /// Its name in the editor.
  final String label;

  /// How far it reaches from its middle, in metres: what a view frames.
  final double radius;

  /// Its mesh, its coordinates laid out as [uv] says.
  ShapeMesh mesh(ShapeUv uv) => switch (this) {
    ball => Sphere3D(radius: 0.5, segments: 48, rings: 24).buildMesh(uv),
    cube => Cube3D(width: 0.75, height: 0.75, depth: 0.75).buildMesh(uv),
    cylinder => Cylinder3D(
      radius: 0.4,
      height: 0.9,
      segments: 48,
    ).buildMesh(uv),
    torus => Torus3D(
      radius: 0.38,
      tubeRadius: 0.16,
      segments: 48,
      sides: 24,
    ).buildMesh(uv),
    plane => Plane3D(width: 1, depth: 1).buildMesh(uv),
  };
}

/// What a preview is drawn in front of.
enum PreviewBackdrop {
  /// The light's own sky: a plain dark grey for the studio.
  sky('Sky', null),

  /// A plain dark grey, as the 2-D material window's dark background.
  dark('Dark', 0xFF2A2E35),

  /// A plain light grey, as the 2-D material window's bright background.
  bright('Bright', 0xFFD9DDE3);

  const PreviewBackdrop(this.label, this.colour);

  /// Its name in the editor.
  final String label;

  /// Its colour (sRGB); null for [sky].
  final int? colour;
}

/// The light a preview is drawn in.
enum PreviewLighting {
  /// A neutral grey room with a key light: how the material looks itself.
  studio('Studio'),

  /// A clear day's sky and sun.
  day('Day'),

  /// A low, warm sun.
  dusk('Dusk'),

  /// Moonlight: where a glow shows.
  night('Night'),

  /// Soft light from a grey sky.
  overcast('Overcast'),

  /// The open scene's own sky and sun.
  scene('Scene');

  const PreviewLighting(this.label);

  /// Its name in the editor.
  final String label;

  /// The sky a preset lights from: zenith, horizon, ground, ambient sky,
  /// ambient ground (sRGB), exposure; null for [scene].
  _Sky? get _sky => switch (this) {
    // A bright soft box overhead and a grey room: what metal mirrors.
    studio => const _Sky(
      0xFFD8DCE3,
      0xFF8A8F99,
      0xFF33353B,
      0xFF8A8F99,
      0xFF3A3A40,
      1,
      drawn: false,
    ),
    day => const _Sky(
      0xFF8AB4F0,
      0xFFE0EAF5,
      0xFF9E978F,
      0xFF9EAAC0,
      0xFF6B655F,
      1,
    ),
    dusk => const _Sky(
      0xFF3B4C7A,
      0xFFF2A65A,
      0xFF4A3B36,
      0xFF6E6A8F,
      0xFF4A3A30,
      0.9,
    ),
    night => const _Sky(
      0xFF05070F,
      0xFF1C2338,
      0xFF0E0E12,
      0xFF26304A,
      0xFF14141A,
      0.8,
    ),
    overcast => const _Sky(
      0xFF9AA3AD,
      0xFFC9CED3,
      0xFF7A7672,
      0xFFA9B0B8,
      0xFF77736F,
      1,
    ),
    scene => null,
  };

  /// The sun of a preset: its direction (where its light goes, +Y down),
  /// linear colour and intensity.
  (Vector3, (double, double, double), double) get _sun => switch (this) {
    studio => (Vector3(0.3, 1, 0.5), (1.0, 1.0, 1.0), 2.6),
    day => (Vector3(0.3, 1, 0.5), (1.0, 0.96, 0.9), 3.0),
    dusk => (Vector3(0.9, 0.3, 0.2), (1.0, 0.55, 0.3), 2.2),
    night => (Vector3(0.2, 1, 0.6), (0.45, 0.55, 0.9), 0.5),
    overcast => (Vector3(0.1, 1, 0.3), (0.9, 0.92, 0.95), 0.9),
    scene => (Vector3(0.3, 1, 0.5), (1.0, 1.0, 1.0), 3.0),
  };

  /// The gradient a preset's reflections come from (linear); null for
  /// [scene], whose own map is used.
  (
    (double, double, double),
    (double, double, double),
    (double, double, double),
  )?
  get gradient {
    final sky = _sky;
    if (sky == null) return null;
    return (_linear(sky.zenith), _linear(sky.horizon), _linear(sky.ground));
  }

  /// Lights [scene] as this preset says: its sun and its sky, with [map]
  /// (made from [gradient]) for its reflections. [from] is the open
  /// scene's drawing, for [PreviewLighting.scene]; without it, studio light.
  void apply(RenderScene scene, {GpuEnvironmentMap? map, RenderScene? from}) {
    final env = scene.environment;
    scene.lights.clear();
    if (this == PreviewLighting.scene && from != null) {
      final sun = from.sun;
      scene.sun
        ..direction.setFrom(sun.direction)
        ..color = sun.color
        ..intensity = sun.intensity
        ..enabled = sun.enabled;
      final f = from.environment;
      env
        ..zenith = f.zenith
        ..horizon = f.horizon
        ..ground = f.ground
        ..ambientSky = f.ambientSky
        ..ambientGround = f.ambientGround
        ..exposure = f.exposure
        ..sky = f.sky
        ..clearColor = f.clearColor
        ..fogDensity = 0
        ..map = f.map
        ..reflections = f.reflections
        ..skybox = f.skybox
        ..skyboxBlur = f.skyboxBlur;
      return;
    }
    final preset = this == PreviewLighting.scene
        ? PreviewLighting.studio
        : this;
    final sky = preset._sky!;
    final (direction, colour, intensity) = preset._sun;
    scene.sun
      ..direction.setFrom(direction.normalized())
      ..color = colour
      ..intensity = intensity
      ..enabled = true;
    env
      ..zenith = _linear(sky.zenith)
      ..horizon = _linear(sky.horizon)
      ..ground = _linear(sky.ground)
      ..ambientSky = _linear(sky.ambientSky)
      ..ambientGround = _linear(sky.ambientGround)
      ..exposure = sky.exposure
      ..sky = sky.drawn
      ..clearColor = _linear(0xFF17191D)
      ..fogDensity = 0
      ..map = map
      ..reflections = 1
      ..skybox = false
      ..skyboxBlur = 0;
  }

  static (double, double, double) _linear(int argb) =>
      GraphicsShapes.linear(Color(argb));
}

final class _Sky {
  const _Sky(
    this.zenith,
    this.horizon,
    this.ground,
    this.ambientSky,
    this.ambientGround,
    this.exposure, {
    this.drawn = true,
  });

  final int zenith, horizon, ground, ambientSky, ambientGround;
  final double exposure;

  /// Whether the sky is drawn behind; otherwise a plain dark grey.
  final bool drawn;
}

/// A view of something [radius] metres round its middle, [width] by
/// [height], turned [yaw] and tipped [pitch] (radians), [zoom] times as
/// close as fits it all.
RenderView framePreview(
  int width,
  int height, {
  double radius = 0.5,
  double yaw = -0.6,
  double pitch = -0.45,
  double zoom = 1,
}) {
  const fov = math.pi / 4;
  final fit = radius / math.sin(fov / 2) * 1.05;
  final distance = fit / zoom.clamp(0.25, 4);
  final eye = Vector3(
    -math.cos(pitch) * math.sin(yaw),
    math.sin(pitch),
    -math.cos(pitch) * math.cos(yaw),
  )..scale(distance);
  final view = RenderView()
    ..width = width
    ..height = height;
  view.lookAt(eye, Vector3.zero());
  view.projection.setPerspectiveYDown(
    fov,
    width / height,
    math.max(0.01, distance - radius * 2),
    distance + radius * 2,
  );
  return view;
}
