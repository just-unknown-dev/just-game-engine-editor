import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_colours/just_colours.dart';
import '../dialogs/add_component_picker.dart';
import '../theme/editor_theme.dart';
import '../widgets/scrubbable_number_field.dart';
import '../../core/services/color_history_service.dart';
import '../../core/state/editor_scene_state.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

/// Inspector panel that shows and edits components on the selected entity.
class EntityInspectorPanel extends StatelessWidget {
  const EntityInspectorPanel({
    super.key,
    required this.sceneState,
    required this.world,
    required this.onDetachFromParent,
    required this.onGroupSelection,
  });

  final EditorSceneState sceneState;
  final World world;
  final void Function(Entity entity) onDetachFromParent;
  final VoidCallback onGroupSelection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sceneState,
      builder: (context, _) {
        if (sceneState.hasMultiSelection) {
          return _MultiSelectionPanel(
            sceneState: sceneState,
            onGroupSelection: onGroupSelection,
          );
        }
        final entity = sceneState.selectedEntity;
        if (entity == null) {
          return const Center(
            child: Text(
              'No entity selected',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 12),
            ),
          );
        }
        return _EntityInspector(
          key: ValueKey(entity.id),
          entity: entity,
          sceneState: sceneState,
          world: world,
          onDetachFromParent: onDetachFromParent,
        );
      },
    );
  }
}

// ── Multi-selection panel ─────────────────────────────────────────────────────

class _MultiSelectionPanel extends StatelessWidget {
  const _MultiSelectionPanel({
    required this.sceneState,
    required this.onGroupSelection,
  });

  final EditorSceneState sceneState;
  final VoidCallback onGroupSelection;

  @override
  Widget build(BuildContext context) {
    final count = sceneState.multiSelectedIds.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$count entities selected',
            style: const TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onGroupSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: EditorTheme.buttonBg,
              foregroundColor: EditorTheme.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 14),
            label: Text(
              'Group $count entities',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-entity inspector ──────────────────────────────────────────────────────

class _EntityInspector extends StatelessWidget {
  const _EntityInspector({
    super.key,
    required this.entity,
    required this.sceneState,
    required this.world,
    required this.onDetachFromParent,
  });

  final Entity entity;
  final EditorSceneState sceneState;
  final World world;
  final void Function(Entity entity) onDetachFromParent;

  void _removeComponent<T extends Component>() {
    entity.removeComponent<T>();
    sceneState.markDirty();
    sceneState.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    // ── Core ─────────────────────────────────────────────────────────────────
    final transform = entity.getComponent<TransformComponent>();
    if (transform != null) {
      sections.add(
        _TransformSection(
          transform: transform,
          sceneState: sceneState,
          entity: entity,
        ),
      );
    }

    final velocity = entity.getComponent<VelocityComponent>();
    if (velocity != null) {
      sections.add(
        _VelocitySection(
          vel: velocity,
          sceneState: sceneState,
          onDelete: () => _removeComponent<VelocityComponent>(),
        ),
      );
    }

    // ── Shape / Renderable ───────────────────────────────────────────────────
    // All shape components (Circle/Rectangle/Capsule/Line/Polygon) override
    // componentType → RenderableComponent, so they are stored under that key.
    final renderable = entity.getComponent<RenderableComponent>();
    if (renderable is RectangleComponent) {
      sections.add(
        _RectangleSection(
          comp: renderable,
          sceneState: sceneState,
          onDelete: () => _removeComponent<RenderableComponent>(),
        ),
      );
    } else if (renderable is CircleComponent) {
      sections.add(
        _CircleSection(
          comp: renderable,
          sceneState: sceneState,
          onDelete: () => _removeComponent<RenderableComponent>(),
        ),
      );
    } else if (renderable is CapsuleComponent) {
      sections.add(
        _CapsuleSection(
          comp: renderable,
          sceneState: sceneState,
          onDelete: () => _removeComponent<RenderableComponent>(),
        ),
      );
    } else if (renderable is LineComponent) {
      sections.add(
        _LineSection(
          comp: renderable,
          sceneState: sceneState,
          onDelete: () => _removeComponent<RenderableComponent>(),
        ),
      );
    } else if (renderable is PolygonComponent) {
      sections.add(
        _PolygonSection(
          comp: renderable,
          sceneState: sceneState,
          onDelete: () => _removeComponent<RenderableComponent>(),
        ),
      );
    }

    // ── Gameplay ─────────────────────────────────────────────────────────────
    final tag = entity.getComponent<TagComponent>();
    if (tag != null) {
      sections.add(
        _TagSection(
          comp: tag,
          entity: entity,
          sceneState: sceneState,
          onDelete: () => _removeComponent<TagComponent>(),
        ),
      );
    }

    final health = entity.getComponent<HealthComponent>();
    if (health != null) {
      sections.add(
        _HealthSection(
          comp: health,
          sceneState: sceneState,
          onDelete: () => _removeComponent<HealthComponent>(),
        ),
      );
    }

    final lifetime = entity.getComponent<LifetimeComponent>();
    if (lifetime != null) {
      sections.add(
        _LifetimeSection(
          comp: lifetime,
          entity: entity,
          sceneState: sceneState,
          onDelete: () => _removeComponent<LifetimeComponent>(),
        ),
      );
    }

    // ── Rendering ────────────────────────────────────────────────────────────
    final sprite = entity.getComponent<SpriteComponent>();
    if (sprite != null) {
      sections.add(
        _SpriteSection(
          comp: sprite,
          sceneState: sceneState,
          onDelete: () => _removeComponent<SpriteComponent>(),
        ),
      );
    }

    // ── Camera / Input ───────────────────────────────────────────────────────
    final camFollow = entity.getComponent<CameraFollowComponent>();
    if (camFollow != null) {
      sections.add(
        _CameraFollowSection(
          comp: camFollow,
          sceneState: sceneState,
          onDelete: () => _removeComponent<CameraFollowComponent>(),
        ),
      );
    }

    if (entity.hasComponent<InputComponent>()) {
      sections.add(
        _MarkerSection(
          title: 'Input',
          onDelete: () => _removeComponent<InputComponent>(),
        ),
      );
    }

    if (entity.hasComponent<EffectComponent>()) {
      sections.add(
        _MarkerSection(
          title: 'Effects',
          onDelete: () => _removeComponent<EffectComponent>(),
        ),
      );
    }

    // ── Physics ───────────────────────────────────────────────────────────
    final physics = entity.getComponent<PhysicsBodyComponent>();
    if (physics != null) {
      sections.add(
        _PhysicsBodySection(
          comp: physics,
          sceneState: sceneState,
          onDelete: () => _removeComponent<PhysicsBodyComponent>(),
        ),
      );
    }

    // ── Animation ─────────────────────────────────────────────────────────
    final animState = entity.getComponent<AnimationStateComponent>();
    if (animState != null) {
      sections.add(
        _AnimationStateSection(
          comp: animState,
          sceneState: sceneState,
          onDelete: () => _removeComponent<AnimationStateComponent>(),
        ),
      );
    }

    // ── Audio ─────────────────────────────────────────────────────────────
    final audioSource = entity.getComponent<AudioSourceComponent>();
    if (audioSource != null) {
      sections.add(
        _AudioSourceSection(
          comp: audioSource,
          sceneState: sceneState,
          onDelete: () => _removeComponent<AudioSourceComponent>(),
        ),
      );
    }

    final audioStream = entity.getComponent<AudioStreamComponent>();
    if (audioStream != null) {
      sections.add(
        _AudioStreamSection(
          comp: audioStream,
          sceneState: sceneState,
          onDelete: () => _removeComponent<AudioStreamComponent>(),
        ),
      );
    }

    // ── Hierarchy ─────────────────────────────────────────────────────────
    final childrenComp = entity.getComponent<ChildrenComponent>();
    if (childrenComp != null) {
      sections.add(
        _ChildrenSection(
          comp: childrenComp,
          world: world,
          onDelete: () => _removeComponent<ChildrenComponent>(),
        ),
      );
    }

    final parentComp = entity.getComponent<ParentComponent>();
    if (parentComp != null) {
      sections.add(
        _ParentSection(
          comp: parentComp,
          world: world,
          onDetach: () => onDetachFromParent(entity),
          onDelete: () => _removeComponent<ParentComponent>(),
        ),
      );
    }

    // ── Joystick ──────────────────────────────────────────────────────────
    if (entity.hasComponent<JoystickInputComponent>()) {
      sections.add(
        _MarkerSection(
          title: 'Joystick Input',
          onDelete: () => _removeComponent<JoystickInputComponent>(),
        ),
      );
    }

    // ── UI ────────────────────────────────────────────────────────────────
    final textComp = entity.getComponent<TextComponent>();
    if (textComp != null) {
      sections.add(
        _TextSection(
          comp: textComp,
          sceneState: sceneState,
          onDelete: () => _removeComponent<TextComponent>(),
        ),
      );
    }

    final buttonComp = entity.getComponent<ButtonComponent>();
    if (buttonComp != null) {
      sections.add(
        _ButtonSection(
          comp: buttonComp,
          sceneState: sceneState,
          onDelete: () => _removeComponent<ButtonComponent>(),
        ),
      );
    }

    final linearProgress = entity.getComponent<LinearProgressComponent>();
    if (linearProgress != null) {
      sections.add(
        _LinearProgressSection(
          comp: linearProgress,
          sceneState: sceneState,
          onDelete: () => _removeComponent<LinearProgressComponent>(),
        ),
      );
    }

    final circularProgress = entity.getComponent<CircularProgressComponent>();
    if (circularProgress != null) {
      sections.add(
        _CircularProgressSection(
          comp: circularProgress,
          sceneState: sceneState,
          onDelete: () => _removeComponent<CircularProgressComponent>(),
        ),
      );
    }

    final uiComp = entity.getComponent<UIComponent>();
    if (uiComp != null) {
      sections.add(
        _UISection(
          comp: uiComp,
          sceneState: sceneState,
          onDelete: () => _removeComponent<UIComponent>(),
        ),
      );
    }

    // ── Add Component picker (search + grouped results) ─────────────────────
    sections.add(AddComponentPicker(entity: entity, sceneState: sceneState));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            sections[i],
          ],
        ],
      ),
    );
  }
}

