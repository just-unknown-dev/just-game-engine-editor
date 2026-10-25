import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/just_editor_core.dart';

import 'store_checks.dart';
import 'store_controller.dart';
import 'store_settings.dart';
import 'ui/store_window.dart';

/// The Asset Store: how a project gets art, sound, editor tools and kits.
///
/// It adds:
/// - the store window, to browse, install, update and remove items: the
///   shop button under the transform tools (a feature of the editor, in a
///   frame of its own below Q/W/E/R), its tile and tip on the start card,
///   and Ctrl+Shift+G (Cmd+Shift+G on macOS);
/// - "Show in the Asset Store" on installed packages in the Assets dock, and
///   "Get assets from the store" on assets/;
/// - its settings page: catalogs, the Flutter SDK, downloads;
/// - checks in the Problems dock: missing package folders, out-of-date
///   generated files, an entry point that doesn't register store items,
///   items the store took down.
///
/// Installs go through `just_asset_store`, the same code `just store …`
/// and a catalog's CI run, so all three agree on what an item may do.
///
/// One of the editor's own modules, for every game: `JustGameEditorPlugin`
/// brings it itself. The plugins and kits it installs register through the
/// generated `lib/editor/store_modules.g.dart`, so a broken generated file
/// can't take the store down with it, and the store can always repair it.
class BuiltInAssetStoreModule extends EditorModule {
  /// The store for the project at [root] (the working directory when null).
  BuiltInAssetStoreModule({this.root, this.sources, this.cacheDir, this.pub});

  /// The module for [scope]: how the editor makes its built-ins.
  static EditorModule make(EditorScope scope) => BuiltInAssetStoreModule();

  /// Its id.
  static const String moduleId = 'asset_store';

  /// The store window's id.
  static const String workspaceId = 'asset_store';

  /// The project folder; the working directory when null.
  final String? root;

  /// Catalogs to read instead of the settings' (tests).
  final List<SourceConfig>? sources;

  /// The download cache; the per-user one when null.
  final String? cacheDir;

  /// Runs pub get; the project's Flutter SDK when null (tests use a fake).
  final PubRunner? pub;

  StoreController? _controller;
  StoreChecks? _checks;

  /// The store's state for [scope]: one per editor session.
  StoreController controllerFor(EditorScope scope) =>
      _controller ??= StoreController(
        scope: scope,
        root: root,
        sources: sources,
        cacheDir: cacheDir,
        pub: pub,
      );

  @override
  String get id => moduleId;

  @override
  String get name => 'Asset Store';

  @override
  IconData? get icon => Icons.storefront_rounded;

  @override
  void onRegister(EditorModuleContext context) {
    final c = controllerFor(context.scope);
    _checks ??= StoreChecks(c);
    // An install a crash left half done is undone before anything else.
    unawaited(
      StoreInstaller.recover(c.project).then((recovered) {
        if (!recovered) return;
        context.scope.log.log(
          'An unfinished Asset Store install was rolled back.',
          source: 'asset_store',
          category: 'store',
          level: DebuggerLogLevel.warning,
        );
        c.refreshProject();
      }, onError: (_) {}),
    );
  }

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Asset Store',
      icon: Icons.storefront_rounded,
      build: (context, workspace) {
        final path = workspace.path;
        return StoreWindow(
          controller: controllerFor(workspace.scope),
          workspace: workspace,
          focusItem: path != null && path.startsWith('store:')
              ? path.substring('store:'.length)
              : null,
        );
      },
    ),
  ];

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'asset_store.open',
      icon: Icons.storefront_rounded,
      tooltip:
          'Asset Store: plugins, kits, art and sound '
          '(${_openKey.shortcut})',
      order: 105,
      // A feature of the editor, not a tool for the scene: under the
      // transform tools, apart from the modules' buttons.
      slot: ToolbarSlot.toolColumn,
      isActive: (scope) =>
          scope.activeWorkspace.value?.definition.id == workspaceId,
      onPressed: (scope) => scope.openWorkspace(workspaceId),
    ),
  ];

  @override
  List<DesignerCommand> get commands => [
    DesignerCommand(
      id: 'store.open',
      label: 'Open the Asset Store',
      scope: CommandScope.always,
      run: (context) => context.scope.openWorkspace(workspaceId),
    ),
  ];

  /// Opens the store: Ctrl+Shift+G, Cmd+Shift+G on macOS.
  static const _openKey = KeyBinding(
    LogicalKeyboardKey.keyG,
    'store.open',
    control: true,
    shift: true,
  );

  @override
  List<KeyBinding> get keyBindings => const [_openKey];

  @override
  List<GettingStartedTip> get gettingStartedTips => [
    GettingStartedTip(
      id: 'asset_store.tip',
      icon: Icons.storefront_rounded,
      text:
          'Plugins, kits, characters, tilesets and sounds are in the Asset '
          'Store: the shop button, or ${_openKey.shortcut}.',
    ),
  ];

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: 'asset_store.show',
      label: 'Show in the Asset Store',
      icon: Icons.storefront_rounded,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && RegExp(r'^packages/[a-z][a-z0-9_]*$').hasMatch(path),
      run: (scope, path) => scope.openWorkspace(
        workspaceId,
        path: 'store:${path.substring('packages/'.length)}',
      ),
    ),
    AssetAction(
      id: 'asset_store.get',
      label: 'Get assets from the store',
      icon: Icons.storefront_outlined,
      order: 140,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && path == 'assets',
      run: (scope, path) => scope.openWorkspace(workspaceId),
    ),
  ];

  @override
  List<SceneValidator> get validators => [
    (context) => _checks?.check(context) ?? const [],
  ];

  @override
  List<String> get dataFileSuffixes => const [
    '/${ItemManifest.fileName}',
    StoreLock.fileName,
  ];

  @override
  List<SettingsSection> get settingsSections => [
    SettingsSection(
      id: 'asset_store',
      title: 'Asset Store',
      build: (context, prefs) => _Settings(prefs: prefs),
    ),
  ];

  @override
  void onAssetChanged(String path) {
    if (path.endsWith(StoreLock.fileName)) {
      _checks?.invalidate();
      _controller?.refreshProject();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _checks = null;
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.prefs});

  final EditorPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: EditorTheme.textMuted,
      fontSize: EditorMetrics.fontBody,
      height: 1.4,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: prefs.watch(StoreSettings.official),
      builder: (context, official, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorToggle(
            value: official,
            label: 'Read the official catalog',
            onChanged: (v) => prefs.set(StoreSettings.official, v),
          ),
          const SizedBox(height: 4),
          Text(
            '${StoreSettings.custom(prefs).length} other catalogs. Add or '
            'remove them, set the Flutter SDK and clear downloads on the '
            "store's Sources page.",
            style: muted,
          ),
          const SizedBox(height: 12),
          Text('Flutter SDK folder (empty: the project\'s)', style: muted),
          const SizedBox(height: 4),
          CommitTextField(
            value: prefs.get(StoreSettings.sdkPath),
            decoration: editorFieldDecoration(hint: 'C:\\flutter'),
            onCommit: (v) => prefs.set(StoreSettings.sdkPath, v.trim()),
          ),
        ],
      ),
    );
  }
}
