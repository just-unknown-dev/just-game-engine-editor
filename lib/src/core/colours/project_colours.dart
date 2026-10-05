/// The colours the editor's pickers offer, as the editor keeps them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:just_colours/just_colours.dart';
import 'package:just_storage/just_storage.dart';

/// The palettes and gradients a project keeps, and the colours this user
/// picked lately — one [ColourLibrary] for every colour picker in the
/// editor.
///
/// Palettes and gradients belong to the game, so they are written to the
/// project's palette file ([defaultPath]) on every change and travel with
/// it. Recent colours are one person's, so they stay in this machine's
/// storage. Until a palette or gradient is saved there is no file.
class ProjectColours {
  ProjectColours({
    required this.path,
    Future<JustStandardStorage> Function()? storage,
  }) : _storage = storage;

  /// Where in a project its palette file is.
  static const String defaultPath = 'assets/project/palettes.json';

  /// The palette file of the project the editor runs in — or, for a store
  /// rooted elsewhere (a test's temporary directory), `palettes.json` there.
  static String pathFor({String? scenesRoot}) => scenesRoot == null
      ? '${Directory.current.path}/$defaultPath'
      : '$scenesRoot/palettes.json';

  static const String _recentsKey = 'editor.colour_picker.recents';

  /// Where the palette file is.
  final String path;

  final Future<JustStandardStorage> Function()? _storage;

  /// The store, opened once when first needed. A store that cannot be
  /// reached — no platform to ask where, in a test — fails quietly.
  late final Future<JustStandardStorage>? _store = () {
    final open = _storage;
    if (open == null) return null;
    try {
      return open()..ignore();
    } catch (_) {
      return null;
    }
  }();

  /// What the pickers read and change.
  final ColourLibrary library = ColourLibrary();

  /// What went wrong reading or writing the palette file, or null.
  String? get error => _error;
  String? _error;

  bool _loading = false;

  /// Reads the palette file and this user's recent colours, then follows
  /// every change.
  void load() {
    _loading = true;
    try {
      final file = File(path);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map<String, dynamic>) library.loadCollections(json);
      }
    } on FormatException catch (e) {
      _error = 'The palette file is not valid: ${e.message}';
    } on FileSystemException catch (e) {
      _error = 'Could not read $path: ${e.message}';
    } finally {
      _loading = false;
    }
    library.collectionsChanged.addListener(_writeCollections);
    library.recentsChanged.addListener(_writeRecents);
    unawaited(_readRecents());
  }

  void _writeCollections() {
    if (_loading) return;
    _error = null;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final text = const JsonEncoder.withIndent(
        '  ',
      ).convert(library.collectionsToJson());
      // Written beside and moved over, so a crash never leaves half a file.
      final saving = File('$path.saving')..writeAsStringSync('$text\n');
      saving.renameSync(path);
    } on FileSystemException catch (e) {
      _error = 'Could not write $path: ${e.message}';
    }
  }

  Future<void> _readRecents() async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await (await store).read(_recentsKey);
      if (raw == null) return;
      final json = jsonDecode(raw.toString());
      // Colours picked before the store answered come first.
      final picked = library.recentColours;
      if (json is Map<String, dynamic>) library.loadRecents(json);
      if (picked.isNotEmpty) library.addRecentColours(picked);
    } catch (_) {
      // Recent colours are a convenience: without the store there are none
      // from before, and that is all.
    }
  }

  void _writeRecents() {
    final store = _store;
    if (store == null) return;
    final text = jsonEncode(library.recentsToJson());
    unawaited(() async {
      try {
        await (await store).write(_recentsKey, text);
      } catch (_) {
        // As for reading: no store, no recent colours kept.
      }
    }());
  }

  void dispose() {
    library.collectionsChanged.removeListener(_writeCollections);
    library.recentsChanged.removeListener(_writeRecents);
    library.dispose();
  }
}
