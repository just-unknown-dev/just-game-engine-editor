part of 'editor_overlay.dart';

class _EditorRightPanel extends StatelessWidget {
  const _EditorRightPanel({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorTheme.panelBg,
      child: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: EditorTheme.border, width: 1),
            ),
          ),
          child: ListenableBuilder(
            listenable: plugin.sceneState,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _HeaderBar(plugin: plugin, settings: settings),
                  const Divider(height: 1, color: EditorTheme.border),
                  if (!plugin.sceneState.hasScene)
                    Expanded(
                      child: ScenePickerPanel(
                        onSceneSelected: (name) => plugin.openScene(name),
                      ),
                    )
                  else ...<Widget>[
                    SizedBox(
                      height: 220,
                      child: SceneTreePanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onCreateEntity: plugin.createEntity,
                        onCreateGroup: plugin.createGroup,
                        onCreateGroupFrom: (entity) =>
                            plugin.createGroup(children: [entity]),
                        onDeleteEntity: plugin.deleteEntity,
                        onCopyEntity: plugin.copyEntity,
                        onPasteEntity: plugin.pasteEntity,
                        onReparentEntity: plugin.reparentEntity,
                      ),
                    ),
                    const Divider(height: 1, color: EditorTheme.border),
                    Expanded(
                      child: EntityInspectorPanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onDetachFromParent: plugin.detachFromParent,
                        onGroupSelection: plugin.createGroup,
                      ),
                    ),
                    _SaveFooter(plugin: plugin, settings: settings),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          if (sceneName != null) ...<Widget>[
            Tooltip(
              message: 'Back to scene list',
              child: IconButton(
                onPressed: plugin.sceneState.closeScene,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                iconSize: 14,
                color: settings.themeColor,
                splashRadius: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            const SizedBox(width: 4),
          ] else ...<Widget>[
            const Icon(
              Icons.tune_rounded,
              color: EditorTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Just Runtime Editor',
                  style: TextStyle(
                    fontSize: 13 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                    color: EditorTheme.textPrimary,
                  ),
                ),
                if (sceneName != null)
                  Text(
                    sceneName,
                    style: TextStyle(
                      fontSize: 10 * settings.effectiveTextScale,
                      color: settings.themeColor.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          _Badge(label: 'JIT', accent: settings.themeColor, settings: settings),
        ],
      ),
    );
  }
}

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final isDirty = plugin.sceneState.isDirty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            if (isDirty)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: _Badge(
                  label: 'UNSAVED',
                  accent: EditorTheme.warning,
                  settings: settings,
                ),
              ),
            const Spacer(),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: isDirty ? () => plugin.saveScene() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTheme.buttonBg,
                  disabledBackgroundColor: EditorTheme.surfaceBg,
                  foregroundColor: settings.themeColor,
                  disabledForegroundColor: EditorTheme.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(settings.cornerRadius),
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 14),
                label: Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 12 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
