/// The project's tag list, as the editor keeps it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

/// The tags a project knows, from three places:
///
/// * **the tag file** ([jge.TagLibrary.defaultPath]) — the tags people
///   made, and the colours and descriptions they set;
/// * **code** — tags the engine and each module look for by name
///   ([jge.EngineTags], `EditorModule.tags`), shown as built in: they
///   cannot be renamed or deleted, or code would go on looking for the old
///   name;
/// * **spawners** — the tags the game gives what it spawns
///   ([jge.Spawner.tags]), which exist only once the game runs. That is how
///   the editor knows a camera following `#player` in a level with no
///   player in it is not a mistake.
///
/// Until a project has a tag file, the list is the declared tags and the
/// tags its scenes already carry; the file is written with the first
/// change. Every change writes it.
class ProjectTags {
  ProjectTags({required this.path, List<jge.Spawner> Function()? spawners})
    : _spawners = spawners ?? (() => const []);

  /// The tag file of the project the editor runs in — or, for a store
  /// rooted elsewhere (a test's temporary directory), `tags.json` there.
  static String pathFor({String? scenesRoot}) => scenesRoot == null
      ? '${Directory.current.path}/${jge.TagLibrary.defaultPath}'
      : '$scenesRoot/tags.json';

  /// Where the tag file is.
  final String path;

  /// The list: the file's tags with the declared ones merged in.
  late final Signal<jge.TagLibrary> library = Signal(
    jge.TagLibrary.empty,
    debugLabel: 'projectTags',
  );

  final List<jge.Spawner> Function() _spawners;

  /// The game's spawners, as the app handed them to the editor.
  List<jge.Spawner> get spawners => _spawners();

  jge.TagLibrary _file = jge.TagLibrary.empty;
  List<jge.TagDefinition> _declared = jge.EngineTags.declared;
  bool _loaded = false;

  /// Whether the project has a tag file yet.
  bool get hasFile => File(path).existsSync();

  /// What went wrong reading the file, or null.
  String? get loadError => _loadError;
  String? _loadError;

  /// Sets the tags code declares — the engine's and every module's. Called
  /// on each registration pass.
  void setDeclared(Iterable<jge.TagDefinition> declared) {
    _declared = [...jge.EngineTags.declared, ...declared];
    _publish();
  }

  /// Reads the tag file. Without one, [seed] — the tags the project's
  /// scenes carry — stands in for it until the first change writes it.
  void load({Iterable<String> Function()? seed}) {
    _loadError = null;
    final file = File(path);
    if (file.existsSync()) {
      try {
        _file = jge.TagLibrary.fromJson(jsonDecode(file.readAsStringSync()));
      } on FormatException catch (e) {
        _loadError = 'The tag file is not valid JSON: ${e.message}';
        _file = jge.TagLibrary.empty;
      }
    } else {
      _file = jge.TagLibrary.empty.withNames(seed?.call() ?? const []);
    }
    _loaded = true;
    _publish();
  }

  void _ensureLoaded() {
    if (!_loaded) load();
  }

  void _publish() => library.value = _file.withDeclared(_declared);

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Every tag the game's spawners give.
  Set<String> get spawnedTags => {for (final s in spawners) ...s.tags};

  /// The spawners whose entities carry [tag].
  List<jge.Spawner> spawnersGiving(String tag) => [
    for (final s in spawners)
      if (s.tags.contains(tag)) s,
  ];

  /// Whether [tag] is one the project knows: listed, or given by a spawner.
  bool isKnown(String tag) {
    _ensureLoaded();
    return library.value.contains(tag) || spawnedTags.contains(tag);
  }

  /// Every tag to offer in a picker, in list order, spawned ones last.
  List<String> get names {
    _ensureLoaded();
    final listed = library.value.names.toList();
    return [
      ...listed,
      for (final t in spawnedTags)
        if (!listed.contains(t)) t,
    ];
  }

  jge.TagDefinition? operator [](String name) {
    _ensureLoaded();
    return library.value[name];
  }

  Color colorOf(String tag) => library.value.colorOf(tag);

  /// The listed tag [name] most likely meant, or null.
  String? closest(String name) => jge.TagNames.closest(name, names);

  // ── Changing ─────────────────────────────────────────────────────────────

  /// Why [name] cannot be a new tag, or null when it can.
  String? problemWithNew(String name) {
    _ensureLoaded();
    final problem = jge.TagNames.problemWith(name);
    if (problem != null) return problem;
    if (library.value.contains(name)) return 'There is already a "$name".';
    final near = library.value.nearDuplicateOf(name);
    if (near != null) {
      return 'Too close to "$near" to tell apart — use that one, or pick a '
          'clearly different name.';
    }
    return null;
  }

  /// Adds a tag; null when [problemWithNew] objects.
  jge.TagDefinition? create(
    String name, {
    Color? color,
    String description = '',
  }) {
    if (problemWithNew(name) != null) return null;
    final tag = jge.TagDefinition(
      name,
      color: color ?? jge.TagLibrary.colorFor(name),
      description: description,
    );
    _write(_file.put(tag));
    return library.value[name];
  }

  /// Adds [names] that are not listed yet, as plain tags — for tags a scene
  /// already uses. Returns how many were added.
  int adopt(Iterable<String> names) {
    _ensureLoaded();
    final missing = [
      for (final n in jge.TagNames.normalize(names))
        if (!library.value.contains(n)) n,
    ];
    if (missing.isEmpty) return 0;
    _write(_file.withNames(missing));
    return missing.length;
  }

  /// Changes a tag's colour or description.
  void update(jge.TagDefinition tag) {
    _ensureLoaded();
    _write(_file.put(tag));
  }

  /// Renames [from] in the list — not in the scenes: see `TagRefactor`.
  /// Refused for a declared tag.
  bool rename(String from, String to) {
    _ensureLoaded();
    if (library.value[from]?.isDeclared ?? false) return false;
    final source = _file.contains(from)
        ? _file
        : _file.put(library.value[from] ?? jge.TagDefinition(from));
    _write(source.rename(from, to));
    return true;
  }

  /// Takes [name] off the list. Refused for a declared tag.
  bool remove(String name) {
    _ensureLoaded();
    if (library.value[name]?.isDeclared ?? false) return false;
    _write(_file.remove(name));
    return true;
  }

  void _write(jge.TagLibrary next) {
    // What the file has written is what the list shows, declared tags
    // included, so it reads as the whole list.
    _file = next;
    _publish();
    final file = File(path);
    file.parent.createSync(recursive: true);
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(library.value.toJson());
    // Written beside and moved over, so a crash never leaves half a file.
    final saving = File('$path.saving')..writeAsStringSync('$text\n');
    saving.renameSync(path);
  }

  void dispose() => library.dispose();
}
