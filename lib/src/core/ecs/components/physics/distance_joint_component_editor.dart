import '../../generator/component_annotations.dart';
import 'distance_joint_component.dart';

@ECSComponent(
  name: 'Distance Joint',
  group: 'Physics',
  description: 'Distance/spring joint linking this entity to targetEntityName.',
  componentType: ECSComponentType.editor,
)
class DistanceJointEditorComponent extends DistanceJointComponent {
  DistanceJointEditorComponent() : super();

  @EditorField(label: 'Target Name')
  @override
  String get targetEntityName => super.targetEntityName;
  @override
  set targetEntityName(String v) => super.targetEntityName = v.trim();

  @EditorField(label: 'Length', scrubStep: 1.0, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get length => super.length;
  @override
  set length(double v) => super.length = v;

  @EditorField(label: 'Stiffness', scrubStep: 1.0, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get stiffness => super.stiffness;
  @override
  set stiffness(double v) => super.stiffness = v;

  @EditorField(label: 'Damping', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get damping => super.damping;
  @override
  set damping(double v) => super.damping = v;

  @EditorField(label: 'Collide Connected')
  @override
  bool get collideConnected => super.collideConnected;
  @override
  set collideConnected(bool v) => super.collideConnected = v;
}
