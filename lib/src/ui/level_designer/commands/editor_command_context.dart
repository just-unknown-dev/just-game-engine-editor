import '../../../core/plugin/editor_plugin.dart';
import '../level_designer_session.dart';
import 'package:just_editor_core/host.dart';

/// What the editor's own commands take from a [CommandContext] beyond what
/// a module's get: the editor's session and plugin themselves.
extension EditorCommandContext on CommandContext {
  /// The open Level Designer session, if any.
  LevelDesignerSession? get designer => switch (session) {
    final LevelDesignerSession s => s,
    _ => null,
  };

  /// The plugin, when the editor dispatched the command rather than a bare
  /// designer session.
  JustGameEditorPlugin? get plugin => switch (host) {
    final JustGameEditorPlugin p => p,
    _ => null,
  };
}
