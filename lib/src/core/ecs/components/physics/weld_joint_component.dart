import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

/// Editor-side data component describing a weld joint.

@ECSComponent(
  name: 'WeldJointComponent',
  group: 'Physics',
  description: 'Rigid weld joint descriptor linking to targetEntityName.',
)
class WeldJointComponent extends Component {
  WeldJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  bool collideConnected;
}
