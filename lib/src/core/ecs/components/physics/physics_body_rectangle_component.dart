import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Rect)',
  group: 'Physics',
  description: 'Rigid body with rectangle shape.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyRectangleEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyRectangleEditorComponent() : super(shape: RectangleShape(50, 50));

  @EditorField(label: 'Mass', scrubStep: 0.1, scrubFractionDigits: 2, scrubMin: 0)
  double get massValue => super.mass;
  set massValue(double v) => super.mass = v;

  @override
  @EditorField(label: 'Rest.', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0)
  double get restitution => super.restitution;
  @override
  set restitution(double v) => super.restitution = v;

  @override
  @EditorField(label: 'Drag', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0)
  double get drag => super.drag;
  @override
  set drag(double v) => super.drag = v;

  @override
  @EditorField(label: 'Static')
  bool get isStatic => super.isStatic;
  @override
  set isStatic(bool v) => super.isStatic = v;

  @override
  @EditorField(label: 'Sensor')
  bool get isSensor => super.isSensor;
  @override
  set isSensor(bool v) => super.isSensor = v;

  @override
  @EditorField(label: 'One-way')
  bool get isOneWay => super.isOneWay;
  @override
  set isOneWay(bool v) => super.isOneWay = v;

  @override
  @EditorField(label: 'Layer', scrubStep: 1.0, scrubInteger: true)
  int get layer => super.layer;
  @override
  set layer(int v) => super.layer = v;

  @override
  @EditorField(label: 'Coll. Mask', scrubStep: 1.0, scrubInteger: true)
  int get collisionMask => super.collisionMask;
  @override
  set collisionMask(int v) => super.collisionMask = v;

  @override
  @EditorField(label: 'Category', scrubStep: 1.0, scrubInteger: true)
  int get categoryBits => super.categoryBits;
  @override
  set categoryBits(int v) => super.categoryBits = v;

  @override
  @EditorField(label: 'Mask Bits', scrubStep: 1.0, scrubInteger: true)
  int get maskBits => super.maskBits;
  @override
  set maskBits(int v) => super.maskBits = v;

  @override
  @EditorField(label: 'Group Index', scrubStep: 1.0, scrubInteger: true)
  int get groupIndex => super.groupIndex;
  @override
  set groupIndex(int v) => super.groupIndex = v;
}