// ── Transform ─────────────────────────────────────────────────────────────────

class _TransformSection extends StatefulWidget {
  const _TransformSection({
    required this.transform,
    required this.sceneState,
    required this.entity,
  });

  final TransformComponent transform;
  final EditorSceneState sceneState;
  final Entity entity;

  @override
  State<_TransformSection> createState() => _TransformSectionState();
}

class _TransformSectionState extends State<_TransformSection> {
  late TextEditingController _xCtrl, _yCtrl, _rotCtrl, _sxCtrl, _syCtrl;
  final _xF = FocusNode(),
      _yF = FocusNode(),
      _rotF = FocusNode(),
      _sxF = FocusNode(),
      _syF = FocusNode();

  @override
  void initState() {
    super.initState();
    final t = widget.transform;
    _xCtrl = TextEditingController(text: t.position.x.toStringAsFixed(1));
    _yCtrl = TextEditingController(text: t.position.y.toStringAsFixed(1));
    _rotCtrl = TextEditingController(
      text: _toDeg(t.rotation).toStringAsFixed(1),
    );
    _sxCtrl = TextEditingController(text: t.scale.x.toStringAsFixed(3));
    _syCtrl = TextEditingController(text: t.scale.y.toStringAsFixed(3));
  }

  @override
  void didUpdateWidget(_TransformSection old) {
    super.didUpdateWidget(old);
    final t = widget.transform;
    if (!_xF.hasFocus) _xCtrl.text = t.position.x.toStringAsFixed(1);
    if (!_yF.hasFocus) _yCtrl.text = t.position.y.toStringAsFixed(1);
    if (!_rotF.hasFocus) _rotCtrl.text = _toDeg(t.rotation).toStringAsFixed(1);
    if (!_sxF.hasFocus) _sxCtrl.text = t.scale.x.toStringAsFixed(3);
    if (!_syF.hasFocus) _syCtrl.text = t.scale.y.toStringAsFixed(3);
  }

  @override
  void dispose() {
    for (final c in [_xCtrl, _yCtrl, _rotCtrl, _sxCtrl, _syCtrl]) {
      c.dispose();
    }
    for (final f in [_xF, _yF, _rotF, _sxF, _syF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final x = double.tryParse(_xCtrl.text);
    final y = double.tryParse(_yCtrl.text);
    if (x != null && y != null) {
      widget.sceneState.setPosition(widget.entity, Offset(x, y));
    }
    final deg = double.tryParse(_rotCtrl.text);
    if (deg != null) {
      widget.sceneState.setRotation(widget.entity, deg * 3.14159265 / 180.0);
    }
    final sx = double.tryParse(_sxCtrl.text);
    final sy = double.tryParse(_syCtrl.text);
    if (sx != null) widget.sceneState.setScaleX(widget.entity, sx);
    if (sy != null) widget.sceneState.setScaleY(widget.entity, sy);
  }

  static double _toDeg(double rad) => rad * 180.0 / 3.14159265;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Transform',
    children: [
      _Row2(
        'X',
        _xCtrl,
        _xF,
        'Y',
        _yCtrl,
        _yF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1),
      ),
      const SizedBox(height: 6),
      _FieldRow(
        'Rotation°',
        _rotCtrl,
        _rotF,
        _commit,
        scrub: const NumberScrubConfig(step: 1, fractionDigits: 1),
      ),
      const SizedBox(height: 6),
      _Row2(
        'SX',
        _sxCtrl,
        _sxF,
        'SY',
        _syCtrl,
        _syF,
        _commit,
        scrub1: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
        scrub2: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
      ),
    ],
  );
}

// ── Velocity ──────────────────────────────────────────────────────────────────

class _VelocitySection extends StatefulWidget {
  const _VelocitySection({
    required this.vel,
    required this.sceneState,
    required this.onDelete,
  });
  final VelocityComponent vel;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_VelocitySection> createState() => _VelocitySectionState();
}

class _VelocitySectionState extends State<_VelocitySection> {
  late TextEditingController _vxCtrl, _vyCtrl, _msCtrl;
  final _vxF = FocusNode(), _vyF = FocusNode(), _msF = FocusNode();

  @override
  void initState() {
    super.initState();
    final v = widget.vel;
    _vxCtrl = TextEditingController(text: v.velocity.x.toStringAsFixed(1));
    _vyCtrl = TextEditingController(text: v.velocity.y.toStringAsFixed(1));
    _msCtrl = TextEditingController(text: v.maxSpeed.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_VelocitySection old) {
    super.didUpdateWidget(old);
    final v = widget.vel;
    if (!_vxF.hasFocus) _vxCtrl.text = v.velocity.x.toStringAsFixed(1);
    if (!_vyF.hasFocus) _vyCtrl.text = v.velocity.y.toStringAsFixed(1);
    if (!_msF.hasFocus) _msCtrl.text = v.maxSpeed.toStringAsFixed(1);
  }

  @override
  void dispose() {
    for (final c in [_vxCtrl, _vyCtrl, _msCtrl]) {
      c.dispose();
    }
    for (final f in [_vxF, _vyF, _msF]) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Velocity',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'VX',
        _vxCtrl,
        _vxF,
        'VY',
        _vyCtrl,
        _vyF,
        () {
          final x = double.tryParse(_vxCtrl.text);
          final y = double.tryParse(_vyCtrl.text);
          if (x != null && y != null) widget.vel.setVelocityXY(x, y);
          widget.sceneState.markDirty();
        },
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1),
      ),
      const SizedBox(height: 6),
      _FieldRow(
        'Max Speed',
        _msCtrl,
        _msF,
        () {
          final v = double.tryParse(_msCtrl.text);
          if (v != null) widget.vel.maxSpeed = v;
          widget.sceneState.markDirty();
        },
        scrub: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
    ],
  );
}

// ── Rectangle ─────────────────────────────────────────────────────────────────

class _RectangleSection extends StatefulWidget {
  const _RectangleSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final RectangleComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_RectangleSection> createState() => _RectangleSectionState();
}

class _RectangleSectionState extends State<_RectangleSection> {
  late TextEditingController _wCtrl, _hCtrl, _swCtrl, _crCtrl;
  final _wF = FocusNode(),
      _hF = FocusNode(),
      _swF = FocusNode(),
      _crF = FocusNode();

