/// The strip along the top of the Timeline dock: what is open, the
/// transport, the time, the timeline's own settings, and the selected key.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../overlay/docks/shared/dock_widgets.dart';
import 'timeline_dialogs.dart';
import 'timeline_menu.dart';
import 'timeline_session.dart';

class TimelineHeader extends StatelessWidget {
  const TimelineHeader({super.key, required this.session, required this.onFit});

  final TimelineSession session;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final asset = session.asset.value!;
    final path = session.path;
    final source = path == null
        ? 'Inline · ${session.owner?.name ?? 'entity'}'
        : path
              .split('/')
              .last
              .replaceAll('.${jge.TimelineAsset.fileExtension}', '');

    // The left of the bar scrolls when the dock is narrow, so nothing is
    // ever cut off; the buttons on the right stay where they are.
    return DockToolbar(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Tooltip(
                  message: path ?? 'Saved inside the scene, with this entity.',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      '${session.isDirty.value ? '● ' : ''}$source',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: session.isDirty.value
                            ? EditorTheme.warning
                            : EditorTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DockIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'To the start  (Home)',
                  onTap: () => session
                    ..pause()
                    ..scrubTo(0)
                    ..scrollTo(0),
                ),
                DockIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Back a frame  (,)',
                  onTap: () => session.stepFrames(-1),
                ),
                DockIconButton(
                  icon: session.isPlaying.value
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: session.isPlaying.value
                      ? 'Pause  (Space)'
                      : 'Play  (Space)',
                  isActive: session.isPlaying.value,
                  onTap: () => session.isPlaying.value
                      ? session.pause()
                      : session.play(),
                ),
                DockIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'On a frame  (.)',
                  onTap: () => session.stepFrames(1),
                ),
                DockIconButton(
                  icon: Icons.fiber_manual_record_rounded,
                  tooltip: session.record.value
                      ? 'Recording: what you change becomes a key here'
                      : 'Record: turn changes made anywhere into keys  (R)',
                  isActive: session.record.value,
                  color: session.record.value
                      ? EditorTheme.error
                      : EditorTheme.primaryBright,
                  onTap: () => session.setRecording(!session.record.value),
                ),
                DockIconButton(
                  icon: Icons.stop_rounded,
                  tooltip: 'Stop, and show the scene as it is saved',
                  isActive: session.isPreviewing,
                  onTap: session.stop,
                ),
                const SizedBox(width: 6),
                _divider(),
                Tooltip(
                  message:
                      'Click to show ${session.showFrames.value ? 'seconds' : 'frames'}',
                  child: InkWell(
                    onTap: () =>
                        session.showFrames.value = !session.showFrames.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        '${session.formatTime(session.playhead.value)} / '
                        '${session.formatTime(asset.duration)}',
                        style: const TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _divider(),
                _timeBox(
                  label: 'Length',
                  tooltip: 'How long the timeline is',
                  seconds: asset.duration,
                  width: 46,
                  onSeconds: (v) {
                    if (v > 0) {
                      session.apply('Length', asset.copyWith(duration: v));
                    }
                  },
                ),
                _NumberBox(
                  label: 'FPS',
                  tooltip: 'Frames per second: how time is divided and snapped',
                  value: asset.fps.toDouble(),
                  width: 34,
                  integer: true,
                  onSubmitted: (v) {
                    if (v >= 1) {
                      session.apply('FPS', asset.copyWith(fps: v.round()));
                    }
                  },
                ),
                PopupMenuButton<jge.TimelineWrap>(
                  tooltip: 'What happens at the end',
                  color: EditorTheme.menuBg,
                  onSelected: (w) =>
                      session.apply('Wrap', asset.copyWith(wrap: w)),
                  itemBuilder: (context) => [
                    for (final w in jge.TimelineWrap.values)
                      timelineMenuItem(w, _wrapLabel(w)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${_wrapLabel(asset.wrap)} ▾',
                      style: const TextStyle(
                        color: EditorTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (session.player != null) _divider(),
        ..._selected(context),
        DockIconButton(
          icon: Icons.show_chart_rounded,
          tooltip: session.showCurves.value
              ? 'Back to the dope sheet  (Tab)'
              : 'Edit curves  (Tab)',
          isActive: session.showCurves.value,
          onTap: () => session.showCurves.value = !session.showCurves.value,
        ),
        DockIconButton(
          icon: Icons.grid_on_rounded,
          tooltip: 'Snap to frames',
          isActive: session.snap.value,
          onTap: () => session.snap.value = !session.snap.value,
        ),
        DockIconButton(
          icon: Icons.fit_screen_outlined,
          tooltip: 'Show the whole timeline  (F)',
          onTap: onFit,
        ),
        DockIconButton(
          icon: Icons.undo_rounded,
          tooltip: 'Undo  (Ctrl+Z)',
          color: session.canUndo
              ? EditorTheme.primaryBright
              : EditorTheme.textMuted,
          onTap: session.undo,
        ),
        DockIconButton(
          icon: Icons.redo_rounded,
          tooltip: 'Redo  (Ctrl+Y)',
          color: session.canRedo
              ? EditorTheme.primaryBright
              : EditorTheme.textMuted,
          onTap: session.redo,
        ),
        if (session.isInline)
          DockIconButton(
            icon: Icons.output_rounded,
            tooltip:
                'Extract to a .timeline.json, so other entities can play it',
            onTap: () async {
              final name = await promptTimelineText(
                context,
                title: 'Name the timeline',
                initial: (session.owner?.name ?? 'timeline').toLowerCase(),
              );
              if (name != null && name.isNotEmpty) {
                await session.extractToAsset(name);
              }
            },
          )
        else
          DockIconButton(
            icon: Icons.save_outlined,
            tooltip: 'Save  (Ctrl+S)',
            isActive: session.isDirty.value,
            onTap: session.save,
          ),
      ],
    );
  }

  /// A box holding a time, in whichever unit the dock is counting.
  Widget _timeBox({
    required String label,
    required String tooltip,
    required double seconds,
    required double width,
    required ValueChanged<double> onSeconds,
  }) {
    final frames = session.showFrames.value;
    return _NumberBox(
      label: label,
      tooltip: '$tooltip, in ${frames ? 'frames' : 'seconds'}',
      value: frames ? session.frameOf(seconds).toDouble() : seconds,
      width: width,
      integer: frames,
      onSubmitted: (v) => onSeconds(frames ? v / session.fps : v),
    );
  }

  /// A hairline between groups of controls.
  static Widget _divider() => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.only(right: 10),
    color: EditorTheme.textPrimary.withValues(alpha: 0.12),
  );

  static String _wrapLabel(jge.TimelineWrap w) => switch (w) {
    jge.TimelineWrap.once => 'Once',
    jge.TimelineWrap.loop => 'Loop',
    jge.TimelineWrap.pingPong => 'Ping-pong',
  };

  /// How many things are selected; one is edited in the item bar below.
  List<Widget> _selected(BuildContext context) {
    final count = session.selection.value.length;
    return [
      if (count > 1)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '$count selected',
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
    ];
  }
}

class _NumberBox extends StatefulWidget {
  const _NumberBox({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.width,
    required this.onSubmitted,
    this.integer = false,
  });

  final String label;
  final String tooltip;
  final double value;
  final double width;
  final bool integer;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _text = TextEditingController(text: _shown);
  final FocusNode _focus = FocusNode();

  String get _shown => widget.integer
      ? '${widget.value.round()}'
      : widget.value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(_NumberBox old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) _text.text = _shown;
  }

  void _submit() {
    final v = double.tryParse(_text.text.trim());
    if (v != null && v != widget.value) widget.onSubmitted(v);
    _text.text = _shown;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    waitDuration: const Duration(milliseconds: 600),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 4),
        ],
        SizedBox(
          width: widget.width,
          height: 20,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: EditorTheme.inputBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );
}
