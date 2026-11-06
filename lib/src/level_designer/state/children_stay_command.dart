import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// An edit of some entities' own place, size or turn — a resize, a typed
/// angle — after which what hangs under them is where it was in the world,
/// done, undone and redone alike.
///
/// A child's place is kept twice: in the world, and as its offset from its
/// parent (the `ParentComponent`'s local transform), which the transform
/// hierarchy composes it from whenever the parent moves. An edit that moves
/// a parent without its children has to work their offsets out again, or
/// the next pass of the hierarchy — Play, an undo, a value typed in the
/// inspector — moves them by what the parent did, and the jump is saved.
///
/// Wraps [inner], the edit itself, which keeps its label and its merging:
/// each time it runs, the entities under the edited ones (but not edited
/// themselves) are put back where they were, and every offset involved is
/// worked out again from the world.
class ChildrenStayCommand extends EditorCommand {
  /// [inner] edits [edited] — already done, as `pushApplied` expects; call
  /// [settle] for the first time round.
  ChildrenStayCommand({
    required this.inner,
    required this.world,
    required this.sceneState,
    required Iterable<jge.Entity> edited,
  }) : ids = [for (final e in edited) e.id];

  /// The edit.
  final EditorCommand inner;

  /// The world the entities live in.
  final jge.World world;

  /// Where an entity made again since (a delete undone) is found.
  final EditorSceneState sceneState;

  /// The entities [inner] edits, as they were when it was made.
  final List<jge.EntityId> ids;

  @override
  String get label => inner.label;

  @override
  void redo() => _keepingChildren(inner.redo);

  @override
  void undo() => _keepingChildren(inner.undo);

  /// A later edit of the same entities folds in when [inner] takes it —
  /// a scrub of the angle field, say.
  @override
  bool mergeWith(EditorCommand next) {
    if (next is! ChildrenStayCommand || next.ids.length != ids.length) {
      return false;
    }
    for (var i = 0; i < ids.length; i++) {
      if (next.ids[i] != ids[i]) return false;
    }
    return inner.mergeWith(next.inner);
  }

  void _keepingChildren(void Function() run) {
    final edited = [
      for (final id in ids)
        if (world.getEntity(sceneState.currentId(id)) case final e?
            when e.isAlive)
          e,
    ];
    final kept = childrenOf(world, edited);
    final at = [for (final e in kept) TransformSnapshot.of(e)];
    run();
    for (var i = 0; i < kept.length; i++) {
      if (kept[i].isAlive) at[i].applyTo(kept[i]);
    }
    settle(world, [...edited, ...kept]);
  }

  /// The children of [edited] that are not among them and have a place of
  /// their own to keep: what an edit of [edited] alone would leave behind.
  static List<jge.Entity> childrenOf(
    jge.World world,
    Iterable<jge.Entity> edited,
  ) {
    final ids = {for (final e in edited) e.id};
    return [
      for (final e in edited)
        for (final id
            in e.getComponent<jge.ChildrenComponent>()?.childIds ??
                const <jge.EntityId>[])
          if (!ids.contains(id))
            if (world.getEntity(id) case final child?
                when child.isAlive &&
                    child.hasComponent<jge.TransformComponent>() &&
                    child.getComponent<jge.ParentComponent>()?.parentId == e.id)
              child,
    ];
  }

  /// Works out each of [entities]' offsets from its parent again from where
  /// it is in the world, so the transform hierarchy keeps it there — and
  /// what is under it where its own offsets put it.
  static void settle(jge.World world, Iterable<jge.Entity> entities) {
    final linked = [
      for (final e in entities)
        if (e.isAlive &&
            e.hasComponent<jge.TransformComponent>() &&
            e.getComponent<jge.ParentComponent>()?.parentId != null)
          e,
    ];
    // All first: then whichever is settled first, none of the others is
    // composed from an offset about to be worked out again.
    for (final e in linked) {
      e.getComponent<jge.ParentComponent>()!.invalidateLocal();
    }
    for (final e in linked) {
      world.transformHierarchy.propagateFrom(e);
    }
  }
}
