import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import 'store_settings.dart';

/// The store window's pages.
enum StoreTab { browse, installed, updates, sources }

/// What the store window shows and does: the catalogs, what the project
/// has, the filters, and the install running now. One per editor session;
/// it outlives the window, so reopening the store is instant.
class StoreController extends ChangeNotifier {
  StoreController({
    required this.scope,
    String? root,
    List<SourceConfig>? sources,
    String? cacheDir,
    PubRunner? pub,
  }) : project = StoreProject(root ?? Directory.current.path),
       _fixedSources = sources,
       _cacheDir = cacheDir ?? StorePaths.defaultCacheDir(),
       _pub = pub {
    _registeredStamp = _generatedStamp();
  }

  final EditorScope scope;

  /// The project items install into.
  final StoreProject project;

  final List<SourceConfig>? _fixedSources;
  final String? _cacheDir;
  final PubRunner? _pub;

  AssetStore? _store;
  String _storeKey = '';

  /// The store for the current settings, rebuilt when they change.
  AssetStore get store {
    final sources = sourceConfigs;
    final sdk = scope.prefs.get(StoreSettings.sdkPath).trim();
    final key = '${sources.map((s) => '${s.url}|${s.enabled}').join(',')}#$sdk';
    if (_store == null || key != _storeKey) {
      _storeKey = key;
      _store = AssetStore(
        project: project,
        sources: sources,
        cacheDir: _cacheDir,
        pub: _pub,
        sdkPath: sdk.isEmpty ? null : sdk,
      );
    }
    return _store!;
  }

  /// The catalogs the settings name.
  List<SourceConfig> get sourceConfigs =>
      _fixedSources ?? StoreSettings.sources(scope.prefs);

  /// Whether the catalogs come from the settings (rather than being fixed
  /// by whoever made the controller), so the Sources page may edit them.
  bool get usesSettings => _fixedSources == null;

  // ── Catalogs ─────────────────────────────────────────────────────────────

  /// The merged catalog, once loaded.
  LoadedCatalog? catalog;

  /// Whether catalogs are being fetched.
  bool loading = false;

  /// Loads the catalogs, or (with [refresh]) asks the servers again.
  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      catalog = await store.loadCatalog(refresh: refresh);
      _readProject();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// The sources whose catalogs could not be read, or came from the cache.
  Iterable<SourceStatus> get troubledSources =>
      catalog?.sources.where((s) => !s.loaded || s.offline) ?? const [];

  /// The item [id] as a catalog lists it.
  CatalogEntry? entry(String id) => catalog?.catalog.entry(id);

  // ── The project ──────────────────────────────────────────────────────────

  StoreLock _lock = StoreLock();
  ProjectState? _state;

  /// What the project has installed.
  StoreLock get lock => _lock;

  /// The installed item [id], or null.
  LockedItem? installed(String id) => _lock.items[id];

  /// Reads the lockfile and the project's packages again.
  void refreshProject() {
    _readProject();
    notifyListeners();
  }

  void _readProject() {
    try {
      _lock = project.readLock();
      _state = ProjectState.read(
        project,
        OverridesTarget(
          project.file(StoreProject.overrides).existsSync()
              ? StoreProject.overrides
              : StoreProject.pubspec,
        ),
      );
    } on Object catch (e) {
      projectError = e;
      return;
    }
    projectError = null;
  }

  /// Why the project's store files could not be read.
  Object? projectError;

  Planner? get _planner {
    final c = catalog;
    final s = _state;
    if (c == null || s == null) return null;
    return Planner(c.catalog, s);
  }

  /// A newer version of [id] than the one installed, when there is one.
  StoreItemVersion? updateFor(String id) => _planner?.availableUpdate(id);

  /// The installed items with a newer version available.
  List<String> get updates => [
    for (final id in _lock.items.keys)
      if (_lock.items[id]!.origin == ItemOrigin.vendored &&
          updateFor(id) != null)
        id,
  ];

  // ── Filters ──────────────────────────────────────────────────────────────

  StoreTab tab = StoreTab.browse;
  String query = '';

  /// Shown category, or every one when null.
  String? category;

  /// Shown kind, or every one when null.
  ItemKind? kind;

  /// The item in the details pane.
  String? selected;

  void show(StoreTab tab, {String? category}) {
    this.tab = tab;
    this.category = category;
    notifyListeners();
  }

  void search(String query) {
    this.query = query;
    notifyListeners();
  }

  void filterKind(ItemKind? kind) {
    this.kind = kind;
    notifyListeners();
  }

  void select(String? id) {
    selected = id;
    notifyListeners();
  }

