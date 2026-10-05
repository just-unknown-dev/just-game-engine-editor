import '../../core/scope/editor_scope.dart';
import '../level_designer/state/editor_history.dart';

/// A value shown in the scene for a while without being recorded — what a
/// colour picker writes while it is open — and then put back.
///
/// The editor is told while it shows: an autosave waits, and a save or a
/// play-test puts the value there was back first, so neither keeps a value
/// nobody chose yet. When it ends, the next edit is an undo step of its
/// own: the value kept goes through the usual recording, as one step.
class LivePreview {
  LivePreview({
    required this.read,
    required this.write,
    this.scope,
    this.history,
  });

  /// The value there is now.
  final Object? Function() read;

  /// Puts a value in place without recording it, and shows it.
  final void Function(Object? value) write;

  final EditorScope? scope;

  /// The undo stack the kept value will be recorded on; the scope's when
  /// null.
  final EditorHistory? history;

  Object? _original;
  bool _showing = false;

  /// Whether a value other than the recorded one is showing.
  bool get isShowing => _showing;

  /// Shows [value] in place of the recorded one.
  void show(Object? value) {
    if (!_showing) {
      _original = read();
      _showing = true;
      scope?.authoredStateGuards.add(restore);
      scope?.authoredStateHeld.add(_held);
    }
    write(value);
  }

  /// Puts back the value there was before [show].
  void restore() {
    if (!_showing) return;
    _showing = false;
    scope?.authoredStateGuards.remove(restore);
    scope?.authoredStateHeld.remove(_held);
    write(_original);
    (history ?? scope?.history)?.breakMerge();
  }

  bool _held() => _showing;
}
