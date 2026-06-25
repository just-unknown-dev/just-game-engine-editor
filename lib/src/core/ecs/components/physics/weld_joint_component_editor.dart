import '../../generator/component_annotations.dart';
import 'weld_joint_component.dart';

@ECSComponent(
  name: 'Weld Joint',
  group: 'Physics',
  description: 'Rigid weld joint linking this entity to targetEntityName.',
  componentType: ECSComponentType.editor,
)
class WeldJointEditorComponent extends WeldJointComponent {
  WeldJointEditorComponent() : super();

  @EditorField(label: 'Target Name')
  @override
  String get targetEntityName => super.targetEntityName;
  @override
  set targetEntityName(String v) => super.targetEntityName = v.trim();

  @EditorField(label: 'Collide Connected')
  @override
  bool get collideConnected => super.collideConnected;
  @override
  set collideConnected(bool v) => super.collideConnected = v;
}
