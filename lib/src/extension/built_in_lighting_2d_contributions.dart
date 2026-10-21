import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

import '../core/scope/editor_scope_services.dart';
import '../ui/level_designer/commands/editor_command_context.dart';

/// Shift+L's state, one per editor: whether the scene is seen unlit, and
/// the pass turned off for it with what the game had it at.
class _UnlitView {
  bool unlit = false;
  jge.Lighting2DPass? heldPass;
  bool gameEnabled = true;
}

/// What the editor itself brings for 2-D lighting, through the seams a
/// module uses: a marker on every light and on the scene's lighting, how far
/// a selected light reaches (and its cone), the outline of a selected shadow
/// caster, a Lighting group in the Add menu, and a command (Shift+L) to see
/// the scene unlit while it is worked on.
///
/// Lighting is the engine's own (`Light2D`, `Lighting2D`,
/// `ShadowCaster2D`), so every 2-D project has it.
abstract final class BuiltInLighting2DContributions {
  /// The colour lights are drawn in.
  static const Color color = Color(0xFFFFCA28);

  /// A marker on every 2-D light.
  static const EditorMarker lights = EditorMarker(
    id: 'lighting.light2D',
    components: [jge.Light2D],
    icon: Icons.lightbulb_outline,
    color: color,
  );

  /// A marker on the scene's lighting.
  static const EditorMarker lighting = EditorMarker(
    id: 'lighting.lighting2D',
    components: [jge.Lighting2D],
    icon: Icons.wb_twilight,
    color: color,
  );

  /// Both markers.
  static List<EditorMarker> get markers => [lights, lighting];

  /// A selected light's reach and cone; a selected caster's outline.
  static List<ViewportOverlay> get viewportOverlays => [Light2DOverlay()];

  /// The Add menu's Lighting group.
  static const PrefabCategory category = PrefabCategory(
    label: 'Lighting',
    order: 35,
  );

  /// Ids of the Lighting prefabs.
  static const String pointId = 'builtin.light_2d_point';
  static const String spotId = 'builtin.light_2d_spot';
  static const String lightingId = 'builtin.lighting_2d';

  /// The Lighting group's prefabs, for 2-D scenes.
  static List<PrefabDefinition> get prefabs => [_lighting, _point, _spot];

  static PrefabDefinition get _point => PrefabDefinition(
    id: pointId,
    name: 'Point light',
    category: category.label,
    icon: Icons.lightbulb_outline,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'Light all round it, fading to nothing at its radius. Needs Scene '
        'lighting in the scene.',
    namePrefix: 'Light',
    build: (position, _) => [..._at(position), jge.Light2D()],
  );

  static PrefabDefinition get _spot => PrefabDefinition(
    id: spotId,
    name: 'Spot light',
    category: category.label,
    icon: Icons.flashlight_on_outlined,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'A cone of light along its turn (pointing right unturned). Needs '
        'Scene lighting in the scene.',
    namePrefix: 'Spot',
    build: (position, _) => [
      ..._at(position),
      jge.Light2D(kind: jge.Light2DKind.spot, radius: 320),
    ],
  );

  static PrefabDefinition get _lighting => PrefabDefinition(
    id: lightingId,
    name: 'Scene lighting',
    category: category.label,
    icon: Icons.wb_twilight,
    color: color,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'Turns 2-D lighting on: the scene is drawn in its ambient light, lit '
        'by its lights. One per scene.',
    namePrefix: 'Lighting',
    build: (position, _) => [..._at(position), jge.Lighting2D()],
  );

  static List<jge.Component> _at(Offset position) => [
    jge.TransformComponent(position: jge.Vector3(position.dx, position.dy, 0)),
    jge.LayerComponent(),
  ];

