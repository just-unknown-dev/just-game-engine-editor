import 'package:flutter/material.dart';
import '../theme/editor_theme.dart';

import '../dialogs/create_scene_overlay.dart';
import '../dialogs/scene_actions_dialogs.dart';
import '../../core/serialization/scene_manager.dart';

/// Shown in the right panel when no scene is currently open.
///
/// - Lists all scene folders found in `lib/game/scenes/`.
/// - Tapping a scene row calls [onSceneSelected].
/// - The `+` icon button in the header switches to the inline create form.
/// - The create form has a back arrow that returns to the list.
/// - Each row's overflow menu offers Rename / Duplicate / Delete, routed
///   through [sceneManager].
class ScenePickerPanel extends StatefulWidget {
  const ScenePickerPanel({
    super.key,
    required this.onSceneSelected,
    required this.sceneManager,
  });

  /// Called when the user opens an existing scene **or** successfully creates
  /// a new one.
  final Future<void> Function(String sceneName) onSceneSelected;

  final SceneManager sceneManager;

  @override
  State<ScenePickerPanel> createState() => _ScenePickerPanelState();
}

class _ScenePickerPanelState extends State<ScenePickerPanel> {
  bool _showCreate = false;
  List<String> _scenes = [];
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _refreshScenes();
  }

  void _refreshScenes() {
    setState(() => _scenes = widget.sceneManager.listScenes());
  }

  void _openCreate() => setState(() => _showCreate = true);
  void _backToList() => setState(() => _showCreate = false);

  Future<void> _onSceneCreated(String name) async {
    await widget.onSceneSelected(name);
    // Refresh the list in case the user navigates back.
    _refreshScenes();
  }

  Future<void> _onRename(String name) async {
    setState(() => _actionError = null);
    final newName = await promptSceneName(
      context,
      title: 'Rename "$name"',
      actionLabel: 'Rename',
      initialValue: name,
      validate: (value) => widget.sceneManager.validateName(
        value,
        ignoring: name,
      ),
    );
    if (newName == null || !mounted) return;
    try {
      await widget.sceneManager.renameScene(name, newName);
      _refreshScenes();
    } on SceneManagerException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    }
  }

  Future<void> _onDuplicate(String name) async {
    setState(() => _actionError = null);
    final newName = await promptSceneName(
      context,
      title: 'Duplicate "$name"',
      actionLabel: 'Duplicate',
      initialValue: '${name}_copy',
      validate: (value) =>
          widget.sceneManager.validateName(value, ignoring: name),
    );
    if (newName == null || !mounted) return;
    try {
      await widget.sceneManager.duplicateScene(name, newName);
      _refreshScenes();
    } on SceneManagerException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    }
  }

  Future<void> _onDelete(String name) async {
    setState(() => _actionError = null);
    final confirmed = await confirmDeleteScene(context, name);
    if (!confirmed || !mounted) return;
    try {
      await widget.sceneManager.deleteScene(name);
      _refreshScenes();
    } on SceneManagerException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showCreate) {
      return _CreateView(onBack: _backToList, onSceneCreated: _onSceneCreated);
    }
    return _ListView(
      scenes: _scenes,
      sceneManager: widget.sceneManager,
      actionError: _actionError,
      onDismissError: () => setState(() => _actionError = null),
      onAdd: _openCreate,
      onSelect: widget.onSceneSelected,
      onRename: _onRename,
      onDuplicate: _onDuplicate,
      onDelete: _onDelete,
    );
  }
}

// ── List view ─────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({
    required this.scenes,
    required this.sceneManager,
    required this.actionError,
    required this.onDismissError,
    required this.onAdd,
    required this.onSelect,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final List<String> scenes;
  final SceneManager sceneManager;
  final String? actionError;
  final VoidCallback onDismissError;
  final VoidCallback onAdd;
  final Future<void> Function(String) onSelect;
  final void Function(String) onRename;
  final void Function(String) onDuplicate;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Row(
            children: <Widget>[
              const Text(
                'SCENES',
                style: TextStyle(
                  color: EditorTheme.primaryBright,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Create new scene',
                child: IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  iconSize: 18,
                  color: EditorTheme.primary,
                  splashRadius: 16,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: EditorTheme.border),
        if (actionError != null) _ActionErrorBanner(
          message: actionError!,
          onDismiss: onDismissError,
        ),
        // Body
        Expanded(
          child: scenes.isEmpty
              ? _EmptyState(onAdd: onAdd)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: scenes.length,
                  itemBuilder: (context, i) => _SceneRow(
                    name: scenes[i],
                    isProtected: sceneManager.isProtected(scenes[i]),
                    onTap: () => onSelect(scenes[i]),
                    onRename: () => onRename(scenes[i]),
                    onDuplicate: () => onDuplicate(scenes[i]),
                    onDelete: () => onDelete(scenes[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActionErrorBanner extends StatelessWidget {
  const _ActionErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EditorTheme.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: EditorTheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: EditorTheme.errorLight,
                fontSize: 11,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: EditorTheme.errorLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.folder_open_rounded,
            color: EditorTheme.border,
            size: 36,
          ),
          const SizedBox(height: 12),
          const Text(
            'No scenes yet',
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Press + to create your first scene.',
            style: TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 11,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTheme.buttonBg,
                foregroundColor: EditorTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'New Scene',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SceneRowAction { rename, duplicate, delete }

class _SceneRow extends StatelessWidget {
  const _SceneRow({
    required this.name,
    required this.isProtected,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final String name;
  final bool isProtected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.folder_rounded,
              size: 15,
              color: EditorTheme.primaryMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isProtected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Used by the shipped game — cannot be renamed or '
                      'deleted',
                  child: Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: EditorTheme.primaryMuted,
                  ),
                ),
              ),
            PopupMenuButton<_SceneRowAction>(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 16,
                color: EditorTheme.textMuted,
              ),
              splashRadius: 14,
              padding: EdgeInsets.zero,
              color: EditorTheme.menuBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: EditorTheme.border),
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _SceneRowAction.rename,
                  height: 32,
                  child: Text(
                    'Rename',
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: _SceneRowAction.duplicate,
                  height: 32,
                  child: Text(
                    'Duplicate',
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: _SceneRowAction.delete,
                  height: 32,
                  enabled: !isProtected,
                  child: Text(
                    'Delete',
                    style: TextStyle(
                      color: isProtected
                          ? EditorTheme.textMuted
                          : EditorTheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _SceneRowAction.rename:
                    onRename();
                  case _SceneRowAction.duplicate:
                    onDuplicate();
                  case _SceneRowAction.delete:
                    onDelete();
                }
              },
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: EditorTheme.border,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create view ───────────────────────────────────────────────────────────────

class _CreateView extends StatelessWidget {
  const _CreateView({required this.onBack, required this.onSceneCreated});

  final VoidCallback onBack;
  final Future<void> Function(String) onSceneCreated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Back header
        InkWell(
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 14,
                  color: EditorTheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'New Scene',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: EditorTheme.border),
        Expanded(child: CreateSceneOverlay(onSceneCreated: onSceneCreated)),
      ],
    );
  }
}
