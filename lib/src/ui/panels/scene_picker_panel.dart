import 'package:flutter/material.dart';
import '../theme/editor_theme.dart';

import '../dialogs/create_scene_overlay.dart';
import '../../core/serialization/scene_file_generator.dart';

/// Shown in the right panel when no scene is currently open.
///
/// - Lists all scene folders found in `lib/game/scenes/`.
/// - Tapping a scene row calls [onSceneSelected].
/// - The `+` icon button in the header switches to the inline create form.
/// - The create form has a back arrow that returns to the list.
class ScenePickerPanel extends StatefulWidget {
  const ScenePickerPanel({super.key, required this.onSceneSelected});

  /// Called when the user opens an existing scene **or** successfully creates
  /// a new one.
  final Future<void> Function(String sceneName) onSceneSelected;

  @override
  State<ScenePickerPanel> createState() => _ScenePickerPanelState();
}

class _ScenePickerPanelState extends State<ScenePickerPanel> {
  bool _showCreate = false;
  List<String> _scenes = [];

  @override
  void initState() {
    super.initState();
    _refreshScenes();
  }

  void _refreshScenes() {
    setState(() => _scenes = SceneFileGenerator.listSceneNames()..sort());
  }

  void _openCreate() => setState(() => _showCreate = true);
  void _backToList() => setState(() => _showCreate = false);

  Future<void> _onSceneCreated(String name) async {
    await widget.onSceneSelected(name);
    // Refresh the list in case the user navigates back.
    _refreshScenes();
  }

  @override
  Widget build(BuildContext context) {
    if (_showCreate) {
      return _CreateView(onBack: _backToList, onSceneCreated: _onSceneCreated);
    }
    return _ListView(
      scenes: _scenes,
      onAdd: _openCreate,
      onSelect: widget.onSceneSelected,
    );
  }
}

// ── List view ─────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({
    required this.scenes,
    required this.onAdd,
    required this.onSelect,
  });

  final List<String> scenes;
  final VoidCallback onAdd;
  final Future<void> Function(String) onSelect;

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
        // Body
        Expanded(
          child: scenes.isEmpty
              ? _EmptyState(onAdd: onAdd)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: scenes.length,
                  itemBuilder: (context, i) => _SceneRow(
                    name: scenes[i],
                    onTap: () => onSelect(scenes[i]),
                  ),
                ),
        ),
      ],
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

class _SceneRow extends StatelessWidget {
  const _SceneRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
