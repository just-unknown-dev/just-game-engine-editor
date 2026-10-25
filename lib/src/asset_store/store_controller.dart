import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import 'store_settings.dart';

/// The store window's pages.
enum StoreTab { browse, installed, updates, sources }

/// The order the grid lists items in.
enum StoreSort {
  name('By name'),
  updated('Recently updated');

  const StoreSort(this.label);

  /// Its name in the sort menu.
  final String label;
}

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

  /// Whether no catalog could be read at all, not even from the cache.
  bool get unreachable {
    final sources = catalog?.sources ?? const <SourceStatus>[];
    return sources.isNotEmpty && sources.every((s) => !s.loaded);
  }

  /// Whether every catalog is turned off.
  bool get noSources => catalog != null && catalog!.sources.isEmpty;

  /// The name of the catalog [sourceId] (what the lockfile records).
  String sourceName(String sourceId) {
    for (final s in catalog?.sources ?? const <SourceStatus>[]) {
      if (s.info?.id == sourceId) return s.name;
    }
    return sourceId;
  }

  /// The item [id] as a catalog lists it.
  CatalogEntry? entry(String id) => catalog?.catalog.entry(id);

  /// The installed item [id] as its own manifest describes it: for an item
  /// no catalog lists (a checkout of your own, or every item while the
  /// store can't be reached). Null when it isn't installed.
  CatalogEntry? localEntry(String id) {
    final locked = _lock.items[id];
    if (locked == null) return null;
    final m = _state?.manifests[id];
    return CatalogEntry(
      locked.source ?? 'project',
      StoreItem(
        id: id,
        name: m?.name ?? id,
        kind: m?.kind ?? locked.kind,
        category: m?.category ?? '',
        summary: m?.summary ?? '',
        description: m?.description,
        tags: m?.tags ?? const [],
        author: m?.author,
        license: m?.license,
        trust: locked.official ? TrustLevel.official : TrustLevel.community,
        versions: [
          StoreItemVersion(
            version:
                m?.version ??
                Version.tryParse(locked.version) ??
                Version(0, 0, 0),
            requires: m?.requires ?? const {},
            dependencies: m?.dependencies ?? const {},
            permissions: m?.permissions ?? const {},
            stage: m?.stage,
            replacedBy: m?.replacedBy,
          ),
        ],
      ),
    );
  }

  // ── The project ──────────────────────────────────────────────────────────

  StoreLock _lock = StoreLock();
  ProjectState? _state;

  /// What the project has installed.
  StoreLock get lock => _lock;

  /// The installed item [id], or null.
  LockedItem? installed(String id) => _lock.items[id];

  /// What the Installed page lists: every installed item but the editor's
  /// own parts (`system` items: the editor and the store's core). Those
  /// were not added from the store and can't be removed; the lockfile
  /// keeps them for what other items require.
  List<String> get listedInstalled => [
    for (final e in _lock.items.entries)
      if (!e.value.system) e.key,
  ];

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
    // Installed copies may have changed their pictures.
    _thumbs.removeWhere((key, _) => key.startsWith('local/'));
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

  /// The order of the grid.
  StoreSort sort = StoreSort.name;

  void sortBy(StoreSort sort) {
    this.sort = sort;
    notifyListeners();
  }

  /// Whether experimental items are listed (they are hidden until asked).
  bool get showExperimental => scope.prefs.get(StoreSettings.showExperimental);

  set showExperimental(bool show) {
    scope.prefs.set(StoreSettings.showExperimental, show);
    notifyListeners();
  }

  /// Where [entry] comes from: what the project recorded when it was
  /// installed, else its catalog.
  ItemSource sourceOf(CatalogEntry entry) =>
      ItemSource.of(entry: entry, installed: _lock.items[entry.item.id]);

  /// Whether browsing lists [item]: an experimental one only when
  /// [showExperimental] is on, a deprecated one only to a search.
  bool _browses(StoreItem item) => switch (item.stage) {
    ItemStage.experimental => showExperimental,
    ItemStage.deprecated => query.trim().isNotEmpty,
    _ => true,
  };

  void select(String? id) {
    selected = id;
    notifyListeners();
  }

  /// The items the current page shows.
  List<CatalogEntry> get shown => _matching(kind)..sort(_compare);

  /// How many items of each kind the current page would show, whichever
  /// kind is picked: the kind chips with none are left out.
  Map<ItemKind, int> get kindCounts {
    final out = <ItemKind, int>{};
    for (final e in _matching(null)) {
      out[e.item.kind] = (out[e.item.kind] ?? 0) + 1;
    }
    return out;
  }

  List<CatalogEntry> _matching(ItemKind? kind) {
    final updating = tab == StoreTab.updates ? updates.toSet() : <String>{};
    return [
      for (final e in _pageEntries())
        if (_onPage(e, updating) &&
            (category == null || e.item.category == category) &&
            (kind == null || e.item.kind == kind) &&
            e.item.matches(query) &&
            e.item.latest != null)
          e,
    ];
  }

  /// The catalogs' items, and on the Installed page the installed items no
  /// catalog lists, as their manifests describe them.
  Iterable<CatalogEntry> _pageEntries() sync* {
    yield* catalog?.catalog.entries ?? const <CatalogEntry>[];
    if (tab != StoreTab.installed) return;
    for (final id in listedInstalled) {
      if (entry(id) == null) yield localEntry(id)!;
    }
  }

  int _compare(CatalogEntry a, CatalogEntry b) {
    if (sort == StoreSort.updated) {
      final pa = a.item.latest?.published, pb = b.item.latest?.published;
      if (pa != pb) {
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pb.compareTo(pa);
      }
    }
    return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
  }

  bool _onPage(CatalogEntry e, Set<String> updating) => switch (tab) {
    StoreTab.browse => _browses(e.item),
    StoreTab.installed => _lock.items[e.item.id]?.system == false,
    StoreTab.updates => updating.contains(e.item.id),
    StoreTab.sources => false,
  };

  /// How many items each category holds.
  Map<String, int> get categoryCounts {
    final out = <String, int>{};
    for (final e in catalog?.catalog.entries ?? const <CatalogEntry>[]) {
      if (e.item.latest == null || !_browses(e.item)) continue;
      out[e.item.category] = (out[e.item.category] ?? 0) + 1;
    }
    return out;
  }

  // ── Plans and installs ───────────────────────────────────────────────────

  /// Plans installing [id] ([version], or the newest that fits). Installed,
  /// it plans moving to [version].
  InstallPlan? planInstall(String id, {Version? version}) =>
      _planner?.install(id, version: version);

  /// The versions of [id] that can be installed, newest first.
  List<StoreItemVersion> versionsOf(String id) =>
      (entry(id)?.item.available.toList() ?? <StoreItemVersion>[])
        ..sort((a, b) => b.version.compareTo(a.version));

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

  /// [entry]'s card picture, cached on disk; else the installed copy's
  /// first picture; null when it has neither.
  Future<File?> thumbnail(CatalogEntry entry) {
    final ref = entry.item.thumbnail;
    final source = entry.source;
    if (ref == null || source == null) {
      final id = entry.item.id;
      return _thumbs.putIfAbsent('local/$id', () async => _localPicture(id));
    }
    return _thumbs.putIfAbsent(
      '${entry.sourceId}/$ref',
      () => store.downloader.thumbnail(source, ref),
    );
  }

  /// The first picture inside the installed copy of [id], when it has one.
  File? _localPicture(String id, [int index = 0]) {
    final path = _lock.items[id]?.path;
    final pictures = _state?.manifests[id]?.previews ?? const <String>[];
    if (path == null || index >= pictures.length) return null;
    final file = project.file('$path/${pictures[index]}');
    return file.existsSync() ? file : null;
  }

  /// [entry]'s pictures for its details: a catalog's previews, else the
  /// installed copy's.
  int pictureCount(CatalogEntry entry) {
    if (entry.source != null && entry.item.previews.isNotEmpty) {
      return entry.item.previews.length;
    }
    return _state?.manifests[entry.item.id]?.previews.length ?? 0;
  }

  /// Picture [index] of [entry] (see [pictureCount]), cached on disk.
  Future<File?> picture(CatalogEntry entry, int index) {
    final source = entry.source;
    final previews = entry.item.previews;
    if (source != null && previews.isNotEmpty) {
      if (index >= previews.length) return Future.value();
      final ref = previews[index];
      return _thumbs.putIfAbsent(
        '${entry.sourceId}/$ref',
        () => store.downloader.thumbnail(source, ref),
      );
    }
    final id = entry.item.id;
    return _thumbs.putIfAbsent(
      'local/$id/$index',
      () async => _localPicture(id, index),
    );
  }

  // ── Links ────────────────────────────────────────────────────────────────

  /// The store website's page for [entry], when the official catalog lists
  /// it.
  Uri? webPage(CatalogEntry entry) => entry.sourceId == SourceConfig.officialId
      ? _site.replace(path: '/items/${entry.item.id}')
      : null;

  /// The store website's form for reporting [entry], when the official
  /// catalog lists it.
  Uri? reportPage(CatalogEntry entry) =>
      entry.sourceId == SourceConfig.officialId
      ? _site.replace(path: '/report', queryParameters: {'item': entry.item.id})
      : null;

  static final Uri _site = Uri.parse(SourceConfig.official.url);

  /// Opens [uri] in the browser: only `https:` links, passed as one
  /// argument (never through a shell). False when it could not.
  Future<bool> openLink(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) return false;
    final link = '$uri';
    try {
      final result = Platform.isWindows
          ? await Process.run('rundll32', ['url.dll,FileProtocolHandler', link])
          : await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [link]);
      return result.exitCode == 0;
    } on Exception {
      return false;
    }
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
