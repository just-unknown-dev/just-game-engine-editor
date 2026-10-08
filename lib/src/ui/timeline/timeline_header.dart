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
    return EditorToolbar(
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
                EditorIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'To the start  (Home)',
                  onTap: () => session
                    ..pause()
                    ..scrubTo(0)
                    ..scrollTo(0),
                ),
                EditorIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Back a frame  (,)',
                  onTap: () => session.stepFrames(-1),
                ),
                EditorIconButton(
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
                EditorIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'On a frame  (.)',
                  onTap: () => session.stepFrames(1),
                ),
                EditorIconButton(
                  icon: Icons.fiber_manual_record_rounded,
                  tooltip: session.record.value
                      ? 'Recording: what you change becomes a key here'
                      : 'Record: turn changes made anywhere into keys  (R)',
                  isActive: session.record.value,
                  // Red, lit or not: the record button everywhere.
                  color: EditorTheme.error,
                  onTap: () => session.setRecording(!session.record.value),
                ),
                EditorIconButton(
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
                        style: TextStyle(
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
                      style: TextStyle(
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
        ..._playRange(context),
        ..._selected(context),
        EditorIconButton(
          icon: Icons.show_chart_rounded,
          tooltip: session.showCurves.value
              ? 'Back to the dope sheet  (Tab)'
              : 'Edit curves  (Tab)',
          isActive: session.showCurves.value,
          onTap: () => session.showCurves.value = !session.showCurves.value,
        ),
        EditorIconButton(
          icon: Icons.grid_on_rounded,
          tooltip: 'Snap to frames',
          isActive: session.snap.value,
          onTap: () => session.snap.value = !session.snap.value,
        ),
        EditorIconButton(
          icon: Icons.fit_screen_outlined,
          tooltip: 'Show the whole timeline  (F)',
          onTap: onFit,
        ),
        EditorIconButton(
          icon: Icons.undo_rounded,
          tooltip: 'Undo  (Ctrl+Z)',
          onTap: session.canUndo ? session.undo : null,
        ),
        EditorIconButton(
          icon: Icons.redo_rounded,
          tooltip: 'Redo  (Ctrl+Y)',
          onTap: session.canRedo ? session.redo : null,
        ),
        if (session.isInline)
          EditorIconButton(
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
          EditorIconButton(
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

  /// What this entity plays of the timeline. Two boxes and a cross beat a
  /// gesture nobody can guess at.
  List<Widget> _playRange(BuildContext context) {
    final player = session.player;
    if (player == null) return const [];
    final range = session.playRange ?? (0.0, session.duration);
    return [
      Tooltip(
        message: player.hasRange
            ? 'This entity plays only part of the timeline. Drag the ends on '
                  'the ruler, or type here.'
            : 'Set what this entity plays of the timeline. The rest stays '
                  'authored, and other entities can play all of it.',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              player.hasRange
                  ? Icons.filter_center_focus_rounded
                  : Icons.all_inclusive_rounded,
              size: 12,
              color: player.hasRange
                  ? EditorTheme.primaryBright
                  : EditorTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              'Plays',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
      // A timeline starts at zero, and so does almost every play range, so
      // the start is only worth a box once it is not zero — dragged there on
      // the ruler, or set on the player itself.
      if (range.$1 > 0) ...[
        _timeBox(
          label: '',
          tooltip: 'From here',
          seconds: range.$1,
          width: 42,
          onSeconds: (v) => session.setPlayRange(v, range.$2),
        ),
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: Text(
            '→',
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
      ] else
        Padding(
          padding: EdgeInsets.only(right: 6),
          child: Text(
            'to',
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
      _timeBox(
        label: '',
        tooltip: 'To here',
        seconds: range.$2,
        width: 42,
        onSeconds: (v) => session.setPlayRange(range.$1, v),
      ),
      if (player.hasRange)
        EditorIconButton(
          icon: Icons.close_rounded,
          tooltip: 'Play the whole timeline again',
          onTap: session.clearPlayRange,
        ),
      const SizedBox(width: 8),
    ];
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
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
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
    // Kept on Enter, on leaving — Tab, a click elsewhere — and before Save
    // while it is typed in.
    _focus.addListener(() {
      if (_focus.hasFocus) {
        PendingFieldEdits.join(_keep);
      } else {
        PendingFieldEdits.leave(_keep);
        _submit();
      }
    });
  }

  @override
  void didUpdateWidget(_NumberBox old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) _text.text = _shown;
  }

  void _submit() {
    _keep();
    // Not a number, or refused: shows what it still is.
    _text.text = _shown;
  }

  void _keep() {
    final v = double.tryParse(_text.text.trim());
    if (v != null && v != widget.value) widget.onSubmitted(v);
  }

  /// Esc, with a change typed: what was there, and out of the field.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isEscapeDown(event) || _text.text == _shown) {
      return KeyEventResult.ignored;
    }
    _text.text = _shown;
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    PendingFieldEdits.leave(_keep);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 4),
        ],
        SizedBox(
          width: widget.width,
          height: 20,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
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
        ),
        const SizedBox(width: 8),
      ],
    ),
  );
}
