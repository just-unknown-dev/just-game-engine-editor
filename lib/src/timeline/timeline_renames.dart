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
  ///
  /// Undone or redone, the command renames the tracks of whatever timeline
  /// each player holds then — not a copy taken now — so keys added in the
  /// Timeline after the rename survive its undo.
  static EditorCommand? commandFor(EditorScope scope, String from, String to) {
    if (from.isEmpty || from == to) return null;
    final players = <TimelinePlayerComponent>[];
    for (final entity in scope.world.entities) {
      final player = entity.getComponent<TimelinePlayerComponent>();
      final inline = player?.inline;
      if (player == null || inline == null) continue;
      if (player.timelinePath.trim().isNotEmpty) continue;
      if (rebound(inline, from, to) != null) players.add(player);
    }
    return players.isEmpty
        ? null
        : _RebindCommand(scope.sceneState, from, to, players);
  }

  /// [asset] with each track bound to the name [from] bound to [to]; null
  /// when none is.
  static TimelineAsset? rebound(TimelineAsset asset, String from, String to) {
    var changed = false;
    final tracks = [
      for (final track in asset.tracks)
        if (track.binding.kind == EntityTargetKind.name &&
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

/// Rebinds the [players]' inline timelines from [from] to [to] (redo) or
/// back (undo), applied to the timeline each holds at the time: edits made
/// in the Timeline since — which live in the player, not in the editor's
/// history — are kept either way.
class _RebindCommand extends EditorCommand {
  _RebindCommand(this.sceneState, this.from, this.to, this.players);

  final EditorSceneState sceneState;
  final String from, to;
  final List<TimelinePlayerComponent> players;

  @override
  String get label => 'Timelines follow $from to $to';

  @override
  void redo() => _apply(from, to);

  @override
  void undo() => _apply(to, from);

  void _apply(String was, String now) {
    var changed = false;
    for (final player in players) {
      final inline = player.inline;
      if (inline == null) continue;
      final next = TimelineRenames.rebound(inline, was, now);
      if (next == null) continue;
      player.inline = next;
      changed = true;
    }
    if (!changed) return;
    sceneState
      ..markDirty()
      ..refresh();
  }
}
