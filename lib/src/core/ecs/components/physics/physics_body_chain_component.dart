import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Chain)',
  group: 'Physics',
  description: 'Static chain collider for terrain-like collision paths.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyChainEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyChainEditorComponent()
      : super(
          shape: ChainShape(
            const [Offset(-50, 0), Offset(0, -30), Offset(50, 0)],
          ),
          isStatic: true,
        );
}