  /// The engine's lighting pass, or null without one (or before the
  /// engine is up).
  static jge.Lighting2DPass? passOf(jge.Engine? engine) {
    if (engine == null || !engine.isInitialized) return null;
    for (final p in engine.rendering.screenPasses) {
      if (p is jge.Lighting2DPass) return p;
    }
    return null;
  }

  /// Id of the command that turns 2-D lighting on and off in the editor.
  static const String toggleId = 'view.toggleLighting2D';

  /// Turning 2-D lighting off to see the scene as drawn, and back on.
  ///
  /// A view of the editor's, not a change to the game: it is off only while
  /// authoring ([syncUnlit]) — a play-test, and the game once the editor
  /// closes, are lit as the game has them.
  static List<DesignerCommand> get commands => [
    DesignerCommand(
      id: toggleId,
      label: 'Turn 2-D lighting on or off',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.twoD,
      isEnabled: (c) => passOf(c.scope.engine) != null,
      run: (c) {
        final view = _viewOf(c.scope)..unlit = !_viewOf(c.scope).unlit;
        syncUnlit(c.scope, authoring: !c.scope.isPlayTesting.value);
        c.designer?.controller.setStatus(
          view.unlit ? '2-D lighting off: as drawn' : '2-D lighting on',
        );
      },
    ),
  ];

  /// Whether the editor shows [scope]'s scene unlit while authoring (Shift+L).
  static bool isUnlit(EditorScope scope) => _viewOf(scope).unlit;

  /// Puts the engine's 2-D lighting pass as it should be now: off while
  /// [authoring] with the scene asked to be seen unlit, and otherwise as
  /// the game had it before the editor turned it off. The editor calls it
  /// every frame, and when it closes.
  static void syncUnlit(EditorScope scope, {required bool authoring}) {
    final view = _viewOf(scope);
    final pass = passOf(scope.engine);
    final want = authoring && view.unlit && pass != null;
    final held = view.heldPass;
    if (held != null && (!want || !identical(held, pass))) {
      held.enabled = view.gameEnabled;
      view.heldPass = null;
    }
    if (want && view.heldPass == null) {
      view.gameEnabled = pass.enabled;
      view.heldPass = pass;
      pass.enabled = false;
    }
  }

  static _UnlitView _viewOf(EditorScope scope) {
    final container = scope.container;
    if (!container.isRegistered<_UnlitView>()) {
      container.registerLazySingleton<_UnlitView>(_UnlitView.new);
    }
    return container.get<_UnlitView>();
  }

