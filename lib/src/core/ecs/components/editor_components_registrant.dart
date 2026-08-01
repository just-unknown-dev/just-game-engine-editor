import 'animation/animation_controller_editor_component.dart';
import 'animation/animation_state_editor_component.dart';
import 'audio/audio_source_editor_component.dart';
import 'audio/audio_stream_editor_component.dart';
import 'camera/camera_editor_component.dart';
import 'camera/camera_follow_editor_component.dart';
import 'core/transform_editor_component.dart';
import 'core/velocity_editor_component.dart';
import 'effects/effect_editor_component.dart';
import 'gameplay/health_editor_component.dart';
import 'gameplay/lifetime_editor_component.dart';
import 'gameplay/spawn_editor_component.dart';
import 'gameplay/tag_editor_component.dart';
import 'hierarchy/children_editor_component.dart';
import 'hierarchy/parent_editor_component.dart';
import 'input/input_editor_component.dart';
import 'input/joystick_input_editor_component.dart';
import 'input/simple_movement_editor_component.dart';
import 'physics/physics_body_editor_component.dart';
import 'physics/distance_joint_editor_component.dart';
import 'physics/prismatic_joint_editor_component.dart';
import 'physics/weld_joint_editor_component.dart';
import 'physics/wheel_joint_editor_component.dart';
import 'rendering/capsule_editor_component.dart';
import 'rendering/circle_editor_component.dart';
import 'rendering/line_editor_component.dart';
import 'rendering/polygon_editor_component.dart';
import 'rendering/rectangle_editor_component.dart';
import 'rendering/animated_sprite_editor_component.dart';
import 'rendering/sprite_editor_component.dart';
import 'ui/button_editor_component.dart';
import 'ui/elliptical_progress_editor_component.dart';
import 'ui/linear_progress_editor_component.dart';
import 'ui/text_editor_component.dart';
import 'ui/ui_catalog_editor_component.dart';

import '../generator/component_registry.dart';

void registerAllEditorComponents() {
  CustomComponentRegistry.instance.registerAll([
    AnimationControllerEditorComponent(),
    AnimationStateEditorComponent(),
    AudioSourceEditorComponent(),
    AudioStreamEditorComponent(),
    CameraEditorComponent(),
    CameraFollowEditorComponent(),
    TransformEditorComponent(),
    VelocityEditorComponent(),
    EffectEditorComponent(),
    HealthEditorComponent(),
    LifetimeEditorComponent(),
    SpawnEditorComponent(),
    TagEditorComponent(),
    ChildrenEditorComponent(),
    ParentEditorComponent(),
    InputEditorComponent(),
    JoystickInputEditorComponent(),
    SimpleMovementEditorComponent(),
    PhysicsBodyEditorComponent(),
    DistanceJointEditorComponent(),
    PrismaticJointEditorComponent(),
    WeldJointEditorComponent(),
    WheelJointEditorComponent(),
    CapsuleEditorComponent(),
    CircleEditorComponent(),
    LineEditorComponent(),
    PolygonEditorComponent(),
    RectangleEditorComponent(),
    AnimatedSpriteEditorComponent(),
    SpriteEditorComponent(),
    ButtonEditorComponent(),
    EllipticalProgressEditorComponent(),
    LinearProgressEditorComponent(),
    TextEditorComponent(),
    UICatalogEditorComponent(),
  ]);
}
