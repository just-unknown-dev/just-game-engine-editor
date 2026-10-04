/// The project's collision layers, as the editor keeps them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

/// The project's collision layers — their names, colours, descriptions and
/// which collide — from the project's layer file
/// ([jge.PhysicsLayers.defaultPath]).
///
/// Every change writes the file and goes straight into the engine the
/// editor runs, so a game being play-tested collides by the new grid at
/// once. Until a project changes something there is no file, and the
/// defaults stand: everything on `Default`, everything colliding.
///
/// Bodies refer to a layer by its number, so naming, renaming, recolouring
/// and describing one touch only this file. Taking a layer out of use while
/// bodies are on it is `LayerRefactor`'s job: it moves them first.
class ProjectPhysicsLayers {
  ProjectPhysicsLayers({
    required this.path,
    jge.EngineContext? Function()? context,
  }) : _context = context ?? (() => null);

  /// The layer file of the project the editor runs in — or, for a store
  /// rooted elsewhere (a test's temporary directory), `physics.json` there.
  static String pathFor({String? scenesRoot}) => scenesRoot == null
      ? '${Directory.current.path}/${jge.PhysicsLayers.defaultPath}'
      : '$scenesRoot/physics.json';

  /// Where the layer file is.
  final String path;

  final jge.EngineContext? Function() _context;

  /// The layers, as last read or set.
  late final Signal<jge.PhysicsLayers> layers = Signal(
    jge.PhysicsLayers.defaults,
    debugLabel: 'physicsLayers',
  );

  jge.PhysicsLayers get value => layers.value;

  /// Whether the project has a layer file yet.
  bool get hasFile => File(path).existsSync();

  /// What went wrong reading or writing the file, or null.
  String? get error => _error;
  String? _error;

  /// Reads the layer file — the defaults without one — and hands the layers
  /// to the engine.
  void load() {
    _error = null;
    final file = File(path);
    var next = jge.PhysicsLayers.defaults;
    if (file.existsSync()) {
      try {
        next = jge.PhysicsLayers.fromJson(jsonDecode(file.readAsStringSync()));
      } on jge.UnsupportedFormatVersionException catch (e) {
        _error = e.toString();
      } on FormatException catch (e) {
        _error = 'The physics layers file is not valid: ${e.message}';
      }
    }
    _apply(next);
  }

  /// Makes [next] the project's layers: written to the file, then given to
  /// the engine.
  void set(jge.PhysicsLayers next) {
    if (next == layers.value) return;
    _error = null;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final text = const JsonEncoder.withIndent('  ').convert(next.toJson());
      // Written beside and moved over, so a crash never leaves half a file.
      final saving = File('$path.saving')..writeAsStringSync('$text\n');
      saving.renameSync(path);
    } on FileSystemException catch (e) {
      _error = 'Could not write $path: ${e.message}';
    }
    _apply(next);
  }

  // ── Changing ─────────────────────────────────────────────────────────────

  /// Why [name] cannot be a new layer, or null when it can.
  String? problemWithNew(String name) {
    if (value.firstFree == null) {
      return 'All ${jge.PhysicsLayers.count} layers are in use.';
    }
    return value.problemWithName(name);
  }

  /// Why [layer] cannot be renamed [name], or null when it can.
  String? problemWithRename(int layer, String name) {
    if (name.trim() == value.nameOf(layer)) return 'That is its name already.';
    return value.problemWithName(name, except: layer);
  }

  /// Names the first free layer [name]; its number, or null when
  /// [problemWithNew] objects.
  int? create(String name, {Color? color, String description = ''}) {
    if (problemWithNew(name) != null) return null;
    final layer = value.firstFree!;
    var next = value.withName(layer, name.trim());
    if (color != null) next = next.withColor(layer, color);
    if (description.isNotEmpty) next = next.withDescription(layer, description);
    set(next);
    return layer;
  }

  /// Renames [layer]; false when [problemWithRename] objects. Bodies keep
  /// their layer by number, so nothing else changes.
  bool rename(int layer, String name) {
    if (problemWithRename(layer, name) != null) return false;
    set(value.withName(layer, name.trim()));
    return true;
  }

  /// Shows [layer] in [color]; null for its default.
  void recolor(int layer, Color? color) => set(value.withColor(layer, color));

  /// Describes what [layer] is for.
  void describe(int layer, String description) =>
      set(value.withDescription(layer, description.trim()));

  /// Takes [layer] out of use: no name, colour or description, colliding
  /// with everything again. Bodies still on it are left there — see
  /// `LayerRefactor`, which moves them first.
  void clear(int layer) => set(value.cleared(layer));

  /// Whether layers [a] and [b] collide, both ways.
  void setCollision(int a, int b, bool collide) =>
      set(value.withCollision(a, b, collide));

  void _apply(jge.PhysicsLayers next) {
    layers.value = next;
    _context()?.physicsLayers = next;
  }

  void dispose() => layers.dispose();
}
