import 'package:flutter/material.dart';
import '../theme/editor_theme.dart';

import '../../core/serialization/scene_file_generator.dart';
import '../../core/serialization/scene_name_validator.dart';

/// Full-panel overlay shown when the editor is open but no scene is loaded.
///
/// Presents a name input field with inline validation and a "Create Scene"
/// button.  On success it:
/// 1. Writes `lib/game/scenes/{name}.dart` via [SceneFileGenerator].
/// 2. Calls [onSceneCreated] with the validated name.
class CreateSceneOverlay extends StatefulWidget {
  const CreateSceneOverlay({super.key, required this.onSceneCreated});

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

  @override
  void initState() {
    super.initState();
    _existingNames = SceneNameValidator.existingSceneNames();
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
      await SceneFileGenerator.writeInitialFiles(name);
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
          const Text(
            'No scene is open',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a scene to start placing and editing entities.',
            style: TextStyle(color: EditorTheme.primaryBright, fontSize: 12),
          ),
          const SizedBox(height: 20),
          const Text(
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
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. level_1',
              hintStyle: const TextStyle(color: EditorTheme.primaryMuted),
              filled: true,
              fillColor: EditorTheme.surfaceDark,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: EditorTheme.border),
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
              style: const TextStyle(
                color: EditorTheme.errorLight,
                fontSize: 11,
              ),
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
                  ? const SizedBox(
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
          const Text(
            'Files created:\n'
            'lib/game/scenes/{name}/{name}.level.dart\n'
            'lib/game/scenes/{name}/{name}.data.dart\n'
            'lib/game/scenes/{name}/{name}.scene.json',
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