  /// The items the current page shows.
  List<CatalogEntry> get shown {
    final all = catalog?.catalog.entries.toList() ?? const <CatalogEntry>[];
    final updating = tab == StoreTab.updates ? updates.toSet() : <String>{};
    final out = [
      for (final e in all)
        if (_onPage(e, updating) &&
            (category == null || e.item.category == category) &&
            (kind == null || e.item.kind == kind) &&
            e.item.matches(query) &&
            e.item.latest != null)
          e,
    ];
    out.sort(
      (a, b) => a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
    );
    return out;
  }

  bool _onPage(CatalogEntry e, Set<String> updating) => switch (tab) {
    StoreTab.browse => true,
    StoreTab.installed => _lock.items.containsKey(e.item.id),
    StoreTab.updates => updating.contains(e.item.id),
    StoreTab.sources => false,
  };

  /// How many items each category holds.
  Map<String, int> get categoryCounts {
    final out = <String, int>{};
    for (final e in catalog?.catalog.entries ?? const <CatalogEntry>[]) {
      if (e.item.latest == null) continue;
      out[e.item.category] = (out[e.item.category] ?? 0) + 1;
    }
    return out;
  }

  // ── Plans and installs ───────────────────────────────────────────────────

  /// Plans installing [id] ([version], or the newest that fits).
  InstallPlan? planInstall(String id, {Version? version}) =>
      _planner?.install(id, version: version);

  /// Plans updating [id].
  InstallPlan? planUpdate(String id) => _planner?.update(id);

  /// Plans updating every item installed on purpose.
  InstallPlan? planUpdateAll() => _planner?.updateAll();

  /// Plans removing [id], with what still uses it and the dependencies that
  /// would go with it.
  InstallPlan? planUninstall(String id) => _planner?.uninstall(
    id,
    references: store.referencesTo(id),
    referencesOf: (dep, going) => store.referencesTo(dep, ignoring: going),
  );

  /// The task running now, if any: what it says it is doing.
  InstallProgress? progress;

  /// Whether a plan is being applied.
  bool get busy => progress != null;

  CancelToken? _cancel;

  /// Stops the running install, if it has not started changing files.
  void cancel() => _cancel?.cancel();

  /// Applies [plan]; [onProgress] hears each step too. Returns what was
  /// done, or throws [InstallFailure] / [CancelledException].
  Future<InstallResult> apply(
    InstallPlan plan, {
    void Function(InstallProgress)? onProgress,
  }) async {
    if (busy) throw StateError('An install is already running.');
    final cancel = _cancel = CancelToken();
    progress = const InstallProgress('Starting');
    notifyListeners();
    try {
      final result = await store.installer().apply(
        plan,
        cancel: cancel,
        onProgress: (p) {
          progress = p;
          onProgress?.call(p);
          notifyListeners();
        },
      );
      // The editor shows what changed: sprites, maps, fonts…
      scope.reloadAssets(result.changedAssets);
      PackageAssetPaths.of(project.root).invalidate();
      _readProject();
      return result;
    } finally {
      progress = null;
      _cancel = null;
      notifyListeners();
    }
  }

  // ── Restart ──────────────────────────────────────────────────────────────

  late final String _registeredStamp;

  /// Whether installed code changed since the editor started: the
  /// generated registries differ from what this session loaded, so a
  /// restart (or hot restart) is needed to run it.
  bool get restartPending => _generatedStamp() != _registeredStamp;

  String _generatedStamp() {
    // A missing file registers nothing, as an empty list does: installing
    // art writes the empty lists for the first time, and needs no restart.
    final empty = {
      StoreProject.modulesFile: StoreCodegen.modules(const []),
      StoreProject.extensionsFile: StoreCodegen.extensions(const []),
    };
    return [
      for (final e in empty.entries)
        project.file(e.key).existsSync()
            ? project.file(e.key).readAsStringSync()
            : e.value,
    ].join('\u0000');
  }

  // ── Pictures ─────────────────────────────────────────────────────────────

  final Map<String, Future<File?>> _thumbs = {};

  /// [entry]'s card picture, cached on disk; null when it has none.
  Future<File?> thumbnail(CatalogEntry entry) {
    final ref = entry.item.thumbnail;
    final source = entry.source;
    if (ref == null || source == null) return Future.value();
    return _thumbs.putIfAbsent(
      '${entry.sourceId}/$ref',
      () => store.downloader.thumbnail(source, ref),
    );
  }

  /// Downloads the locked items whose folders are missing.
  Future<RestoreResult> restore() async {
    progress = const InstallProgress('Restoring');
    notifyListeners();
    try {
      final result = await store.restore(
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
      PackageAssetPaths.of(project.root).invalidate();
      _readProject();
      return result;
    } finally {
      progress = null;
      notifyListeners();
    }
  }
}
