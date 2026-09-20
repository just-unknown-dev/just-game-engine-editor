import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What a file is, as far as the browser cares: how to draw it, what opens
/// it, what it can be dropped on.
enum AssetKind {
  folder('Folders'),
  image('Images'),
  sprite('Sprites'),
  scene('Scenes'),
  animator('Animators'),
  data('Data'),
  audio('Audio'),
  font('Fonts'),
  other('Other');

  const AssetKind(this.label);

  final String label;

  static AssetKind of(String path, {bool isDirectory = false}) {
    if (isDirectory) return AssetKind.folder;
    final p = path.toLowerCase();
    if (p.endsWith('.scene.json')) return AssetKind.scene;
    if (p.endsWith('.animator.json')) return AssetKind.animator;
    if (p.endsWith('.jsprite') ||
        p.endsWith('.aseprite') ||
        p.endsWith('.ase')) {
      return AssetKind.sprite;
    }
    final dot = p.lastIndexOf('.');
    final ext = dot < 0 ? '' : p.substring(dot + 1);
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'webp' || 'gif' || 'bmp' => AssetKind.image,
      'json' ||
      'yaml' ||
      'yml' ||
      'txt' ||
      'csv' ||
      'tmx' ||
      'tsx' => AssetKind.data,
      'wav' || 'mp3' || 'ogg' || 'flac' || 'm4a' => AssetKind.audio,
      'ttf' || 'otf' => AssetKind.font,
      _ => AssetKind.other,
    };
  }
}

