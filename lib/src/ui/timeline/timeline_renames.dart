/// Timeline tracks bound to an entity by its name follow it when it is
/// renamed, as tags follow a tag's rename.
library;

import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// What renaming an entity does to the timelines that name it.
abstract final class TimelineRenames {
  /// A command giving every inline timeline in [scope]'s scene that binds
  /// tracks to the name [from] the name [to] instead — to run with the
  /// rename, as one undo step. Null when no inline timeline names [from].
  ///
  /// Timeline files are left as they are: a file may be played in other
  /// scenes, where [from] is someone else.
  static EditorCommand? commandFor(EditorScope scope, String from, String to) {
    if (from.isEmpty || from == to) return null;
    final changes = <(TimelinePlayerComponent, TimelineAsset, TimelineAsset)>[];
    for (final entity in scope.world.entities) {
      final player = entity.getComponent<TimelinePlayerComponent>();
      final inline = player?.inline;
      if (player == null || inline == null) continue;
      if (player.timelinePath.trim().isNotEmpty) continue;
      final next = rebound(inline, from, to);
      if (next != null) changes.add((player, inline, next));
    }
    return changes.isEmpty
        ? null
        : _RebindCommand(scope.sceneState, from, to, changes);
  }

  /// [asset] with each track bound to the name [from] bound to [to]; null
  /// when none is.
  static TimelineAsset? rebound(TimelineAsset asset, String from, String to) {
    var changed = false;
    final tracks = [
      for (final track in asset.tracks)
        if (track.binding.kind == TrackBindingKind.name &&
            track.binding.value == from)
          () {
            changed = true;
            return track.withBase(binding: TrackBinding.name(to));
          }()
        else
          track,
    ];
    return changed ? asset.copyWith(tracks: tracks) : null;
  }
}

class _RebindCommand extends EditorCommand {
  _RebindCommand(this.sceneState, this.from, this.to, this.changes);

  final EditorSceneState sceneState;
  final String from, to;
  final List<(TimelinePlayerComponent, TimelineAsset, TimelineAsset)> changes;

  @override
  String get label => 'Timelines follow $from to $to';

  @override
  void redo() => _apply(after: true);

  @override
  void undo() => _apply(after: false);

  void _apply({required bool after}) {
    for (final (player, before, next) in changes) {
      player.inline = after ? next : before;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }
}