  @override
  void initState() {
    super.initState();
    final c = widget.comp;
    _wCtrl = TextEditingController(text: c.width.toStringAsFixed(1));
    _hCtrl = TextEditingController(text: c.height.toStringAsFixed(1));
    _swCtrl = TextEditingController(text: c.strokeWidth.toStringAsFixed(1));
    _crCtrl = TextEditingController(text: c.cornerRadius.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_RectangleSection old) {
    super.didUpdateWidget(old);
    final c = widget.comp;
    if (!_wF.hasFocus) _wCtrl.text = c.width.toStringAsFixed(1);
    if (!_hF.hasFocus) _hCtrl.text = c.height.toStringAsFixed(1);
    if (!_swF.hasFocus) _swCtrl.text = c.strokeWidth.toStringAsFixed(1);
    if (!_crF.hasFocus) _crCtrl.text = c.cornerRadius.toStringAsFixed(1);
  }

  @override
  void dispose() {
    for (final c in [_wCtrl, _hCtrl, _swCtrl, _crCtrl]) {
      c.dispose();
    }
    for (final f in [_wF, _hF, _swF, _crF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null) widget.comp.width = w;
    if (h != null) widget.comp.height = h;
    final sw = double.tryParse(_swCtrl.text);
    if (sw != null) widget.comp.strokeWidth = sw;
    final cr = double.tryParse(_crCtrl.text);
    if (cr != null) widget.comp.cornerRadius = cr;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Rectangle',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _Row2(
        'SW',
        _swCtrl,
        _swF,
        'CR',
        _crCtrl,
        _crF,
        _commit,
        scrub1: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _ShapePaintRow('Fill', widget.comp.fillStyle, (style) {
        widget.comp.fillStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 6),
      _ShapePaintRow('Stroke', widget.comp.strokeStyle, (style) {
        widget.comp.strokeStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Filled', widget.comp.filled, (v) {
        widget.comp.filled = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Circle ────────────────────────────────────────────────────────────────────

class _CircleSection extends StatefulWidget {
  const _CircleSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final CircleComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_CircleSection> createState() => _CircleSectionState();
}

class _CircleSectionState extends State<_CircleSection> {
  late TextEditingController _rCtrl, _swCtrl;
  final _rF = FocusNode(), _swF = FocusNode();

  @override
  void initState() {
    super.initState();
    _rCtrl = TextEditingController(text: widget.comp.radius.toStringAsFixed(1));
    _swCtrl = TextEditingController(
      text: widget.comp.strokeWidth.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_CircleSection old) {
    super.didUpdateWidget(old);
    if (!_rF.hasFocus) {
      _rCtrl.text = widget.comp.radius.toStringAsFixed(1);
    }
    if (!_swF.hasFocus) {
      _swCtrl.text = widget.comp.strokeWidth.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _swCtrl.dispose();
    _rF.dispose();
    _swF.dispose();
    super.dispose();
  }

  void _commit() {
    final r = double.tryParse(_rCtrl.text);
    if (r != null) widget.comp.radius = r;
    final sw = double.tryParse(_swCtrl.text);
    if (sw != null) widget.comp.strokeWidth = sw;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Circle',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'Radius',
        _rCtrl,
        _rF,
        'SW',
        _swCtrl,
        _swF,
        _commit,
        scrub1: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _ShapePaintRow('Fill', widget.comp.fillStyle, (style) {
        widget.comp.fillStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 6),
      _ShapePaintRow('Stroke', widget.comp.strokeStyle, (style) {
        widget.comp.strokeStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Filled', widget.comp.filled, (v) {
        widget.comp.filled = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Capsule ───────────────────────────────────────────────────────────────────

class _CapsuleSection extends StatefulWidget {
  const _CapsuleSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final CapsuleComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_CapsuleSection> createState() => _CapsuleSectionState();
}

class _CapsuleSectionState extends State<_CapsuleSection> {
  late TextEditingController _wCtrl, _hCtrl;
  final _wF = FocusNode(), _hF = FocusNode();

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(text: widget.comp.width.toStringAsFixed(1));
    _hCtrl = TextEditingController(text: widget.comp.height.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_CapsuleSection old) {
    super.didUpdateWidget(old);
    if (!_wF.hasFocus) _wCtrl.text = widget.comp.width.toStringAsFixed(1);
    if (!_hF.hasFocus) _hCtrl.text = widget.comp.height.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    _wF.dispose();
    _hF.dispose();
    super.dispose();
  }

  void _commit() {
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null) widget.comp.width = w;
    if (h != null) widget.comp.height = h;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Capsule',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _ShapePaintRow('Fill', widget.comp.fillStyle, (style) {
        widget.comp.fillStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 6),
      _ShapePaintRow('Stroke', widget.comp.strokeStyle, (style) {
        widget.comp.strokeStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Filled', widget.comp.filled, (v) {
        widget.comp.filled = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Tag ───────────────────────────────────────────────────────────────────────

class _TagSection extends StatefulWidget {
  const _TagSection({
    required this.comp,
    required this.entity,
    required this.sceneState,
    required this.onDelete,
  });
  final TagComponent comp;
  final Entity entity;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<_TagSection> {
  late TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.comp.tag);
  }

  @override
  void didUpdateWidget(_TagSection old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) _ctrl.text = widget.comp.tag;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Tag',
    onDelete: widget.onDelete,
    children: [
      _FieldRow('Tag', _ctrl, _focus, () {
        // tag is final — replace the component
        widget.entity.removeComponent<TagComponent>();
        widget.entity.addComponent(TagComponent(_ctrl.text.trim()));
        widget.sceneState.markDirty();
      }),
    ],
  );
}

// ── Health ────────────────────────────────────────────────────────────────────

class _HealthSection extends StatefulWidget {
  const _HealthSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final HealthComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  late TextEditingController _hCtrl, _mhCtrl;
  final _hF = FocusNode(), _mhF = FocusNode();

  @override
  void initState() {
    super.initState();
    _hCtrl = TextEditingController(text: widget.comp.health.toStringAsFixed(1));
    _mhCtrl = TextEditingController(
      text: widget.comp.maxHealth.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_HealthSection old) {
    super.didUpdateWidget(old);
    if (!_hF.hasFocus) _hCtrl.text = widget.comp.health.toStringAsFixed(1);
    if (!_mhF.hasFocus) _mhCtrl.text = widget.comp.maxHealth.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mhCtrl.dispose();
    _hF.dispose();
    _mhF.dispose();
    super.dispose();
  }

  void _commit() {
    final h = double.tryParse(_hCtrl.text);
    final mh = double.tryParse(_mhCtrl.text);
    if (mh != null) widget.comp.maxHealth = mh;
    if (h != null) widget.comp.health = h;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Health',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'HP',
        _hCtrl,
        _hF,
        'Max',
        _mhCtrl,
        _mhF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Invulnerable', widget.comp.isInvulnerable, (v) {
        widget.comp.isInvulnerable = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Lifetime ──────────────────────────────────────────────────────────────────

class _LifetimeSection extends StatefulWidget {
  const _LifetimeSection({
    required this.comp,
    required this.entity,
    required this.sceneState,
    required this.onDelete,
  });
  final LifetimeComponent comp;
  final Entity entity;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_LifetimeSection> createState() => _LifetimeSectionState();
}

class _LifetimeSectionState extends State<_LifetimeSection> {
  late TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.comp.initialLifetime.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_LifetimeSection old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      _ctrl.text = widget.comp.initialLifetime.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Lifetime',
    onDelete: widget.onDelete,
    children: [
      _FieldRow(
        'Duration (s)',
        _ctrl,
        _focus,
        () {
          final v = double.tryParse(_ctrl.text);
          if (v != null) {
            // initialLifetime is final — replace the component
            widget.entity.removeComponent<LifetimeComponent>();
            widget.entity.addComponent(LifetimeComponent(v));
          }
          widget.sceneState.markDirty();
        },
        scrub: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0),
      ),
    ],
  );
}

// ── Sprite ────────────────────────────────────────────────────────────────────

class _SpriteSection extends StatefulWidget {
  const _SpriteSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final SpriteComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_SpriteSection> createState() => _SpriteSectionState();
}

class _SpriteSectionState extends State<_SpriteSection> {
  late TextEditingController _pathCtrl, _frameCtrl;
  final _pathF = FocusNode(), _frameF = FocusNode();

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: widget.comp.spritePath);
    _frameCtrl = TextEditingController(text: widget.comp.frame.toString());
  }

  @override
  void didUpdateWidget(_SpriteSection old) {
    super.didUpdateWidget(old);
    if (!_pathF.hasFocus) _pathCtrl.text = widget.comp.spritePath;
    if (!_frameF.hasFocus) _frameCtrl.text = widget.comp.frame.toString();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _frameCtrl.dispose();
    _pathF.dispose();
    _frameF.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Sprite',
    onDelete: widget.onDelete,
    children: [
      _FieldRow('Path', _pathCtrl, _pathF, () {
        widget.comp.spritePath = _pathCtrl.text.trim();
        widget.sceneState.markDirty();
      }),
      const SizedBox(height: 6),
      _FieldRow(
        'Frame',
        _frameCtrl,
        _frameF,
        () {
          final v = int.tryParse(_frameCtrl.text);
          if (v != null) widget.comp.frame = v;
          widget.sceneState.markDirty();
        },
        scrub: const NumberScrubConfig(step: 1, integer: true, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Flip X', widget.comp.flipX, (v) {
        widget.comp.flipX = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Flip Y', widget.comp.flipY, (v) {
        widget.comp.flipY = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Camera Follow ─────────────────────────────────────────────────────────────

class _CameraFollowSection extends StatefulWidget {
  const _CameraFollowSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final CameraFollowComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_CameraFollowSection> createState() => _CameraFollowSectionState();
}

class _CameraFollowSectionState extends State<_CameraFollowSection> {
  late TextEditingController _ldCtrl;
  final _ldF = FocusNode();

  @override
  void initState() {
    super.initState();
    _ldCtrl = TextEditingController(
      text: widget.comp.lookaheadDistance.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_CameraFollowSection old) {
    super.didUpdateWidget(old);
    if (!_ldF.hasFocus) {
      _ldCtrl.text = widget.comp.lookaheadDistance.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _ldCtrl.dispose();
    _ldF.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Camera Follow',
    onDelete: widget.onDelete,
    children: [
      _FieldRow(
        'Lookahead',
        _ldCtrl,
        _ldF,
        () {
          final v = double.tryParse(_ldCtrl.text);
          if (v != null) widget.comp.lookaheadDistance = v;
          widget.sceneState.markDirty();
        },
        scrub: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Enabled', widget.comp.enabled, (v) {
        widget.comp.enabled = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Marker (no fields) ────────────────────────────────────────────────────────

class _MarkerSection extends StatelessWidget {
  const _MarkerSection({required this.title, required this.onDelete});
  final String title;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    onDelete: onDelete,
    children: [
      const Text(
        'No editable properties',
        style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
      ),
    ],
  );
}

class _LineSection extends StatefulWidget {
  const _LineSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });

  final LineComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;

  @override
  State<_LineSection> createState() => _LineSectionState();
}

class _LineSectionState extends State<_LineSection> {
  late TextEditingController _sxCtrl, _syCtrl, _exCtrl, _eyCtrl, _swCtrl;
  final _sxF = FocusNode();
  final _syF = FocusNode();
  final _exF = FocusNode();
  final _eyF = FocusNode();
  final _swF = FocusNode();

  @override
  void initState() {
    super.initState();
    _sxCtrl = TextEditingController(
      text: widget.comp.start.dx.toStringAsFixed(1),
    );
    _syCtrl = TextEditingController(
      text: widget.comp.start.dy.toStringAsFixed(1),
    );
    _exCtrl = TextEditingController(
      text: widget.comp.end.dx.toStringAsFixed(1),
    );
    _eyCtrl = TextEditingController(
      text: widget.comp.end.dy.toStringAsFixed(1),
    );
    _swCtrl = TextEditingController(
      text: widget.comp.strokeWidth.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_LineSection old) {
    super.didUpdateWidget(old);
    if (!_sxF.hasFocus) _sxCtrl.text = widget.comp.start.dx.toStringAsFixed(1);
    if (!_syF.hasFocus) _syCtrl.text = widget.comp.start.dy.toStringAsFixed(1);
    if (!_exF.hasFocus) _exCtrl.text = widget.comp.end.dx.toStringAsFixed(1);
    if (!_eyF.hasFocus) _eyCtrl.text = widget.comp.end.dy.toStringAsFixed(1);
    if (!_swF.hasFocus) {
      _swCtrl.text = widget.comp.strokeWidth.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    for (final controller in [_sxCtrl, _syCtrl, _exCtrl, _eyCtrl, _swCtrl]) {
      controller.dispose();
    }
    for (final focus in [_sxF, _syF, _exF, _eyF, _swF]) {
      focus.dispose();
    }
    super.dispose();
  }

  void _commitPoints() {
    final sx = double.tryParse(_sxCtrl.text);
    final sy = double.tryParse(_syCtrl.text);
    final ex = double.tryParse(_exCtrl.text);
    final ey = double.tryParse(_eyCtrl.text);
    if (sx != null && sy != null) widget.comp.start = Offset(sx, sy);
    if (ex != null && ey != null) widget.comp.end = Offset(ex, ey);
    final strokeWidth = double.tryParse(_swCtrl.text);
    if (strokeWidth != null) widget.comp.strokeWidth = strokeWidth;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Line',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'Start X',
        _sxCtrl,
        _sxF,
        'Start Y',
        _syCtrl,
        _syF,
        _commitPoints,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1),
      ),
      const SizedBox(height: 6),
      _Row2(
        'End X',
        _exCtrl,
        _exF,
        'End Y',
        _eyCtrl,
        _eyF,
        _commitPoints,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1),
      ),
      const SizedBox(height: 6),
      _FieldRow(
        'Stroke',
        _swCtrl,
        _swF,
        _commitPoints,
        scrub: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _ShapePaintRow('Paint', widget.comp.strokeStyle, (style) {
        widget.comp.strokeStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Round', widget.comp.roundCaps, (value) {
        widget.comp.roundCaps = value;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

class _PolygonSection extends StatefulWidget {
  const _PolygonSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });

  final PolygonComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;

  @override
  State<_PolygonSection> createState() => _PolygonSectionState();
}

class _PolygonSectionState extends State<_PolygonSection> {
  late TextEditingController _swCtrl;
  final _swF = FocusNode();

  @override
  void initState() {
    super.initState();
    _swCtrl = TextEditingController(
      text: widget.comp.strokeWidth.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_PolygonSection old) {
    super.didUpdateWidget(old);
    if (!_swF.hasFocus) {
      _swCtrl.text = widget.comp.strokeWidth.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _swCtrl.dispose();
    _swF.dispose();
    super.dispose();
  }

  void _commit() {
    final strokeWidth = double.tryParse(_swCtrl.text);
    if (strokeWidth != null) widget.comp.strokeWidth = strokeWidth;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Polygon',
    onDelete: widget.onDelete,
    children: [
      Row(
        children: [
          const SizedBox(
            width: 52,
            child: Text(
              'Verts',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
          ),
          Text(
            '${widget.comp.vertices.length}',
            style: const TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _FieldRow(
        'Stroke',
        _swCtrl,
        _swF,
        _commit,
        scrub: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _ShapePaintRow('Fill', widget.comp.fillStyle, (style) {
        widget.comp.fillStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 6),
      _ShapePaintRow('Stroke', widget.comp.strokeStyle, (style) {
        widget.comp.strokeStyle = style;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Filled', widget.comp.filled, (value) {
        widget.comp.filled = value;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Children ──────────────────────────────────────────────────────────────────

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection({
    required this.comp,
    required this.world,
    required this.onDelete,
  });

  final ChildrenComponent comp;
  final World world;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final childNames = comp.childIds.map((id) {
      return world.getEntity(id)?.name ?? 'entity_$id';
    }).toList();

    return _Section(
      title: 'Children (${comp.childIds.length})',
      onDelete: onDelete,
      children: childNames.isEmpty
          ? [
              const Text(
                'No children yet. Drag entities onto this group to add them.',
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
              ),
            ]
          : childNames
                .map(
                  (name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 12,
                          color: EditorTheme.primaryMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          name,
                          style: const TextStyle(
                            color: EditorTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    );
  }
}

// ── Parent ────────────────────────────────────────────────────────────────────

class _ParentSection extends StatelessWidget {
  const _ParentSection({
    required this.comp,
    required this.world,
    required this.onDetach,
    required this.onDelete,
  });

  final ParentComponent comp;
  final World world;
  final VoidCallback onDetach;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final parentName = comp.parentId != null
        ? world.getEntity(comp.parentId!)?.name ?? 'entity_${comp.parentId}'
        : '(none)';
    final lo = comp.localOffset;

    return _Section(
      title: 'Parent',
      onDelete: onDelete,
      children: [
        _readonlyRow('Parent', parentName),
        _readonlyRow(
          'Local offset',
          'x: ${lo.x.toStringAsFixed(1)},  y: ${lo.y.toStringAsFixed(1)}',
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onDetach,
          icon: const Icon(
            Icons.link_off_rounded,
            size: 14,
            color: EditorTheme.error,
          ),
          label: const Text(
            'Detach from parent',
            style: TextStyle(color: EditorTheme.error, fontSize: 11),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _readonlyRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Physics Body ──────────────────────────────────────────────────────────────

class _PhysicsBodySection extends StatefulWidget {
  const _PhysicsBodySection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final PhysicsBodyComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_PhysicsBodySection> createState() => _PhysicsBodySectionState();
}

class _PhysicsBodySectionState extends State<_PhysicsBodySection> {
  late TextEditingController _massCtrl, _restCtrl, _dragCtrl;
  final _massF = FocusNode(), _restF = FocusNode(), _dragF = FocusNode();

  @override
  void initState() {
    super.initState();
    _massCtrl = TextEditingController(
      text: widget.comp.mass.toStringAsFixed(2),
    );
    _restCtrl = TextEditingController(
      text: widget.comp.restitution.toStringAsFixed(2),
    );
    _dragCtrl = TextEditingController(
      text: widget.comp.drag.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_PhysicsBodySection old) {
    super.didUpdateWidget(old);
    if (!_massF.hasFocus) {
      _massCtrl.text = widget.comp.mass.toStringAsFixed(2);
    }
    if (!_restF.hasFocus) {
      _restCtrl.text = widget.comp.restitution.toStringAsFixed(2);
    }
    if (!_dragF.hasFocus) {
      _dragCtrl.text = widget.comp.drag.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    for (final c in [_massCtrl, _restCtrl, _dragCtrl]) {
      c.dispose();
    }
    for (final f in [_massF, _restF, _dragF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final m = double.tryParse(_massCtrl.text);
    if (m != null) widget.comp.mass = m;
    final r = double.tryParse(_restCtrl.text);
    if (r != null) widget.comp.restitution = r;
    final d = double.tryParse(_dragCtrl.text);
    if (d != null) widget.comp.drag = d;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Physics Body',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'Mass',
        _massCtrl,
        _massF,
        'Rest.',
        _restCtrl,
        _restF,
        _commit,
        scrub1: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0),
        scrub2: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0),
      ),
      const SizedBox(height: 6),
      _FieldRow(
        'Drag',
        _dragCtrl,
        _dragF,
        _commit,
        scrub: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Static', widget.comp.isStatic, (v) {
        widget.comp.isStatic = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Animation State ───────────────────────────────────────────────────────

class _AnimationStateSection extends StatefulWidget {
  const _AnimationStateSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final AnimationStateComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_AnimationStateSection> createState() => _AnimationStateSectionState();
}

class _AnimationStateSectionState extends State<_AnimationStateSection> {
  late TextEditingController _nameCtrl, _framesCtrl, _durCtrl;
  final _nameF = FocusNode(), _framesF = FocusNode(), _durF = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.comp.currentAnimation);
    _framesCtrl = TextEditingController(
      text: widget.comp.frameCount.toString(),
    );
    _durCtrl = TextEditingController(
      text: widget.comp.frameDuration.toStringAsFixed(3),
    );
  }

  @override
  void didUpdateWidget(_AnimationStateSection old) {
    super.didUpdateWidget(old);
    if (!_nameF.hasFocus) {
      _nameCtrl.text = widget.comp.currentAnimation;
    }
    if (!_framesF.hasFocus) {
      _framesCtrl.text = widget.comp.frameCount.toString();
    }
    if (!_durF.hasFocus) {
      _durCtrl.text = widget.comp.frameDuration.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _framesCtrl, _durCtrl]) {
      c.dispose();
    }
    for (final f in [_nameF, _framesF, _durF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty) widget.comp.currentAnimation = name;
    final frames = int.tryParse(_framesCtrl.text);
    if (frames != null && frames > 0) widget.comp.frameCount = frames;
    final dur = double.tryParse(_durCtrl.text);
    if (dur != null && dur > 0) widget.comp.frameDuration = dur;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Animation State',
    onDelete: widget.onDelete,
    children: [
      _FieldRow('Name', _nameCtrl, _nameF, _commit),
      const SizedBox(height: 6),
      _Row2(
        'Frames',
        _framesCtrl,
        _framesF,
        'Dur(s)',
        _durCtrl,
        _durF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, integer: true, min: 1),
        scrub2: const NumberScrubConfig(step: 0.01, fractionDigits: 3, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Loop', widget.comp.loop, (v) {
        widget.comp.loop = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Playing', widget.comp.isPlaying, (v) {
        widget.comp.isPlaying = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Audio Source ──────────────────────────────────────────────────────────

class _AudioSourceSection extends StatefulWidget {
  const _AudioSourceSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final AudioSourceComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_AudioSourceSection> createState() => _AudioSourceSectionState();
}

class _AudioSourceSectionState extends State<_AudioSourceSection> {
  late TextEditingController _volCtrl, _pitchCtrl;
  final _volF = FocusNode(), _pitchF = FocusNode();

  @override
  void initState() {
    super.initState();
    _volCtrl = TextEditingController(
      text: widget.comp.volume.toStringAsFixed(2),
    );
    _pitchCtrl = TextEditingController(
      text: widget.comp.pitch.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_AudioSourceSection old) {
    super.didUpdateWidget(old);
    if (!_volF.hasFocus) {
      _volCtrl.text = widget.comp.volume.toStringAsFixed(2);
    }
    if (!_pitchF.hasFocus) {
      _pitchCtrl.text = widget.comp.pitch.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _volCtrl.dispose();
    _pitchCtrl.dispose();
    _volF.dispose();
    _pitchF.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_volCtrl.text);
    if (v != null) widget.comp.volume = v.clamp(0.0, 1.0);
    final p = double.tryParse(_pitchCtrl.text);
    if (p != null) widget.comp.pitch = p;
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Audio Source',
    onDelete: widget.onDelete,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          widget.comp.clipPath.isEmpty ? '(no path)' : widget.comp.clipPath,
          style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      _Row2(
        'Volume',
        _volCtrl,
        _volF,
        'Pitch',
        _pitchCtrl,
        _pitchF,
        _commit,
        scrub1: const NumberScrubConfig(
          step: 0.05,
          fractionDigits: 2,
          min: 0,
          max: 1,
        ),
        scrub2: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Loop', widget.comp.loop, (v) {
        widget.comp.loop = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Play on Add', widget.comp.playOnAdd, (v) {
        widget.comp.playOnAdd = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Audio Stream ──────────────────────────────────────────────────────────

class _AudioStreamSection extends StatefulWidget {
  const _AudioStreamSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final AudioStreamComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_AudioStreamSection> createState() => _AudioStreamSectionState();
}

class _AudioStreamSectionState extends State<_AudioStreamSection> {
  late TextEditingController _volCtrl;
  final _volF = FocusNode();

  @override
  void initState() {
    super.initState();
    _volCtrl = TextEditingController(
      text: widget.comp.volume.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_AudioStreamSection old) {
    super.didUpdateWidget(old);
    if (!_volF.hasFocus) _volCtrl.text = widget.comp.volume.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _volCtrl.dispose();
    _volF.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Audio Stream',
    onDelete: widget.onDelete,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          widget.comp.path.isEmpty ? '(no path)' : widget.comp.path,
          style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      _FieldRow(
        'Volume',
        _volCtrl,
        _volF,
        () {
          final v = double.tryParse(_volCtrl.text);
          if (v != null) widget.comp.volume = v.clamp(0.0, 1.0);
          widget.sceneState.markDirty();
        },
        scrub: const NumberScrubConfig(
          step: 0.05,
          fractionDigits: 2,
          min: 0,
          max: 1,
        ),
      ),
      const SizedBox(height: 6),
      _BoolRow('Loop', widget.comp.loop, (v) {
        widget.comp.loop = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Play on Add', widget.comp.playOnAdd, (v) {
        widget.comp.playOnAdd = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── UI base ───────────────────────────────────────────────────────────────

class _UISection extends StatefulWidget {
  const _UISection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final UIComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_UISection> createState() => _UISectionState();
}

class _UISectionState extends State<_UISection> {
  late TextEditingController _wCtrl, _hCtrl;
  final _wF = FocusNode(), _hF = FocusNode();

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(
      text: widget.comp.size.width.toStringAsFixed(1),
    );
    _hCtrl = TextEditingController(
      text: widget.comp.size.height.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_UISection old) {
    super.didUpdateWidget(old);
    if (!_wF.hasFocus) _wCtrl.text = widget.comp.size.width.toStringAsFixed(1);
    if (!_hF.hasFocus) _hCtrl.text = widget.comp.size.height.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    _wF.dispose();
    _hF.dispose();
    super.dispose();
  }

  void _commit() {
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null && h != null) widget.comp.size = Size(w, h);
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'UI',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
      const SizedBox(height: 6),
      _BoolRow('Visible', widget.comp.visible, (v) {
        widget.comp.visible = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
      const SizedBox(height: 4),
      _BoolRow('Enabled', widget.comp.enabled, (v) {
        widget.comp.enabled = v;
        widget.sceneState.markDirty();
        setState(() {});
      }),
    ],
  );
}

// ── Text ──────────────────────────────────────────────────────────────────

class _TextSection extends StatefulWidget {
  const _TextSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final TextComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_TextSection> createState() => _TextSectionState();
}

class _TextSectionState extends State<_TextSection> {
  late TextEditingController _textCtrl, _wCtrl, _hCtrl;
  final _textF = FocusNode(), _wF = FocusNode(), _hF = FocusNode();

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.comp.text);
    _wCtrl = TextEditingController(
      text: widget.comp.size.width.toStringAsFixed(1),
    );
    _hCtrl = TextEditingController(
      text: widget.comp.size.height.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_TextSection old) {
    super.didUpdateWidget(old);
    if (!_textF.hasFocus) _textCtrl.text = widget.comp.text;
    if (!_wF.hasFocus) _wCtrl.text = widget.comp.size.width.toStringAsFixed(1);
    if (!_hF.hasFocus) _hCtrl.text = widget.comp.size.height.toStringAsFixed(1);
  }

  @override
  void dispose() {
    for (final c in [_textCtrl, _wCtrl, _hCtrl]) {
      c.dispose();
    }
    for (final f in [_textF, _wF, _hF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    widget.comp.text = _textCtrl.text;
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null && h != null) widget.comp.size = Size(w, h);
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Text',
    onDelete: widget.onDelete,
    children: [
      _FieldRow('Text', _textCtrl, _textF, _commit),
      const SizedBox(height: 6),
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
    ],
  );
}

// ── Button ────────────────────────────────────────────────────────────────

class _ButtonSection extends StatefulWidget {
  const _ButtonSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final ButtonComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_ButtonSection> createState() => _ButtonSectionState();
}

class _ButtonSectionState extends State<_ButtonSection> {
  late TextEditingController _textCtrl, _wCtrl, _hCtrl;
  final _textF = FocusNode(), _wF = FocusNode(), _hF = FocusNode();

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.comp.text);
    _wCtrl = TextEditingController(
      text: widget.comp.size.width.toStringAsFixed(1),
    );
    _hCtrl = TextEditingController(
      text: widget.comp.size.height.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_ButtonSection old) {
    super.didUpdateWidget(old);
    if (!_textF.hasFocus) _textCtrl.text = widget.comp.text;
    if (!_wF.hasFocus) _wCtrl.text = widget.comp.size.width.toStringAsFixed(1);
    if (!_hF.hasFocus) _hCtrl.text = widget.comp.size.height.toStringAsFixed(1);
  }

  @override
  void dispose() {
    for (final c in [_textCtrl, _wCtrl, _hCtrl]) {
      c.dispose();
    }
    for (final f in [_textF, _wF, _hF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    widget.comp.text = _textCtrl.text;
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null && h != null) widget.comp.size = Size(w, h);
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Button',
    onDelete: widget.onDelete,
    children: [
      _FieldRow('Label', _textCtrl, _textF, _commit),
      const SizedBox(height: 6),
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
    ],
  );
}

// ── Linear Progress ───────────────────────────────────────────────────────

class _LinearProgressSection extends StatefulWidget {
  const _LinearProgressSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final LinearProgressComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_LinearProgressSection> createState() => _LinearProgressSectionState();
}

class _LinearProgressSectionState extends State<_LinearProgressSection> {
  late TextEditingController _progCtrl, _wCtrl, _hCtrl;
  final _progF = FocusNode(), _wF = FocusNode(), _hF = FocusNode();

  @override
  void initState() {
    super.initState();
    _progCtrl = TextEditingController(
      text: widget.comp.progress.toStringAsFixed(2),
    );
    _wCtrl = TextEditingController(
      text: widget.comp.size.width.toStringAsFixed(1),
    );
    _hCtrl = TextEditingController(
      text: widget.comp.size.height.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_LinearProgressSection old) {
    super.didUpdateWidget(old);
    if (!_progF.hasFocus) {
      _progCtrl.text = widget.comp.progress.toStringAsFixed(2);
    }
    if (!_wF.hasFocus) {
      _wCtrl.text = widget.comp.size.width.toStringAsFixed(1);
    }
    if (!_hF.hasFocus) {
      _hCtrl.text = widget.comp.size.height.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    for (final c in [_progCtrl, _wCtrl, _hCtrl]) {
      c.dispose();
    }
    for (final f in [_progF, _wF, _hF]) {
      f.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final p = double.tryParse(_progCtrl.text);
    if (p != null) widget.comp.setProgress(p);
    final w = double.tryParse(_wCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w != null && h != null) widget.comp.size = Size(w, h);
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Linear Progress',
    onDelete: widget.onDelete,
    children: [
      _FieldRow(
        'Progress',
        _progCtrl,
        _progF,
        _commit,
        scrub: const NumberScrubConfig(
          step: 0.02,
          fractionDigits: 2,
          min: 0,
          max: 1,
        ),
      ),
      const SizedBox(height: 6),
      _Row2(
        'W',
        _wCtrl,
        _wF,
        'H',
        _hCtrl,
        _hF,
        _commit,
        scrub1: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
        scrub2: const NumberScrubConfig(step: 1, fractionDigits: 1, min: 0),
      ),
    ],
  );
}

// ── Circular Progress ─────────────────────────────────────────────────────

class _CircularProgressSection extends StatefulWidget {
  const _CircularProgressSection({
    required this.comp,
    required this.sceneState,
    required this.onDelete,
  });
  final CircularProgressComponent comp;
  final EditorSceneState sceneState;
  final VoidCallback onDelete;
  @override
  State<_CircularProgressSection> createState() =>
      _CircularProgressSectionState();
}

class _CircularProgressSectionState extends State<_CircularProgressSection> {
  late TextEditingController _progCtrl, _radCtrl;
  final _progF = FocusNode(), _radF = FocusNode();

  @override
  void initState() {
    super.initState();
    _progCtrl = TextEditingController(
      text: widget.comp.progress.toStringAsFixed(2),
    );
    _radCtrl = TextEditingController(
      text: widget.comp.radius.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_CircularProgressSection old) {
    super.didUpdateWidget(old);
    if (!_progF.hasFocus) {
      _progCtrl.text = widget.comp.progress.toStringAsFixed(2);
    }
    if (!_radF.hasFocus) {
      _radCtrl.text = widget.comp.radius.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _progCtrl.dispose();
    _radCtrl.dispose();
    _progF.dispose();
    _radF.dispose();
    super.dispose();
  }

  void _commit() {
    final p = double.tryParse(_progCtrl.text);
    if (p != null) widget.comp.setProgress(p);
    final r = double.tryParse(_radCtrl.text);
    if (r != null && r > 0) widget.comp.size = Size(r * 2, r * 2);
    widget.sceneState.markDirty();
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Circular Progress',
    onDelete: widget.onDelete,
    children: [
      _Row2(
        'Progress',
        _progCtrl,
        _progF,
        'Radius',
        _radCtrl,
        _radF,
        _commit,
        scrub1: const NumberScrubConfig(
          step: 0.02,
          fractionDigits: 2,
          min: 0,
          max: 1,
        ),
        scrub2: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0),
      ),
    ],
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.onDelete});

  final String title;
  final List<Widget> children;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: EditorTheme.primaryMutedLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: EditorTheme.border),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// Two fields side by side.
class _Row2 extends StatelessWidget {
  const _Row2(
    this.label1,
    this.ctrl1,
    this.focus1,
    this.label2,
    this.ctrl2,
    this.focus2,
    this.onCommit, {
    this.scrub1,
    this.scrub2,
  });

  final String label1, label2;
  final TextEditingController ctrl1, ctrl2;
  final FocusNode focus1, focus2;
  final VoidCallback onCommit;
  final NumberScrubConfig? scrub1;
  final NumberScrubConfig? scrub2;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FieldRow(label1, ctrl1, focus1, onCommit, scrub: scrub1),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FieldRow(label2, ctrl2, focus2, onCommit, scrub: scrub2),
        ),
      ],
    );
  }
}

/// Label + text field on one row.
class _FieldRow extends StatelessWidget {
  const _FieldRow(
    this.label,
    this.ctrl,
    this.focus,
    this.onCommit, {
    this.scrub,
  });

  final String label;
  final TextEditingController ctrl;
  final FocusNode focus;
  final VoidCallback onCommit;
  final NumberScrubConfig? scrub;

  @override
  Widget build(BuildContext context) {
    if (scrub != null) {
      return ScrubbableNumberField(
        label: label,
        controller: ctrl,
        focusNode: focus,
        onCommit: onCommit,
        config: scrub!,
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              filled: true,
              fillColor: EditorTheme.surfaceDarker,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.primaryMutedLight),
              ),
            ),
            onSubmitted: (_) => onCommit(),
            onEditingComplete: onCommit,
          ),
        ),
      ],
    );
  }
}

/// Label + color swatch that opens a full HSV color wheel on tap.
class _ColorRow extends StatelessWidget {
  const _ColorRow(this.label, this.color, this.onChanged);

  final String label;
  final Color color;
  final void Function(Color) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        GestureDetector(
          onTap: () => _pickColor(context),
          child: Container(
            width: 32,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EditorTheme.border),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '#${color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}',
          style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
        ),
      ],
    );
  }

  Future<void> _pickColor(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ColorWheelDialog(initial: color, onChanged: onChanged),
    );
  }
}

class _ShapePaintRow extends StatelessWidget {
  const _ShapePaintRow(this.label, this.style, this.onChanged);

  final String label;
  final ShapePaintStyle style;
  final void Function(ShapePaintStyle) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        GestureDetector(
          onTap: () => _pickStyle(context),
          child: Container(
            width: 32,
            height: 20,
            decoration: BoxDecoration(
              color: style.gradient == null ? style.color : null,
              gradient: _toFlutterGradient(style.gradient),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EditorTheme.border),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _shapePaintSummary(style),
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _pickStyle(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ShapePaintDialog(initial: style, onChanged: onChanged),
    );
  }
}

class _ShapePaintDialog extends StatefulWidget {
  const _ShapePaintDialog({required this.initial, required this.onChanged});

  final ShapePaintStyle initial;
  final void Function(ShapePaintStyle) onChanged;

  @override
  State<_ShapePaintDialog> createState() => _ShapePaintDialogState();
}

class _ShapePaintDialogState extends State<_ShapePaintDialog> {
  late ShapePaintStyle _style;

  @override
  void initState() {
    super.initState();
    _style = widget.initial;
  }

  void _updateStyle(ShapePaintStyle style) {
    setState(() => _style = style);
    widget.onChanged(style);
  }

  void _updateGradient(ShapeGradient gradient) {
    _updateStyle(_copyShapePaintStyle(_style, gradient: gradient));
  }

  void _toggleGradient(bool enabled) {
    _updateStyle(
      _copyShapePaintStyle(
        _style,
        gradient: enabled
            ? _style.gradient ?? _defaultShapeGradient(_style.color)
            : null,
      ),
    );
  }

  void _setGradientKind(ShapeGradientKind kind) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    _updateGradient(_copyShapeGradient(gradient, kind: kind));
  }

  void _setTileMode(TileMode tileMode) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    _updateGradient(_copyShapeGradient(gradient, tileMode: tileMode));
  }

  void _setGradientColor(int index, Color color) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final colors = List<Color>.from(gradient.colors);
    colors[index] = color;
    final stops = gradient.stops?.toList();
    _updateGradient(_copyShapeGradient(gradient, colors: colors, stops: stops));
  }

  void _setGradientStop(int index, double stop) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final stops = _normalizedStops(gradient);
    stops[index] = stop.clamp(0.0, 1.0);
    _updateGradient(_copyShapeGradient(gradient, stops: stops));
  }

  void _setBeginX(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final begin = _asAlignment(gradient.begin, Alignment.centerLeft);
    _updateGradient(
      _copyShapeGradient(gradient, begin: Alignment(value, begin.y)),
    );
  }

  void _setBeginY(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final begin = _asAlignment(gradient.begin, Alignment.centerLeft);
    _updateGradient(
      _copyShapeGradient(gradient, begin: Alignment(begin.x, value)),
    );
  }

  void _setEndX(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final end = _asAlignment(gradient.end, Alignment.centerRight);
    _updateGradient(_copyShapeGradient(gradient, end: Alignment(value, end.y)));
  }

  void _setEndY(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final end = _asAlignment(gradient.end, Alignment.centerRight);
    _updateGradient(_copyShapeGradient(gradient, end: Alignment(end.x, value)));
  }

  void _setCenterX(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final center = _asAlignment(gradient.center, Alignment.center);
    _updateGradient(
      _copyShapeGradient(gradient, center: Alignment(value, center.y)),
    );
  }

  void _setCenterY(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    final center = _asAlignment(gradient.center, Alignment.center);
    _updateGradient(
      _copyShapeGradient(gradient, center: Alignment(center.x, value)),
    );
  }

  void _setRadius(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    _updateGradient(_copyShapeGradient(gradient, radius: value));
  }

  void _setStartAngle(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    _updateGradient(_copyShapeGradient(gradient, startAngle: value));
  }

  void _setEndAngle(double value) {
    final gradient = _style.gradient;
    if (gradient == null) return;
    _updateGradient(_copyShapeGradient(gradient, endAngle: value));
  }

  void _addGradientStop() {
    final gradient = _style.gradient;
    if (gradient == null || gradient.colors.length >= 4) return;
    final colors = List<Color>.from(gradient.colors)..add(gradient.colors.last);
    _updateGradient(_copyShapeGradient(gradient, colors: colors, stops: null));
  }

  void _removeGradientStop(int index) {
    final gradient = _style.gradient;
    if (gradient == null || gradient.colors.length <= 2) return;
    final colors = List<Color>.from(gradient.colors)..removeAt(index);
    _updateGradient(_copyShapeGradient(gradient, colors: colors, stops: null));
  }

  void _cancel() {
    widget.onChanged(widget.initial);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _style.gradient;
    return Dialog(
      backgroundColor: EditorTheme.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: EditorTheme.border),
      ),
      child: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Shape Paint',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ColorRow('Tint', _style.color, (color) {
                          _updateStyle(
                            _copyShapePaintStyle(_style, color: color),
                          );
                        }),
                        const SizedBox(height: 8),
                        _BoolRow('Gradient', gradient != null, _toggleGradient),
                        const SizedBox(height: 8),
                        _ShapePaintPreview(style: _style),
                        if (gradient != null) ...[
                          const SizedBox(height: 10),
                          _DropdownRow<ShapeGradientKind>(
                            label: 'Type',
                            value: gradient.kind,
                            values: ShapeGradientKind.values,
                            labelBuilder: _shapeGradientKindLabel,
                            onChanged: _setGradientKind,
                          ),
                          const SizedBox(height: 6),
                          _DropdownRow<TileMode>(
                            label: 'Tile',
                            value: gradient.tileMode,
                            values: TileMode.values,
                            labelBuilder: _tileModeLabel,
                            onChanged: _setTileMode,
                          ),
                          const SizedBox(height: 10),
                          for (int i = 0; i < gradient.colors.length; i++) ...[
                            _GradientColorRow(
                              label: 'Stop ${i + 1}',
                              color: gradient.colors[i],
                              stop: _normalizedStops(gradient)[i],
                              canRemove: gradient.colors.length > 2,
                              onChanged: (color) => _setGradientColor(i, color),
                              onStopChanged: (stop) =>
                                  _setGradientStop(i, stop),
                              onRemove: () => _removeGradientStop(i),
                            ),
                            if (i < gradient.colors.length - 1)
                              const SizedBox(height: 6),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: gradient.colors.length >= 4
                                  ? null
                                  : _addGradientStop,
                              icon: const Icon(Icons.add_rounded, size: 14),
                              label: const Text('Add stop'),
                              style: TextButton.styleFrom(
                                foregroundColor: EditorTheme.primary,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (gradient.kind == ShapeGradientKind.linear) ...[
                            _AlignmentEditor(
                              label: 'Begin',
                              alignment: _asAlignment(
                                gradient.begin,
                                Alignment.centerLeft,
                              ),
                              onXChanged: _setBeginX,
                              onYChanged: _setBeginY,
                            ),
                            const SizedBox(height: 6),
                            _AlignmentEditor(
                              label: 'End',
                              alignment: _asAlignment(
                                gradient.end,
                                Alignment.centerRight,
                              ),
                              onXChanged: _setEndX,
                              onYChanged: _setEndY,
                            ),
                          ],
                          if (gradient.kind != ShapeGradientKind.linear) ...[
                            _AlignmentEditor(
                              label: 'Center',
                              alignment: _asAlignment(
                                gradient.center,
                                Alignment.center,
                              ),
                              onXChanged: _setCenterX,
                              onYChanged: _setCenterY,
                            ),
                          ],
                          if (gradient.kind == ShapeGradientKind.radial) ...[
                            const SizedBox(height: 6),
                            _DoubleValueField(
                              label: 'Radius',
                              value: gradient.radius,
                              fractionDigits: 2,
                              step: 0.05,
                              min: 0,
                              onChanged: _setRadius,
                            ),
                          ],
                          if (gradient.kind == ShapeGradientKind.sweep) ...[
                            const SizedBox(height: 6),
                            _DoubleValueField(
                              label: 'Start',
                              value: gradient.startAngle,
                              fractionDigits: 3,
                              step: 0.1,
                              onChanged: _setStartAngle,
                            ),
                            const SizedBox(height: 6),
                            _DoubleValueField(
                              label: 'End',
                              value: gradient.endAngle,
                              fractionDigits: 3,
                              step: 0.1,
                              onChanged: _setEndAngle,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _cancel,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: EditorTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EditorTheme.buttonBg,
                        foregroundColor: EditorTheme.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientColorRow extends StatelessWidget {
  const _GradientColorRow({
    required this.label,
    required this.color,
    required this.stop,
    required this.onChanged,
    required this.onStopChanged,
    required this.canRemove,
    required this.onRemove,
  });

  final String label;
  final Color color;
  final double stop;
  final void Function(Color) onChanged;
  final ValueChanged<double> onStopChanged;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ColorRow(label, color, onChanged),
              const SizedBox(height: 6),
              _DoubleValueField(
                label: 'Pos',
                value: stop,
                fractionDigits: 2,
                step: 0.05,
                min: 0,
                max: 1,
                onChanged: onStopChanged,
              ),
            ],
          ),
        ),
        if (canRemove) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.remove_circle_outline_rounded,
              size: 16,
              color: EditorTheme.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _ShapePaintPreview extends StatelessWidget {
  const _ShapePaintPreview({required this.style});

  final ShapePaintStyle style;

  @override
  Widget build(BuildContext context) {
    final gradient = _toFlutterGradient(style.gradient);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Preview',
          style: TextStyle(
            color: EditorTheme.primaryMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 28,
          decoration: BoxDecoration(
            color: gradient == null ? style.color : Colors.transparent,
            gradient: gradient,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: EditorTheme.border),
          ),
          child: gradient == null
              ? null
              : ColorFiltered(
                  colorFilter: ColorFilter.mode(style.color, style.blendMode),
                  child: Container(color: Colors.white),
                ),
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.values,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: EditorTheme.surfaceDarker,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EditorTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: EditorTheme.dialogBg,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: values
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item,
                        child: Text(labelBuilder(item)),
                      ),
                    )
                    .toList(),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlignmentEditor extends StatelessWidget {
  const _AlignmentEditor({
    required this.label,
    required this.alignment,
    required this.onXChanged,
    required this.onYChanged,
  });

  final String label;
  final Alignment alignment;
  final ValueChanged<double> onXChanged;
  final ValueChanged<double> onYChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: EditorTheme.primaryMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _DoubleValueField(
                label: 'X',
                value: alignment.x,
                fractionDigits: 2,
                step: 0.1,
                min: -1,
                max: 1,
                onChanged: onXChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DoubleValueField(
                label: 'Y',
                value: alignment.y,
                fractionDigits: 2,
                step: 0.1,
                min: -1,
                max: 1,
                onChanged: onYChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DoubleValueField extends StatefulWidget {
  const _DoubleValueField({
    required this.label,
    required this.value,
    required this.fractionDigits,
    required this.step,
    required this.onChanged,
    this.min,
    this.max,
  });

  final String label;
  final double value;
  final int fractionDigits;
  final double step;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;

  @override
  State<_DoubleValueField> createState() => _DoubleValueFieldState();
}

class _DoubleValueFieldState extends State<_DoubleValueField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_DoubleValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    var next = parsed;
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    widget.onChanged(next);
  }

  String _format(double value) => value.toStringAsFixed(widget.fractionDigits);

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      widget.label,
      _controller,
      _focusNode,
      _commit,
      scrub: NumberScrubConfig(
        step: widget.step,
        fractionDigits: widget.fractionDigits,
        min: widget.min,
        max: widget.max,
      ),
    );
  }
}

ShapePaintStyle _copyShapePaintStyle(
  ShapePaintStyle style, {
  Color? color,
  ShapeGradient? gradient,
  BlendMode? blendMode,
}) {
  return ShapePaintStyle(
    color: color ?? style.color,
    gradient: gradient,
    blendMode: blendMode ?? style.blendMode,
  );
}

ShapeGradient _defaultShapeGradient(Color seedColor) {
  return ShapeGradient.linear(colors: [seedColor, Colors.white]);
}

ShapeGradient _copyShapeGradient(
  ShapeGradient gradient, {
  ShapeGradientKind? kind,
  List<Color>? colors,
  List<double>? stops,
  AlignmentGeometry? begin,
  AlignmentGeometry? end,
  AlignmentGeometry? center,
  double? radius,
  double? startAngle,
  double? endAngle,
  TileMode? tileMode,
}) {
  final nextKind = kind ?? gradient.kind;
  final nextColors = List<Color>.from(colors ?? gradient.colors);
  final nextStops =
      stops ??
      (nextColors.length == gradient.colors.length ? gradient.stops : null);
  switch (nextKind) {
    case ShapeGradientKind.linear:
      return ShapeGradient.linear(
        colors: nextColors,
        stops: nextStops,
        begin:
            begin ??
            (gradient.kind == ShapeGradientKind.linear
                ? gradient.begin
                : Alignment.centerLeft),
        end:
            end ??
            (gradient.kind == ShapeGradientKind.linear
                ? gradient.end
                : Alignment.centerRight),
        tileMode: tileMode ?? gradient.tileMode,
      );
    case ShapeGradientKind.radial:
      return ShapeGradient.radial(
        colors: nextColors,
        stops: nextStops,
        center:
            center ??
            (gradient.kind == ShapeGradientKind.linear
                ? Alignment.center
                : gradient.center),
        radius:
            radius ??
            (gradient.kind == ShapeGradientKind.radial ? gradient.radius : 0.5),
        tileMode: tileMode ?? gradient.tileMode,
      );
    case ShapeGradientKind.sweep:
      return ShapeGradient.sweep(
        colors: nextColors,
        stops: nextStops,
        center:
            center ??
            (gradient.kind == ShapeGradientKind.linear
                ? Alignment.center
                : gradient.center),
        startAngle:
            startAngle ??
            (gradient.kind == ShapeGradientKind.sweep
                ? gradient.startAngle
                : 0.0),
        endAngle:
            endAngle ??
            (gradient.kind == ShapeGradientKind.sweep
                ? gradient.endAngle
                : 6.283185307179586),
        tileMode: tileMode ?? gradient.tileMode,
      );
  }
}

List<double> _normalizedStops(ShapeGradient gradient) {
  if (gradient.stops != null &&
      gradient.stops!.length == gradient.colors.length) {
    return List<double>.from(gradient.stops!);
  }
  if (gradient.colors.length == 1) return [0.0];
  final lastIndex = gradient.colors.length - 1;
  return List<double>.generate(
    gradient.colors.length,
    (index) => index / lastIndex,
  );
}

Gradient? _toFlutterGradient(ShapeGradient? gradient) {
  if (gradient == null) return null;
  switch (gradient.kind) {
    case ShapeGradientKind.linear:
      return LinearGradient(
        begin: _asAlignment(gradient.begin, Alignment.centerLeft),
        end: _asAlignment(gradient.end, Alignment.centerRight),
        colors: gradient.colors,
        stops: gradient.stops,
        tileMode: gradient.tileMode,
      );
    case ShapeGradientKind.radial:
      return RadialGradient(
        center: _asAlignment(gradient.center, Alignment.center),
        radius: gradient.radius,
        colors: gradient.colors,
        stops: gradient.stops,
        tileMode: gradient.tileMode,
      );
    case ShapeGradientKind.sweep:
      return SweepGradient(
        center: _asAlignment(gradient.center, Alignment.center),
        startAngle: gradient.startAngle,
        endAngle: gradient.endAngle,
        colors: gradient.colors,
        stops: gradient.stops,
        tileMode: gradient.tileMode,
      );
  }
}

Alignment _asAlignment(AlignmentGeometry geometry, Alignment fallback) {
  return geometry is Alignment ? geometry : fallback;
}

String _shapePaintSummary(ShapePaintStyle style) {
  final gradient = style.gradient;
  if (gradient == null) {
    return '#${style.color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }
  return '${_shapeGradientKindLabel(gradient.kind)} • ${gradient.colors.length} stops';
}

String _shapeGradientKindLabel(ShapeGradientKind kind) {
  switch (kind) {
    case ShapeGradientKind.linear:
      return 'Linear';
    case ShapeGradientKind.radial:
      return 'Radial';
    case ShapeGradientKind.sweep:
      return 'Sweep';
  }
}

String _tileModeLabel(TileMode mode) {
  switch (mode) {
    case TileMode.clamp:
      return 'Clamp';
    case TileMode.repeated:
      return 'Repeated';
    case TileMode.mirror:
      return 'Mirror';
    case TileMode.decal:
      return 'Decal';
  }
}

// ── Color wheel dialog ────────────────────────────────────────────────────────

class _ColorWheelDialog extends StatefulWidget {
  const _ColorWheelDialog({required this.initial, required this.onChanged});

  final Color initial;
  final void Function(Color) onChanged;

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late Color _current;
  late TextEditingController _hexCtrl;
  bool _hexError = false;
  List<Color> _history = [];
  final ColorHistoryService _historyService = ColorHistoryService();

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _hexCtrl = TextEditingController(text: _toHexString(_current));
    _loadHistory();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _toHexString(Color c) =>
      '#${c.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}';

  Future<void> _loadHistory() async {
    final colors = await _historyService.load();
    if (mounted) setState(() => _history = colors);
  }

  void _applyColor(Color c) {
    setState(() {
      _current = c;
      _hexError = false;
    });
    final hex = _toHexString(c);
    if (_hexCtrl.text != hex) _hexCtrl.text = hex;
    widget.onChanged(c);
  }

  void _setHue(double hue) {
    final hsv = HSVColor.fromColor(_current);
    _applyColor(hsv.withHue(hue).toColor());
  }

  void _setSaturation(double saturation) {
    final hsv = HSVColor.fromColor(_current);
    _applyColor(hsv.withSaturation(saturation.clamp(0, 1)).toColor());
  }

  void _setValue(double value) {
    final hsv = HSVColor.fromColor(_current);
    _applyColor(hsv.withValue(value.clamp(0, 1)).toColor());
  }

  void _setAlpha(double alpha) {
    final hsv = HSVColor.fromColor(_current);
    _applyColor(hsv.withAlpha(alpha.clamp(0, 1)).toColor());
  }

  void _onHexChanged(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    int? argb;
    if (cleaned.length == 6) {
      argb = int.tryParse('FF$cleaned', radix: 16);
    } else if (cleaned.length == 8) {
      argb = int.tryParse(cleaned, radix: 16);
    }
    if (argb != null) {
      final color = Color(argb);
      setState(() {
        _current = color;
        _hexError = false;
      });
      widget.onChanged(color);
    } else {
      setState(() => _hexError = true);
    }
  }

  Future<void> _confirm() async {
    await _historyService.add(_current);
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() {
    widget.onChanged(widget.initial);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: EditorTheme.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: EditorTheme.border),
      ),
      child: SizedBox(
        width: 500,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pick Color',
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ColourWheel(
                  hue: HSVColor.fromColor(_current).hue,
                  onChanged: _setHue,
                  size: 180,
                ),
              ),
              const SizedBox(height: 12),
              _ChannelSlider(
                label: 'Saturation',
                value: HSVColor.fromColor(_current).saturation,
                onChanged: _setSaturation,
              ),
              _ChannelSlider(
                label: 'Value',
                value: HSVColor.fromColor(_current).value,
                onChanged: _setValue,
              ),
              _ChannelSlider(
                label: 'Alpha',
                value: HSVColor.fromColor(_current).alpha,
                onChanged: _setAlpha,
              ),
              const SizedBox(height: 12),
              // ── Editable hex field ───────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: EditorTheme.inputBg,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _hexError
                            ? EditorTheme.error
                            : EditorTheme.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'HEX',
                          style: TextStyle(
                            color: EditorTheme.primaryMuted,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _hexCtrl,
                            onChanged: _onHexChanged,
                            onSubmitted: _onHexChanged,
                            style: const TextStyle(
                              color: EditorTheme.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _current,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: EditorTheme.border),
                    ),
                  ),
                ],
              ),
              // ── Color history ────────────────────────────────────────────
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'RECENT',
                  style: TextStyle(
                    color: EditorTheme.primaryMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _history
                      .map(
                        (c) => GestureDetector(
                          onTap: () => _applyColor(c),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: c.toARGB32() == _current.toARGB32()
                                    ? EditorTheme.primary
                                    : EditorTheme.border,
                                width: c.toARGB32() == _current.toARGB32()
                                    ? 2
                                    : 1,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: EditorTheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EditorTheme.buttonBg,
                      foregroundColor: EditorTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, 1),
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Label + checkbox.
class _BoolRow extends StatelessWidget {
  const _BoolRow(this.label, this.value, this.onChanged);

  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: EditorTheme.primaryMutedLight,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: EditorTheme.border),
          ),
        ),
      ],
    );
  }
}
