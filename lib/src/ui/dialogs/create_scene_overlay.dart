import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' show SceneMode;
import '../../core/constants/editor_constants.dart';

import '../../core/dev/editor_dev_flags.dart';
import '../../core/serialization/scene_store.dart';
import '../../core/serialization/scene_name_validator.dart';
import '../kit/controls.dart';

/// Full-panel overlay shown when the editor is open but no scene is loaded.
///
/// Presents a name input field with inline validation, a choice of scene
/// type — 2-D, or 3-D (disabled until 3-D authoring ships, unless
/// [EditorDevFlags.allow3DSceneMode] is on) — and a "Create Scene" button.
/// On success it:
/// 1. Writes `assets/scenes/{name}.scene.json` via [SceneStore], in the
///    chosen mode.
/// 2. Calls [onSceneCreated] with the validated name.
class CreateSceneOverlay extends StatefulWidget {
  const CreateSceneOverlay({
    super.key,
    required this.onSceneCreated,
    required this.store,
  });

  /// Where the new scene is written.
  final SceneStore store;

  /// Called with the new scene name after the files have been written.
  final Future<void> Function(String sceneName) onSceneCreated;

  @override
  State<CreateSceneOverlay> createState() => _CreateSceneOverlayState();
}

class _CreateSceneOverlayState extends State<CreateSceneOverlay> {
  final TextEditingController _controller = TextEditingController();
  String? _errorMessage;
  bool _isCreating = false;

  List<String> _existingNames = [];

  /// How the new scene is authored. 2-D unless 3-D is picked.
  SceneMode _mode = SceneMode.twoD;

  /// Why 3-D cannot be picked yet — on the page and in the tooltip.
  static const String threeDUnavailable =
      '3D scenes arrive in the next release.';

  bool get _canPick3D => EditorDevFlags.allow3DSceneMode;

  @override
  void initState() {
    super.initState();
    _existingNames = SceneNameValidator.existingSceneNames(widget.store);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    final error = SceneNameValidator.validate(
      value,
      existingNames: _existingNames,
    );
    setState(() => _errorMessage = error);
  }

  Future<void> _onCreate() async {
    final name = _controller.text.trim();
    final error = SceneNameValidator.validate(
      name,
      existingNames: _existingNames,
    );
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    setState(() => _isCreating = true);
    try {
      await widget.store.writeInitialFiles(name, mode: _mode);
      await widget.onSceneCreated(name);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to create scene: $e';
          _isCreating = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isCreating = false);
  }

  bool get _canCreate =>
      _errorMessage == null &&
      _controller.text.trim().isNotEmpty &&
      !_isCreating;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12),
          Text(
            'No scene is open',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a scene to start placing and editing entities.',
            style: TextStyle(color: EditorTheme.primaryBright, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Text(
            'SCENE NAME',
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            onChanged: _onNameChanged,
            onSubmitted: (_) => _canCreate ? _onCreate() : null,
            autofocus: true,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g. level_1',
              hintStyle: TextStyle(color: EditorTheme.primaryMuted),
              filled: true,
              fillColor: EditorTheme.surfaceDark,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: EditorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: _errorMessage != null
                      ? EditorTheme.error
                      : EditorTheme.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: _errorMessage != null
                      ? EditorTheme.error
                      : EditorTheme.primaryActive,
                ),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              style: TextStyle(color: EditorTheme.errorLight, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'SCENE TYPE',
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          EditorSegmented<SceneMode>(
            value: _mode,
            options: const [(SceneMode.twoD, '2D'), (SceneMode.threeD, '3D')],
            disabled: _canPick3D ? const {} : const {SceneMode.threeD},
            tooltips: _canPick3D
                ? const {}
                : const {SceneMode.threeD: threeDUnavailable},
            expand: true,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          if (!_canPick3D) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: EditorTheme.primaryMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    threeDUnavailable,
                    style: TextStyle(
                      color: EditorTheme.primaryMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: _canCreate ? _onCreate : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTheme.primaryActive,
                disabledBackgroundColor: EditorTheme.border,
                foregroundColor: EditorTheme.textPrimary,
                disabledForegroundColor: EditorTheme.primaryMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
              child: _isCreating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EditorTheme.textPrimary,
                      ),
                    )
                  : const Text(
                      'Create Scene',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Creates assets/scenes/{name}.scene.json and adds it to\n'
            'assets/scenes/scenes.json. It ships with the game as it is.',
            style: TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
