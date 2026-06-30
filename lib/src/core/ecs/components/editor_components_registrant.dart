import 'animation/animation_state_editor_component.dart';
import 'audio/audio_source_editor_component.dart';
import 'audio/audio_stream_editor_component.dart';
import 'camera/camera_follow_editor_component.dart';
import 'core/transform_editor_component.dart';
import 'core/velocity_editor_component.dart';
import 'effects/effect_editor_component.dart';
import 'gameplay/health_editor_component.dart';
import 'gameplay/lifetime_editor_component.dart';
import 'gameplay/tag_editor_component.dart';
import 'hierarchy/children_editor_component.dart';
import 'hierarchy/parent_editor_component.dart';
import 'input/input_editor_component.dart';
import 'input/joystick_input_editor_component.dart';
import 'input/simple_movement_editor_component.dart';
import 'physics/physics_body_capsule_editor_component.dart';
import 'physics/physics_body_chain_editor_component.dart';
import 'physics/physics_body_circle_editor_component.dart';
import 'physics/physics_body_polygon_editor_component.dart';
import 'physics/physics_body_rounded_rect_editor_component.dart';
import 'physics/physics_body_segment_editor_component.dart';
import 'physics/physics_sensor_capsule_editor_component.dart';
import 'physics/physics_sensor_circle_editor_component.dart';
import 'physics/physics_sensor_rectangle_editor_component.dart';
import 'physics/distance_joint_editor_component.dart';
import 'physics/prismatic_joint_editor_component.dart';
import 'physics/weld_joint_editor_component.dart';
import 'physics/wheel_joint_editor_component.dart';
// Register rect LAST so its fields are used for all PhysicsBodyComponent inspector instances.
import 'physics/physics_body_rectangle_editor_component.dart';
import 'rendering/capsule_editor_component.dart';
import 'rendering/circle_editor_component.dart';
import 'rendering/line_editor_component.dart';
import 'rendering/polygon_editor_component.dart';
import 'rendering/rectangle_editor_component.dart';
import 'rendering/sprite_editor_component.dart';
import 'ui/button_editor_component.dart';
import 'ui/circular_progress_editor_component.dart';
import 'ui/linear_progress_editor_component.dart';
import 'ui/text_editor_component.dart';
import 'ui/ui_catalog_editor_component.dart';

import '../generator/component_registry.dart';

void registerAllEditorComponents() {
  CustomComponentRegistry.instance.registerAll([
    AnimationStateEditorComponent(),
    AudioSourceEditorComponent(),
    AudioStreamEditorComponent(),
    CameraFollowEditorComponent(),
    TransformEditorComponent(),
    VelocityEditorComponent(),
    EffectEditorComponent(),
    HealthEditorComponent(),
    LifetimeEditorComponent(),
    TagEditorComponent(),
    ChildrenEditorComponent(),
    ParentEditorComponent(),
    InputEditorComponent(),
    JoystickInputEditorComponent(),
    SimpleMovementEditorComponent(),
    PhysicsBodyCapsuleEditorComponent(),
    PhysicsBodyChainEditorComponent(),
    PhysicsBodyCircleEditorComponent(),
    PhysicsBodyPolygonEditorComponent(),
    PhysicsBodyRoundedRectEditorComponent(),
    PhysicsBodySegmentEditorComponent(),
    PhysicsSensorCapsuleEditorComponent(),
    PhysicsSensorCircleEditorComponent(),
    PhysicsSensorRectEditorComponent(),
    DistanceJointEditorComponent(),
    PrismaticJointEditorComponent(),
    WeldJointEditorComponent(),
    WheelJointEditorComponent(),
    // Rect registered last — its fields become the canonical inspector descriptor
    // for all runtime PhysicsBodyComponent instances.
    PhysicsBodyRectEditorComponent(),
    CapsuleEditorComponent(),
    CircleEditorComponent(),
    LineEditorComponent(),
    PolygonEditorComponent(),
    RectangleEditorComponent(),
    SpriteEditorComponent(),
    ButtonEditorComponent(),
    CircularProgressEditorComponent(),
    LinearProgressEditorComponent(),
    TextEditorComponent(),
    UICatalogEditorComponent(),
  ]);
}
