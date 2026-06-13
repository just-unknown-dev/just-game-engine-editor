import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

/// Editor-side data component describing a distance/spring joint.

@ECSComponent(
  name: 'DistanceJointComponent',
  group: 'Physics',
  description:
      'Distance/spring joint descriptor linking this entity to targetEntityName.',
)
class DistanceJointComponent extends Component {
  DistanceJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.length = 48.0,
    this.stiffness = 80.0,
    this.damping = 0.25,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  double length;
  double stiffness;
  double damping;
  bool collideConnected;
}
