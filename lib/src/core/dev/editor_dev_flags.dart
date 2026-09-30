import 'package:flutter/foundation.dart' show visibleForTesting;

/// Switches for work that is built but not shipped yet.
abstract final class EditorDevFlags {
  /// Whether a scene can be authored as 3-D.
  ///
  /// The engine and editor are ready for 3-D, but 3-D authoring ships in a
  /// later release. Until then a scene saved as `mode: '3d'` opens with the
  /// 2-D view and tools — and keeps its mode when saved. Turn on for
  /// development with `--dart-define=JGE_EDITOR_ALLOW_3D_SCENES=true`.
  static bool get allow3DSceneMode => _override ?? _fromEnvironment;

  static const bool _fromEnvironment = bool.fromEnvironment(
    'JGE_EDITOR_ALLOW_3D_SCENES',
  );

  static bool? _override;

  /// Force [allow3DSceneMode] in a test; null goes back to the build's.
  @visibleForTesting
  static set allow3DSceneModeOverride(bool? value) => _override = value;
}
