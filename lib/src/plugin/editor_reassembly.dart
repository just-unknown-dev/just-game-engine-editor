part of 'just_game_editor_plugin.dart';

/// Hot reload: the components brought up to definitions a reload changed.
extension PluginReassembly on JustGameEditorPlugin {
  /// Each definition's fields — name and kind — by type: enough to tell
  /// which ones a reload changed.
  Map<String, List<(String, String)>> _definitionShapes() => {
    for (final d in scope.definitions.definitions)
      d.type: [for (final f in d.fields) (f.name, f.kind.id)],
  };

  /// Brings the scene's components up to definitions a reload changed.
  ///
  /// A component made before its class gained a field may not be able to
  /// read it — its value was never set. Such a one is made again from what
  /// it holds, through the new definition, as Stop puts a component back; the
  /// new field takes its default. One that reads every field is kept as it
  /// is, since undo steps hold it. Left alone during a play-test: Stop
  /// restores through the new definitions anyway.
  ({List<String> types, int rebuilt}) _adoptChangedDefinitions(
    Map<String, List<(String, String)>> before,
  ) {
    final changed = <String>{};
    for (final d in scope.definitions.definitions) {
      final was = before[d.type];
      if (was == null) continue;
      final now = [for (final f in d.fields) (f.name, f.kind.id)];
      if (!listEquals(was, now)) changed.add(d.type);
    }
    var rebuilt = 0;
    if (changed.isEmpty || !engine.isInitialized || playController.isRunning) {
      return (types: changed.toList(), rebuilt: rebuilt);
    }
    for (final entity in engine.world.entities.toList()) {
      for (final component in entity.components.toList()) {
        final d = scope.definitions.definitionFor(component);
        if (d == null || !changed.contains(d.type)) continue;
        if (JustGameEditorPlugin._readsEveryField(d, component)) continue;
        final fields = <String, Object?>{};
        for (final f in d.fields) {
          try {
            fields[f.name] = f.encodeFrom(component);
          } on Object {
            // The field it never had: the new instance's default.
          }
        }
        entity.addComponent(d.decode({'type': d.type, 'fields': fields}));
        rebuilt++;
      }
    }
    return (types: changed.toList(), rebuilt: rebuilt);
  }
}