/// One file or folder under the project's assets.
class AssetEntry {
  const AssetEntry({
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  /// Project-relative, forward slashes: `assets/sprites/hero.png`.
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  /// The folder this sits in; empty for the root.
  String get parent {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  AssetKind get kind => AssetKind.of(path, isDirectory: isDirectory);

  /// `12 B`, `3.4 KB`, `1.2 MB`.
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Every file under a project folder, kept current as the disk changes.
///
/// Paths are project-relative with forward slashes — the form components
/// store — so what the browser shows is what an inspector field wants.
class AssetIndex {
  AssetIndex({String? projectRoot, this.folder = 'assets'})
    : projectRoot = (projectRoot ?? Directory.current.path).replaceAll(
        r'\',
        '/',
      );

  final String projectRoot;

  /// The folder indexed, relative to [projectRoot].
  final String folder;

  /// Where deleted files go, so a delete can be taken back.
  static const String trashFolder = '.editor_trash';

  /// Bumped after every scan; what a view listens to.
  final ValueNotifier<int> revision = ValueNotifier(0);

  List<AssetEntry> _entries = const [];
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _rescan;
  bool _scanning = false;
  bool _scanAgain = false;

  List<AssetEntry> get entries => _entries;

  int get fileCount => _entries.where((e) => !e.isDirectory).length;

  String absolute(String relative) => '$projectRoot/$relative';

  String relative(String absolutePath) {
    final p = absolutePath.replaceAll(r'\', '/');
    return p.startsWith('$projectRoot/')
        ? p.substring(projectRoot.length + 1)
        : p;
  }

  /// Reads the folder. Overlapping calls fold into one more pass.
  Future<void> scan() async {
    if (_scanning) {
      _scanAgain = true;
      return;
    }
    _scanning = true;
    try {
      final root = Directory(absolute(folder));
      final found = <AssetEntry>[];
      if (await root.exists()) {
        await for (final e in root.list(recursive: true, followLinks: false)) {
          final path = relative(e.path);
          if (e is Directory) {
            found.add(AssetEntry(path: path, isDirectory: true));
          } else if (e is File) {
            try {
              final stat = await e.stat();
              found.add(
                AssetEntry(
                  path: path,
                  isDirectory: false,
                  size: stat.size,
                  modified: stat.modified,
                ),
              );
            } on FileSystemException {
              // Gone between the listing and the stat: skip it.
            }
          }
        }
      }
      found.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      _entries = List.unmodifiable(found);
      revision.value++;
    } finally {
      _scanning = false;
      if (_scanAgain) {
        _scanAgain = false;
        unawaited(scan());
      }
    }
  }

  /// Rescans, shortly, whenever something under the folder changes — a save
  /// from the sprite editor, a file dropped in from outside.
  void startWatching() {
    if (_watch != null) return;
    final root = Directory(absolute(folder));
    if (!root.existsSync()) return;
    try {
      _watch = root.watch(recursive: true).listen((_) {
        _rescan?.cancel();
        _rescan = Timer(const Duration(milliseconds: 250), scan);
      }, onError: (_) {});
    } on FileSystemException {
      // Watching is a convenience; Refresh still works.
    }
  }

  /// What is directly inside [dir].
  List<AssetEntry> childrenOf(String dir) => [
    for (final e in _entries)
      if (e.parent == dir) e,
  ];

  /// Files under [within] matching [query] (in the name) and [kinds] (any,
  /// when empty).
  List<AssetEntry> search(
    String query, {
    Set<AssetKind> kinds = const {},
    String? within,
  }) {
    final q = query.trim().toLowerCase();
    return [
      for (final e in _entries)
        if (!e.isDirectory &&
            (within == null || e.path.startsWith('$within/')) &&
            (kinds.isEmpty || kinds.contains(e.kind)) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
  }

  AssetEntry? entryAt(String path) {
    for (final e in _entries) {
      if (e.path == path) return e;
    }
    return null;
  }

  // ── Operations ───────────────────────────────────────────────────────────

  /// A name in [dir] that is not taken: `name`, `name 2`, `name 3`…
  String freeName(String dir, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    var candidate = name, n = 2;
    while (FileSystemEntity.typeSync(absolute('$dir/$candidate')) !=
        FileSystemEntityType.notFound) {
      candidate = '$stem $n$ext';
      n++;
    }
    return candidate;
  }

  Future<String> newFolder(String dir, {String name = 'New folder'}) async {
    final path = '$dir/${freeName(dir, name)}';
    await Directory(absolute(path)).create(recursive: true);
    await scan();
    return path;
  }

  /// Renames [path] to [newName] in the same folder. Throws
  /// [FileSystemException] when the name is taken or not a name.
  Future<String> rename(String path, String newName) async {
    final name = newName.trim();
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw FileSystemException('Not a file name', name);
    }
    final parent = path.substring(0, path.lastIndexOf('/'));
    final target = '$parent/$name';
    if (target == path) return path;
    if (FileSystemEntity.typeSync(absolute(target)) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('There is already a "$name" here', target);
    }
    final isDir = FileSystemEntity.isDirectorySync(absolute(path));
    isDir
        ? await Directory(absolute(path)).rename(absolute(target))
        : await File(absolute(path)).rename(absolute(target));
    await scan();
    return target;
  }

  Future<String> duplicate(String path) async {
    final parent = path.substring(0, path.lastIndexOf('/'));
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final copyName = dot <= 0
        ? '$name copy'
        : '${name.substring(0, dot)} copy${name.substring(dot)}';
    final target = '$parent/${freeName(parent, copyName)}';
    await File(absolute(path)).copy(absolute(target));
    await scan();
    return target;
  }

  /// Moves [path] into the project's trash folder rather than deleting it.
  /// The result restores it.
  Future<TrashedAsset> trash(String path) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final kept = '$trashFolder/$stamp/$path';
    final isDir = FileSystemEntity.isDirectorySync(absolute(path));
    await Directory(
      absolute(kept.substring(0, kept.lastIndexOf('/'))),
    ).create(recursive: true);
    isDir
        ? await Directory(absolute(path)).rename(absolute(kept))
        : await File(absolute(path)).rename(absolute(kept));
    await scan();
    return TrashedAsset._(this, path, kept, isDir);
  }

  /// Shows [path] in the system's file manager.
  Future<void> reveal(String path) async {
    final target = absolute(path);
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', target.replaceAll('/', r'\')]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', target]);
    } else {
      await Process.run('xdg-open', [File(target).parent.path]);
    }
  }

  /// Opens [path] with whatever the system associates with it.
  Future<void> openExternally(String path) async {
    final target = absolute(path);
    if (Platform.isWindows) {
      await Process.run('cmd', [
        '/c',
        'start',
        '',
        target.replaceAll('/', r'\'),
      ]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [target]);
    } else {
      await Process.run('xdg-open', [target]);
    }
  }

  void dispose() {
    _rescan?.cancel();
    _watch?.cancel();
    revision.dispose();
  }
}

/// A file in the trash, able to come back.
class TrashedAsset {
  TrashedAsset._(this._index, this.originalPath, this._keptAt, this._isDir);

  final AssetIndex _index;
  final String originalPath;
  final String _keptAt;
  final bool _isDir;

  /// Puts it back where it was; under a free name if that is taken now.
  Future<String> restore() async {
    final parent = originalPath.substring(0, originalPath.lastIndexOf('/'));
    final name = originalPath.substring(originalPath.lastIndexOf('/') + 1);
    final target = '$parent/${_index.freeName(parent, name)}';
    await Directory(_index.absolute(parent)).create(recursive: true);
    _isDir
        ? await Directory(
            _index.absolute(_keptAt),
          ).rename(_index.absolute(target))
        : await File(_index.absolute(_keptAt)).rename(_index.absolute(target));
    await _index.scan();
    return target;
  }
}

/// Which files mention an asset, and rewriting them when it moves.
///
/// Scenes, atlases and animator graphs refer to assets by path, as JSON
/// strings. That makes "who uses this?" a text search — exact, because the
/// path is matched as a whole quoted string, not a fragment.
abstract final class AssetReferences {
  static const List<String> _searched = ['.json'];

  /// The files under the index that mention [path].
  static Future<List<String>> find(AssetIndex index, String path) async {
    final needle = '"$path"';
    final out = <String>[];
    for (final e in index.entries) {
      if (e.isDirectory || e.path == path) continue;
      if (!_searched.any(e.path.toLowerCase().endsWith)) continue;
      try {
        if ((await File(
          index.absolute(e.path),
        ).readAsString()).contains(needle)) {
          out.add(e.path);
        }
      } on FileSystemException {
        // Unreadable: it cannot be said to use anything.
      }
    }
    return out;
  }

  /// Points every mention of [from] at [to]. Returns the files changed.
  static Future<List<String>> rewrite(
    AssetIndex index,
    String from,
    String to,
  ) async {
    final changed = <String>[];
    for (final file in await find(index, from)) {
      final f = File(index.absolute(file));
      await f.writeAsString(
        (await f.readAsString()).replaceAll('"$from"', '"$to"'),
      );
      changed.add(file);
    }
    return changed;
  }
}
