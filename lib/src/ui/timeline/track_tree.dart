/// The left-hand side of the Timeline dock: who each group of tracks acts
/// on, and a row per track — its name, its value now, a key button, mute and
/// lock.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'dope_sheet.dart';
import 'timeline_dialogs.dart';
import 'timeline_menu.dart';
import 'timeline_session.dart';

/// What a person calls a track: `Position · X` rather than
/// `TransformComponent.position.x`.
String timelineTrackLabel(TimelineSession session, jge.TimelineTrack track) {
  if (track.name.isNotEmpty) return track.name;
  if (track is! jge.PropertyTrack) return track.summary;
  final definition = session.scope.definitions.definitionByType(
    track.component,
  );
  final component = definition?.hints.name ?? track.component;
  final field = definition?.hints.fields[track.field]?.label ?? track.field;
  final channel = track.channel.isEmpty
      ? ''
      : ' · ${track.channel.replaceFirst('d', '').toUpperCase()}';
  return '$component  ›  $field$channel';
}

class TrackTree extends StatelessWidget {
  const TrackTree({
    super.key,
    required this.session,
    required this.rows,
    required this.controller,
  });

  final TimelineSession session;
  final List<TimelineRow> rows;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final asset = session.asset.value!;
    return ListView.builder(
      controller: controller,
      itemExtent: TimelineMetrics.rowHeight,
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        TimelineGroupRow row => _GroupRow(
          session: session,
          binding: row.binding,
        ),
        TimelineTrackRow row => _TrackRow(
          session: session,
          index: row.index,
          track: asset.tracks[row.index],
        ),
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.session, required this.binding});

  final TimelineSession session;
  final jge.TrackBinding binding;

  @override
  Widget build(BuildContext context) {
    final entity = binding.resolve(session.scope.world, session.owner);
    final who = binding.isSelf
        ? 'Self${entity?.name == null ? '' : '  (${entity!.name})'}'
        : binding.label;
    return Container(
      color: EditorTheme.surfaceDark,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            binding.isSelf
                ? Icons.person_pin_circle_outlined
                : binding.kind == jge.TrackBindingKind.tag
                ? Icons.sell_outlined
                : Icons.category_outlined,
            size: 12,
            color: EditorTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              who,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Nobody to act on is worth saying: the tracks below do nothing.
          if (entity == null)
            Tooltip(
              message: 'Nothing in the scene answers to this.',
              child: Icon(
                Icons.link_off_rounded,
                size: 12,
                color: EditorTheme.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.session,
    required this.index,
    required this.track,
  });

  final TimelineSession session;
  final int index;
  final jge.TimelineTrack track;

  @override
  Widget build(BuildContext context) {
    final selected = session.selectedTrack.value == index;
    final track = this.track;
    final time = session.playhead.value;

    String readout = '';
    var keyHere = false;
    if (track is jge.PropertyTrack) {
      final v = track.curve.valueAt(
        time,
        isColor: track.isColor,
        easings: session.scope.context.easings,
      );
      readout = switch (v) {
        null => '',
        final int c when track.isColor =>
          '#${c.toRadixString(16).padLeft(8, '0').toUpperCase()}',
        final num n => n.toStringAsFixed(n.abs() >= 100 ? 0 : 2),
        _ => '$v',
      };
      keyHere = track.curve.keys.any((k) => (k.time - time).abs() < 1e-6);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => session.selectedTrack.value = index,
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? EditorTheme.selectionBg.withValues(alpha: 0.45)
              : null,
          border: Border(
            bottom: BorderSide(
              color: EditorTheme.textPrimary.withValues(alpha: 0.05),
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 18, right: 4),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: timelineTrackColor(track),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                timelineTrackLabel(session, track),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: track.muted
                      ? EditorTheme.textMuted
                      : EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            if (track is jge.PropertyTrack && track.isRelative)
              const Tooltip(
                message:
                    'Relative: the keys are offsets from where the field '
                    'was when the timeline started.',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    'Δ',
                    style: TextStyle(
                      color: GizmoConstants.colSel,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            if (readout.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  readout,
                  style: TextStyle(
                    color: EditorTheme.textMuted,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (track is jge.PropertyTrack)
              _RowButton(
                icon: keyHere ? Icons.diamond : Icons.diamond_outlined,
                tooltip: keyHere ? 'A key is here' : 'Add a key here  (K)',
                color: keyHere ? EditorTheme.warning : EditorTheme.textMuted,
                onTap: () {
                  final ref = session.setKey(index, time);
                  if (ref != null) session.selection.value = {ref};
                },
              ),
            _RowButton(
              icon: track.muted
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              tooltip: track.muted ? 'Muted' : 'Mute',
              color: track.muted ? EditorTheme.warning : EditorTheme.textMuted,
              onTap: () => session.replaceTrack(
                index,
                track.withBase(muted: !track.muted),
                track.muted ? 'Unmute' : 'Mute',
              ),
            ),
            _RowButton(
              icon: track.locked
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              tooltip: track.locked ? 'Locked' : 'Lock',
              color: track.locked ? EditorTheme.warning : EditorTheme.textMuted,
              onTap: () => session.replaceTrack(
                index,
                track.withBase(locked: !track.locked),
                track.locked ? 'Unlock' : 'Lock',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Offset at) async {
    session.selectedTrack.value = index;
    final track = this.track;
    final choice = await showTimelineMenu<String>(context, at, [
      timelineMenuItem('rename', 'Rename…'),
      timelineMenuItem('bind', 'Bind to…'),
      if (track is jge.PropertyTrack && !track.isColor)
        timelineMenuItem(
          'mode',
          track.isRelative ? 'Make absolute' : 'Make relative',
        ),
      timelineMenuDivider(),
      timelineMenuItem('delete', 'Delete track'),
    ]);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'rename':
        final name = await promptTimelineText(
          context,
          title: 'Track name',
          initial: track.name,
          hint: 'Empty: what it animates',
        );
        if (name != null) {
          session.replaceTrack(index, track.withBase(name: name), 'Rename');
        }
      case 'bind':
        final binding = await promptTrackBinding(
          context,
          session,
          initial: track.binding,
        );
        if (binding != null) {
          session.replaceTrack(index, track.withBase(binding: binding), 'Bind');
        }
      case 'mode':
        if (track is jge.PropertyTrack) {
          session.replaceTrack(
            index,
            track.copyWith(
              mode: track.isRelative
                  ? jge.PropertyTrackMode.absolute
                  : jge.PropertyTrackMode.relative,
            ),
            'Track mode',
          );
        }
      case 'delete':
        session.removeTrack(index);
    }
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 13, color: color),
      ),
    ),
  );
}
