import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart'
    show SceneMode, SceneNames;
import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';

import '../../core/dev/editor_dev_flags.dart';
import '../../core/serialization/scene_store.dart';
import '../../core/serialization/scene_name_validator.dart';
import '../kit/kit.dart';

/// Asks for a new scene — see [CreateSceneOverlay] — and writes it. The
/// name it was created with, or null when the dialog was cancelled.
Future<String?> showNewSceneDialog(
  BuildContext context, {
  required SceneStore store,
}) => showDialog<String>(
  context: context,
  barrierColor: Colors.black54,
  builder: (context) => EditorLook(
    child: Dialog(
      backgroundColor: EditorTheme.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorMetrics.radiusLg),
        side: BorderSide(color: EditorTheme.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'New scene',
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: EditorMetrics.fontTitle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  EditorIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: CreateSceneOverlay(
                store: store,
                onCancel: () => Navigator.of(context).pop(),
                onSceneCreated: (name) async => Navigator.of(context).pop(name),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// The New scene form.
///
/// A name, checked as it is typed and suggested from the scenes there are —
/// `level_04` after `level_03` — and a choice of scene type: 2-D, or 3-D
/// (disabled until 3-D authoring ships, unless
/// [EditorDevFlags.allow3DSceneMode] is on). Create:
/// 1. writes `assets/scenes/{name}.scene.json` via [SceneStore], in the
///    chosen mode, at the end of the play order;
/// 2. calls [onSceneCreated] with the name.
class CreateSceneOverlay extends StatefulWidget {
  const CreateSceneOverlay({
    super.key,
    required this.onSceneCreated,
    required this.store,
    this.onCancel,
  });

  /// Where the new scene is written.
  final SceneStore store;

  /// Called with the new scene name after the files have been written.
  final Future<void> Function(String sceneName) onSceneCreated;

  /// Shows a Cancel beside Create, when given.
  final VoidCallback? onCancel;

  /// A free name that follows [after] — the last scene in the play order,
  /// where a new one goes — or else the last of [existing]: `level_03` →
  /// `level_04`, `cave` → `cave_2`; `level_01` when there are none.
  static String suggestName(List<String> existing, {String? after}) =>
      SceneNames.suggest(existing, after: after);

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
    // Ready to go: Enter makes it, typing replaces it.
    final order = widget.store.playOrder();
    final suggested = CreateSceneOverlay.suggestName(
      _existingNames,
      after: order.isEmpty ? null : order.last,
    );
    _controller.value = TextEditingValue(
      text: suggested,
      selection: TextSelection(baseOffset: 0, extentOffset: suggested.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    final error = SceneNameValidator.validate(
      value.trim(),
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

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: EditorMetrics.fontCaption,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _caption('SCENE NAME'),
          TextField(
            controller: _controller,
            onChanged: _onNameChanged,
            onSubmitted: (_) => _canCreate ? _onCreate() : null,
            autofocus: true,
            cursorColor: EditorTheme.primaryBright,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
            decoration: editorFieldDecoration(
              hint: 'e.g. level_01',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ??
                'Letters, digits and underscores; a letter or _ first.',
            style: TextStyle(
              color: _errorMessage != null
                  ? EditorTheme.errorLight
                  : EditorTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          _caption('SCENE TYPE'),
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
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    threeDUnavailable,
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Saved as assets/scenes/${typed.isEmpty ? '{name}' : typed}'
            '.scene.json and added at the end of the play order '
            '(scenes.json). It ships with the game as it is.',
            style: TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onCancel != null) ...[
                EditorButton(
                  label: 'Cancel',
                  kind: EditorButtonKind.ghost,
                  onPressed: widget.onCancel,
                ),
                const SizedBox(width: 8),
              ],
              EditorButton(
                label: _isCreating ? 'Creating…' : 'Create scene',
                kind: EditorButtonKind.primary,
                icon: Icons.add_rounded,
                onPressed: _canCreate ? _onCreate : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
