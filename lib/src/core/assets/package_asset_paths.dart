import 'dart:convert';
import 'dart:io';

/// A package whose assets a project can use, as `packages/<name>/…`.
class PackageAssetRoot {
  const PackageAssetRoot({
    required this.name,
    required this.path,
    required this.assetFolders,
    required this.inPubCache,
    this.fromStore = false,
  });

  /// The package's name: the second part of its asset keys.
  final String name;

  /// Its folder, absolute, with `/` between parts.
  final String path;

  /// The folders its pubspec ships (`flutter: assets:` entries ending in
  /// `/`), relative to [path]. Flutter does not reach into their
  /// subfolders.
  final List<String> assetFolders;

  /// In pub's shared cache: read-only, and shared by every project.
  final bool inPubCache;

  /// Installed by the Asset Store (listed in `just_store.lock.json`).
  final bool fromStore;

  /// Whether files may be written here: not in pub's cache.
  bool get isWritable => !inPubCache;
}

/// Where asset paths live on disk.
///
/// Most asset paths are relative to the project: `assets/sprites/hero.png`.
/// A package's assets are keyed `packages/<name>/<path in the package>` —
/// Flutter's own key for them, the same in the editor and the shipped game —
/// but the package may sit anywhere: in `packages/characters/knight/`, where
/// the Asset Store installs items, or in pub's cache. This finds it, from
/// the store's lockfile and pub's `.dart_tool/package_config.json`.
///
/// One instance per project root ([of]); it re-reads those files when they
/// change, at most twice a second.
class PackageAssetPaths {
  PackageAssetPaths._(this.root);

  static final Map<String, PackageAssetPaths> _byRoot = {};

  /// The resolver for the project in [root] (the working directory by
  /// default).
  static PackageAssetPaths of([String? root]) {
    final r = _normal(root ?? Directory.current.path);
    return _byRoot.putIfAbsent(r, () => PackageAssetPaths._(r));
  }

  /// The project folder, absolute, with `/` between parts.
  final String root;

  /// Whether [key] is a package asset key, `packages/<name>/…`.
  static bool isPackageKey(String key) =>
      key.startsWith('packages/') && key.indexOf('/', 9) > 9;

  /// The package [key] belongs to, or null for a project path.
  static String? packageOf(String key) {
    if (!isPackageKey(key)) return null;
    return key.substring(9, key.indexOf('/', 9));
  }