  /// 2-D lights in a scene with no Scene lighting on light nothing: said,
  /// with Scene lighting added (or the one there turned on) as the fix.
  static List<SceneProblem> lightsWithoutLighting(ValidationContext context) {
    final world = context.world;
    final lights = world.query(const [jge.Light2D]);
    if (lights.isEmpty) return const [];
    final lightings = world
        .query(const [jge.Lighting2D])
        .map((e) => e.getComponent<jge.Lighting2D>()!)
        .toList();
    if (lightings.any((l) => l.enabled)) return const [];
    final scope = context.scope;
    final first = lights.first;
    final off = lightings.isEmpty ? null : lightings.first;
    return [
      SceneProblem(
        entity: first,
        message: lights.length == 1
            ? '${first.name ?? 'A 2-D light'} lights nothing: the scene has '
                  'no Scene lighting on.'
            : '${lights.length} 2-D lights light nothing: the scene has no '
                  'Scene lighting on.',
        hint: 'Scene lighting (Add menu, Lighting) turns 2-D lighting on.',
        fixes: [
          if (off != null)
            ProblemFix(
              label: 'Turn the Scene lighting on',
              apply: () {
                final edit = ComponentEdit.begin(scope, off);
                off.enabled = true;
                edit.commit('Turn on Scene lighting');
              },
            )
          else
            ProblemFix(
              label: 'Add Scene lighting',
              apply: () => scope.history.push(
                CreateEntitiesCommand(
                  label: 'Add Scene lighting',
                  world: scope.world,
                  sceneState: scope.sceneState,
                  specs: [
                    EntitySpec(
                      name: scope.entities.uniqueName('Lighting'),
                      componentsJson: [
                        for (final c in <jge.Component>[
                          jge.TransformComponent(),
                          jge.LayerComponent(),
                          jge.Lighting2D(),
                        ])
                          ?scope.codec.encode(c),
                      ],
                      codec: scope.codec,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  /// Shift+L for [toggleId].
  static List<KeyBinding> get keyBindings => const [
    KeyBinding(LogicalKeyboardKey.keyL, toggleId, shift: true),
  ];
}

/// In a 2-D scene: how far a selected light reaches — a ring, and a spot's
/// cone — and the outline of a selected shadow caster.
class Light2DOverlay extends ViewportOverlay {
  // How far a selected light reaches.
  @override
  GizmoKind get gizmoKind => GizmoKind.reach;

  @override
  String get id => 'lighting.lights2D';

  @override
  String get label => '2-D light reach';

  @override
  void paint(ViewportOverlayContext context) {
    if (!context.view.isPlanar) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BuiltInLighting2DContributions.color.withValues(alpha: 0.9);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BuiltInLighting2DContributions.color.withValues(alpha: 0.45);
    for (final entity in context.world.query([
      jge.TransformComponent,
      jge.Light2D,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final light = entity.getComponent<jge.Light2D>()!;
      final t = entity.getComponent<jge.TransformComponent>()!;
      final centre = t.position;
      if (light.kind == jge.Light2DKind.spot) {
        final half = light.coneAngle * math.pi / 360;
        _arc(
          context,
          centre,
          light.radius,
          t.angle - half,
          t.angle + half,
          ring,
        );
        for (final a in [t.angle - half, t.angle + half]) {
          _line(context, centre, light.radius, a, ring);
        }
        _line(context, centre, light.radius, t.angle, faint);
      } else {
        _arc(context, centre, light.radius, 0, 2 * math.pi, ring);
      }
    }
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF90A4AE);
    for (final entity in context.world.query([
      jge.ShadowCaster2D,
      jge.RenderableComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final renderable = entity
          .getComponent<jge.RenderableComponent>()!
          .renderable;
      var bounds = renderable.getBounds();
      if (bounds == null) continue;
      if (!renderable.boundsAreWorldSpace) {
        bounds = bounds.shift(
          Offset(renderable.position.x, renderable.position.y),
        );
      }
      final corners = [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomRight,
        bounds.bottomLeft,
      ];
      Offset? first, last;
      for (final c in corners) {
        final p = context.project(jge.Vector3(c.dx, c.dy, 0));
        if (p == null) continue;
        first ??= p;
        if (last != null) context.canvas.drawLine(last, p, outline);
        last = p;
      }
      if (first != null && last != null) {
        context.canvas.drawLine(last, first, outline);
      }
    }
  }

  static const int _steps = 48;

  static void _arc(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    double from,
    double to,
    Paint paint,
  ) {
    final point = jge.Vector3.zero();
    Offset? last;
    final steps = math.max(4, (_steps * (to - from) / (2 * math.pi)).ceil());
    for (var i = 0; i <= steps; i++) {
      final a = from + (to - from) * i / steps;
      point.setValues(
        centre.x + math.cos(a) * radius,
        centre.y + math.sin(a) * radius,
        0,
      );
      final screen = context.project(point);
      if (screen != null && last != null) {
        context.canvas.drawLine(last, screen, paint);
      }
      last = screen;
    }
  }

  static void _line(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    double angle,
    Paint paint,
  ) {
    final from = context.project(centre);
    final to = context.project(
      jge.Vector3(
        centre.x + math.cos(angle) * radius,
        centre.y + math.sin(angle) * radius,
        0,
      ),
    );
    if (from != null && to != null) context.canvas.drawLine(from, to, paint);
  }
}
