import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// What the editor itself brings for sound, through the seams a module
/// uses: a marker on every sound source and on the listener, how far a
/// selected 3-D source carries, an Audio group in the Add menu, and an
/// audio file dropped on the viewport becoming a source.
///
/// Sound is the engine's own (`AudioSourceComponent`,
/// `AudioListenerComponent`), so every project has it, 2-D and 3-D.
abstract final class BuiltInAudioContributions {
  /// The colour sound is drawn in.
  static const Color color = Color(0xFFAB47BC);

  /// A marker on every entity with a sound source.
  static const EditorMarker sources = EditorMarker(
    id: 'audio.source',
    components: [jge.AudioSourceComponent],
    icon: Icons.volume_up_rounded,
    color: color,
  );

  /// A marker on the listener.
  static const EditorMarker listener = EditorMarker(
    id: 'audio.listener',
    components: [jge.AudioListenerComponent],
    icon: Icons.hearing_rounded,
    color: color,
  );

  /// Both markers.
  static List<EditorMarker> get markers => [sources, listener];

  /// How far a selected 3-D source carries.
  static List<ViewportOverlay> get viewportOverlays => [AudioRangeOverlay()];

  /// The Add menu's Audio group.
  static const PrefabCategory category = PrefabCategory(
    label: 'Audio',
    order: 30,
  );

  /// Ids of the Audio prefabs.
  static const String soundId = 'builtin.sound';
  static const String sound3dId = 'builtin.sound_3d';
  static const String listenerId = 'builtin.audio_listener';

  /// The Audio group's prefabs, for 2-D and 3-D scenes alike.
  static List<PrefabDefinition> get prefabs => [_sound, _sound3d, _listener];

  static PrefabDefinition get _sound => PrefabDefinition(
    id: soundId,
    name: 'Sound',
    category: category.label,
    icon: Icons.music_note_outlined,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    dimensions: jge.Dimensions.both,
    description:
        'A sound heard the same wherever the listener is — ambience, a '
        'drone. Pick its file in the inspector.',
    namePrefix: 'Sound',
    build: (position, _) => [
      ..._at2d(position),
      AudioDrop.source('', in3d: false),
    ],
    buildAt: (at) => [_above(at), AudioDrop.source('', in3d: true)],
  );

  static PrefabDefinition get _sound3d => PrefabDefinition(
    id: sound3dId,
    name: '3D sound',
    category: category.label,
    icon: Icons.surround_sound_outlined,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    dimensions: jge.Dimensions.both,
    description:
        'A sound heard from where it is: louder near, panned by side, '
        'muffled far away. Pick its file in the inspector.',
    namePrefix: 'Sound',
    build: (position, _) => [
      ..._at2d(position),
      AudioDrop.source('', in3d: false, spatial: true),
    ],
    buildAt: (at) => [
      _above(at),
      AudioDrop.source('', in3d: true, spatial: true),
    ],
  );

  static PrefabDefinition get _listener => PrefabDefinition(
    id: listenerId,
    name: 'Audio listener',
    category: category.label,
    icon: Icons.hearing_rounded,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    dimensions: jge.Dimensions.both,
    description:
        'Where 3-D sounds are heard from. Without one the camera hears; on '
        'the character a third-person camera follows, tick "Face like the '
        'camera".',
    namePrefix: 'Listener',
    build: (position, _) => [..._at2d(position), jge.AudioListenerComponent()],
    buildAt: (at) => [_above(at), jge.AudioListenerComponent()],
  );

  static List<jge.Component> _at2d(Offset position) => [
    jge.TransformComponent(position: jge.Vector3(position.dx, position.dy, 0)),
    jge.LayerComponent(),
  ];

  static jge.TransformComponent _above(SurfacePoint at) =>
      jge.TransformComponent(
        position: jge.Vector3.copy(at.position)
          ..addScaled(at.normal, AudioDrop.lift),
      );
}

/// How far a selected 3-D sound carries: a ring at the distance it starts
/// to fade from full volume, and a fainter one where it falls silent — in
/// a 3-D scene three of each, round the three axes.
class AudioRangeOverlay extends ViewportOverlay {
  // How far a selected sound carries.
  @override
  GizmoKind get gizmoKind => GizmoKind.reach;

  @override
  String get id => 'audio.ranges';

  @override
  String get label => 'Sound ranges';

  @override
  void paint(ViewportOverlayContext context) {
    final near = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BuiltInAudioContributions.color.withValues(alpha: 0.95);
    final far = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BuiltInAudioContributions.color.withValues(alpha: 0.45);
    for (final entity in context.world.query([
      jge.TransformComponent,
      jge.AudioSourceComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final source = entity.getComponent<jge.AudioSourceComponent>()!;
      if (!source.is3d) continue;
      final centre = entity.getComponent<jge.TransformComponent>()!.position;
      final spatial = source.spatial;
      _rings(context, centre, spatial.minDistance, near);
      _rings(context, centre, spatial.maxDistance, far);
    }
  }

  static const int _steps = 48;

  /// Circles of [radius] round [centre]: one in the screen's plane in 2-D,
  /// one round each axis in 3-D.
  static void _rings(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    Paint paint,
  ) {
    // Each plane by two of its axes, as (x, y, z).
    const xy = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0));
    const xz = ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0));
    const yz = ((0.0, 1.0, 0.0), (0.0, 0.0, 1.0));
    final planes = context.view.isPlanar ? const [xy] : const [xy, xz, yz];
    final point = jge.Vector3.zero();
    for (final (u, v) in planes) {
      Offset? last;
      for (var i = 0; i <= _steps; i++) {
        final angle = i / _steps * 2 * math.pi;
        final c = math.cos(angle) * radius, s = math.sin(angle) * radius;
        point.setValues(
          centre.x + u.$1 * c + v.$1 * s,
          centre.y + u.$2 * c + v.$2 * s,
          centre.z + u.$3 * c + v.$3 * s,
        );
        final screen = context.project(point);
        // A point behind the viewer breaks the ring there.
        if (screen != null && last != null) {
          context.canvas.drawLine(last, screen, paint);
        }
        last = screen;
      }
    }
  }
}
