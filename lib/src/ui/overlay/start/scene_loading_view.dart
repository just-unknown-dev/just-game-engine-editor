import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/scene/scene_loading.dart';

/// What the viewport shows while a scene opens: the editor's backdrop in
/// place of the level being built, so the scene appears whole once its
/// assets are in rather than a sprite at a time. Fades with the card
/// [SceneLoadingBarrier] shows.
class SceneLoadingCover extends StatelessWidget {
  const SceneLoadingCover({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final loading = plugin.sceneIO.loading;
    return SignalConsumer(
      signals: [loading.isShown, plugin.scope.prefs.settings],
      builder: (context, _) {
        final shown = loading.isShown.value;
        return IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: EditorMetrics.motionMedium,
            child: ColoredBox(
              color:
                  plugin.scope.prefs.settings.value.backdrop ??
                  EditorTheme.surfaceDarkest,
            ),
          ),
        );
      },
    );
  }
}

/// The editor while a scene opens: dimmed, taking no presses, and over it
/// a [SceneLoadingCard] with where the open has got to.
///
/// Presses are refused from the start of the open, as are the editor's
/// keys (see the plugin's key handler); the card shows only once the open
/// has taken a moment ([SceneLoading.showAfter]). Nothing while the editor
/// is hidden: the game has the window then.
class SceneLoadingBarrier extends StatefulWidget {
  const SceneLoadingBarrier({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  State<SceneLoadingBarrier> createState() => _SceneLoadingBarrierState();
}

class _SceneLoadingBarrierState extends State<SceneLoadingBarrier> {
  /// The last progress, kept while the card fades out.
  SceneLoadProgress? _last;

  bool _wasShown = false;

  /// Whether the card is fading out. Only then, and while shown, is it
  /// built: a card left at no opacity would turn its spinner for ever.
  bool _fadingOut = false;

  void _faded() {
    if (!mounted || widget.plugin.sceneIO.loading.isShown.value) return;
    if (!_fadingOut && _last == null) return;
    setState(() {
      _fadingOut = false;
      _last = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final loading = plugin.sceneIO.loading;
    return SignalConsumer(
      signals: [loading.progress, loading.isShown, plugin.isVisible],
      builder: (context, _) {
        if (!plugin.isVisible.value) return const SizedBox.shrink();
        final progress = loading.progress.value;
        final shown = loading.isShown.value;
        if (progress != null) _last = progress;
        if (shown) {
          _wasShown = true;
          _fadingOut = false;
        } else if (_wasShown) {
          _wasShown = false;
          // With motion off there is no fade to wait for.
          _fadingOut = EditorMetrics.motionMedium > Duration.zero;
        }
        final last = shown || _fadingOut ? _last : null;
        return IgnorePointer(
          ignoring: !loading.isLoading,
          child: BlockSemantics(
            blocking: shown,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: EditorMetrics.motionMedium,
              onEnd: _faded,
              child: ColoredBox(
                color: Colors.black54,
                child: last == null
                    ? const SizedBox.expand()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.sizeOf(context).height - 48,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: SceneLoadingCard(
                                progress: last,
                                onSkip: loading.isWaitingOnAssets
                                    ? loading.skip
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where a scene's opening has got to: its name, what the step under way
/// is doing, a bar for the whole open, and its steps ticked off as they
/// finish — the one under way with its count, `120 of 450`.
class SceneLoadingCard extends StatelessWidget {
  const SceneLoadingCard({super.key, required this.progress, this.onSkip});

  final SceneLoadProgress progress;

  /// Shows the scene before its assets are in. Null while there is nothing
  /// to skip: the entities are still being made.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final percent = (p.fraction * 100).floor();
    final status = p.isFinished ? 'Ready' : p.detail ?? '${p.stage.doing}…';
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: 'Opening ${p.sceneName}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: EditorTheme.panelBg,
          borderRadius: BorderRadius.circular(EditorMetrics.radiusLg + 4),
          border: Border.all(color: EditorTheme.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: EditorTheme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(EditorMetrics.radiusLg),
                    border: Border.all(
                      color: EditorTheme.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Icon(
                    Icons.map_outlined,
                    color: EditorTheme.accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opening ${p.sceneName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Read out as it changes: the step, not every count.
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: EditorTheme.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      color: EditorTheme.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 6,
                backgroundColor: EditorTheme.surfaceDarker,
                valueColor: AlwaysStoppedAnimation(EditorTheme.accent),
                semanticsLabel: 'Opening ${p.sceneName}',
                semanticsValue: '$percent%',
              ),
            ),
            const SizedBox(height: 12),
            for (final stage in SceneLoadStage.values)
              _StageRow(stage: stage, progress: p, still: still),
            const SizedBox(height: 10),
            const EditorDivider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    onSkip == null
                        ? 'The editor takes edits again once the scene is '
                              'built.'
                        : 'What is still loading arrives in place.',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (onSkip != null) ...[
                  const KeyCap('Esc'),
                  const SizedBox(width: 8),
                ],
                EditorButton(
                  label: 'Show now',
                  icon: Icons.visibility_outlined,
                  kind: EditorButtonKind.ghost,
                  onPressed: onSkip,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One step of the open: ticked once done, turning while under way — with
/// its count, when it has one — and dimmed while still to come.
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.progress,
    required this.still,
  });

  final SceneLoadStage stage;
  final SceneLoadProgress progress;

  /// Whether motion is off: the step under way shows a dot, not a spinner.
  final bool still;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final done = p.isFinished || stage.index < p.stage.index;
    final active = !done && stage == p.stage;
    final count = active && p.total > 0 ? '${p.done} of ${p.total}' : null;
    final Widget mark;
    if (done) {
      mark = Icon(
        Icons.check_circle_rounded,
        size: 15,
        color: EditorTheme.success,
      );
    } else if (active && !still) {
      mark = Padding(
        padding: const EdgeInsets.all(1.5),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(EditorTheme.accent),
        ),
      );
    } else {
      mark = Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 15,
        color: active ? EditorTheme.accent : EditorTheme.textMuted,
      );
    }
    final state = done
        ? 'done'
        : active
        ? 'under way'
        : 'to come';
    return Semantics(
      label: '${stage.label}: $state${count == null ? '' : ', $count'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 15, height: 15, child: mark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stage.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done || active
                      ? EditorTheme.textPrimary
                      : EditorTheme.textMuted,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (count != null)
              Text(
                count,
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
