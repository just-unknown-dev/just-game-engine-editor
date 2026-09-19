import 'package:flutter/widgets.dart';

import '../ui/level_designer/level_designer_session.dart';

/// A palette group, with where it sorts. Prefabs name their category by
/// [label]; a category nobody declares sorts after the declared ones.
class PrefabCategory {
  const PrefabCategory({required this.label, this.order = 100});

  final String label;
  final int order;
}

/// A control a module adds to the designer's status bar.
class StatusBarControl {
  const StatusBarControl({
    required this.id,
    required this.build,
    this.order = 100,
  });

  final String id;

  /// Lower sorts first; the built-ins occupy 0–99.
  final int order;

  final Widget Function(BuildContext context, LevelDesignerSession session)
  build;
}

/// A collapsible section a module adds to the designer's side panel, under
/// the built-in ones.
class SidePanelSection {
  const SidePanelSection({
    required this.id,
    required this.title,
    required this.build,
    this.order = 100,
    this.expand = false,
  });

  final String id;
  final String title;

  /// Lower sorts first.
  final int order;

  /// Whether the section takes a share of the remaining height, like the
  /// prefab palette does, rather than its own height.
  final bool expand;

  final Widget Function(BuildContext context, LevelDesignerSession session)
  build;
}