  /// The absolute path of [key], with `/` between parts.
  String absolute(String key) {
    final k = key.replaceAll(r'\', '/');
    final name = packageOf(k);
    if (name != null) {
      final pkg = packages[name];
      if (pkg != null) return '${pkg.path}/${k.substring(10 + name.length)}';
    }
    return '$root/$k';
  }

  /// The file at [key].
  File file(String key) => File(absolute(key));

  /// The asset key of the file at [absolutePath]: `packages/<name>/…` inside
  /// a package, else relative to the project; null when it is neither.
  String? keyFor(String absolutePath) {
    final p = _normal(absolutePath);
    String? best;
    var bestLength = -1;
    for (final pkg in packages.values) {
      final prefix = '${pkg.path}/';
      if (_startsWith(p, prefix) && prefix.length > bestLength) {
        best = 'packages/${pkg.name}/${p.substring(prefix.length)}';
        bestLength = prefix.length;
      }
    }
    if (best != null) return best;
    final prefix = '$root/';
    return _startsWith(p, prefix) ? p.substring(prefix.length) : null;
  }

  /// Whether [key] may be written: project files and packages outside
  /// pub's cache.
  bool isWritable(String key) {
    final name = packageOf(key);
    return name == null || (packages[name]?.isWritable ?? true);
  }

  /// Whether the game ships [key]: for a package key, the package is
  /// resolved and its pubspec ships the folder the file is directly in.
  /// Null for project paths, which `pubspec.yaml` decides.
  bool? ships(String key) {
    final name = packageOf(key);
    if (name == null) return null;
    final pkg = packages[name];
    if (pkg == null) return false;
    final rest = key.substring(10 + name.length);
    final folder = rest.contains('/')
        ? rest.substring(0, rest.lastIndexOf('/') + 1)
        : '';
    return pkg.assetFolders.contains(folder) || pkg.assetFolders.contains(rest);
  }

  /// The packages that ship assets, by name: every Asset Store item, and
  /// any other resolved package that lists `flutter: assets:`.
  Map<String, PackageAssetRoot> get packages {
    _refresh();
    return _packages;
  }

  /// The [packages] worth listing beside the project's own assets: those
  /// with asset folders.
  Iterable<PackageAssetRoot> get withAssets =>
      packages.values.where((p) => p.assetFolders.isNotEmpty);

  /// The keys (`packages/<name>/…`) of the files packages ship — those
  /// directly in their asset folders, as Flutter ships them — whose names
  /// end in one of [endings] (lowercase, like `.png` or `.tileset.json`);
  /// every file when [endings] is empty. Sorted.
  List<String> packageFiles({Iterable<String> endings = const []}) {
    final wanted = endings.map((e) => e.toLowerCase()).toList();
    final out = <String>[];
    for (final pkg in withAssets) {
      for (final folder in pkg.assetFolders) {
        if (!folder.endsWith('/')) continue;
        final dir = Directory('${pkg.path}/$folder');
        if (!dir.existsSync()) continue;
        try {
          for (final f in dir.listSync().whereType<File>()) {
            final name = f.uri.pathSegments.last;
            final lower = name.toLowerCase();
            if (wanted.isNotEmpty && !wanted.any(lower.endsWith)) continue;
            out.add('packages/${pkg.name}/$folder$name');
          }
        } on FileSystemException {
          // Unreadable: nothing from it.
        }
      }
    }
    return out..sort();
  }

  /// Drops what was read, so the next call reads again.
  void invalidate() {
    _checked = null;
    _stamp = '';
  }

  Map<String, PackageAssetRoot> _packages = const {};
  DateTime? _checked;
  String _stamp = '';

  void _refresh() {
    final now = DateTime.now();
    if (_checked != null &&
        now.difference(_checked!) < const Duration(milliseconds: 500)) {
      return;
    }
    _checked = now;
    final lock = File('$root/just_store.lock.json');
    final config = File('$root/.dart_tool/package_config.json');
    final stamp = '${_mtime(lock)}|${_mtime(config)}';
    if (stamp == _stamp) return;
    _stamp = stamp;
    _packages = _read(lock, config);
  }

  Map<String, PackageAssetRoot> _read(File lock, File config) {
    final paths = <String, (String, bool)>{}; // name → (path, fromStore)
    // pub's resolution: every package, wherever it is.
    final configJson = _json(config);
    final packages = configJson?['packages'];
    if (packages is List) {
      final base = config.parent.absolute.uri;
      for (final p in packages) {
        if (p is! Map || p['name'] is! String || p['rootUri'] is! String) {
          continue;
        }
        final uri = p['rootUri'] as String;
        final resolved = base.resolve(uri.endsWith('/') ? uri : '$uri/');
        paths[p['name'] as String] = (
          _normal(resolved.toFilePath(windows: Platform.isWindows)),
          false,
        );
      }
    }
    // The store's items, even before pub has run. Its copy wins only when
    // pub has no other place for the package (a developer's checkout does).
    final items = _json(lock)?['items'];
    if (items is Map) {
      for (final e in items.entries) {
        final item = e.value;
        if (item is! Map || item['path'] is! String) continue;
        final name = '${e.key}';
        final storePath = _normal('$root/${item['path']}');
        final existing = paths[name];
        paths[name] = existing == null || existing.$1 == storePath
            ? (storePath, true)
            : (existing.$1, true);
      }
    }
    final out = <String, PackageAssetRoot>{};
    paths.forEach((name, where) {
      final (path, fromStore) = where;
      // The app itself: its assets have no `packages/` key.
      if (_startsWith('$path/', '$root/') && path.length == root.length) {
        return;
      }
      final lower = path.toLowerCase();
      final inCache =
          lower.contains('/pub/cache/') || lower.contains('/.pub-cache/');
      // Pub-cache packages without assets are the vast majority: skip
      // reading their pubspecs unless the store installed them.
      final pubspec = File('$path/pubspec.yaml');
      final folders = pubspec.existsSync()
          ? parseAssetEntries(pubspec.readAsStringSync())
          : const <String>[];
      if (folders.isEmpty && !fromStore && inCache) return;
      out[name] = PackageAssetRoot(
        name: name,
        path: path,
        assetFolders: folders,
        inPubCache: inCache,
        fromStore: fromStore,
      );
    });
    return out;
  }

  /// The `flutter: assets:` entries of a pubspec's [text].
  static List<String> parseAssetEntries(String text) {
    final out = <String>[];
    var inFlutter = false;
    var inAssets = false;
    var assetsIndent = 0;
    for (final raw in text.split('\n')) {
      final line = raw.replaceAll('\r', '');
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final indent = line.length - line.trimLeft().length;
      if (indent == 0) {
        inFlutter = trimmed == 'flutter:';
        inAssets = false;
        continue;
      }
      if (!inFlutter) continue;
      if (trimmed == 'assets:') {
        inAssets = true;
        assetsIndent = indent;
        continue;
      }
      if (inAssets && indent <= assetsIndent) inAssets = false;
      if (inAssets && trimmed.startsWith('-')) {
        var entry = trimmed.substring(1).trim();
        if (entry.startsWith('path:')) entry = entry.substring(5).trim();
        final hash = entry.indexOf(' #');
        if (hash >= 0) entry = entry.substring(0, hash).trim();
        if (entry.length >= 2 &&
            (entry.startsWith('"') || entry.startsWith("'"))) {
          entry = entry.substring(1, entry.length - 1);
        }
        out.add(entry);
      }
    }
    return out;
  }

  static Map<String, dynamic>? _json(File f) {
    if (!f.existsSync()) return null;
    try {
      final v = jsonDecode(f.readAsStringSync());
      return v is Map<String, dynamic> ? v : null;
    } on Object {
      return null;
    }
  }

  static String _mtime(File f) {
    try {
      return '${f.lastModifiedSync().microsecondsSinceEpoch}';
    } on FileSystemException {
      return '-';
    }
  }

  static bool _startsWith(String path, String prefix) =>
      Platform.isWindows || Platform.isMacOS
      ? path.toLowerCase().startsWith(prefix.toLowerCase())
      : path.startsWith(prefix);

  static String _normal(String path) {
    var p = path.replaceAll(r'\', '/');
    while (p.length > 1 && p.endsWith('/') && !p.endsWith(':/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
