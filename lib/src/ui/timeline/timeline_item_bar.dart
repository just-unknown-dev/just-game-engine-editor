/// The strip under the header that edits the one selected thing: a key's
/// value and how it reaches the next, an event's name, a block's clip, camera
/// or file.
library;

import 'package:flutter/material.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'timeline_menu.dart';
import 'timeline_session.dart';

class TimelineItemBar extends StatelessWidget {
  const TimelineItemBar({super.key, required this.session});

  final TimelineSession session;

  /// Whether there is anything to show: exactly one item is selected.
  static bool showsFor(TimelineSession session) =>
      session.selection.value.length == 1 &&
      session.timeOf(session.selection.value.single) != null;

  @override
  Widget build(BuildContext context) {
    final single = showsFor(session);
    final ref = single ? session.selection.value.single : null;
    final track = ref == null ? null : session.asset.value!.tracks[ref.track];
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        border: Border(
          bottom: BorderSide(
            color: EditorTheme.textPrimary.withValues(alpha: 0.06),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: switch (track) {
            jge.PropertyTrack t => _key(context, ref!, t),
            jge.EventTrack t => _event(ref!, t),
            jge.BlockTrack t => _block(context, ref!, t),
            _ => [
              Text(
                session.selection.value.length > 1
                    ? 'Drag to move · Alt-drag to stretch · '
                          '${EditorKeys.withPrimary('C')} / V / D · '
                          'Shift+Delete ripples'
                    : 'Double-click a track to add to it. Select a key, an '
                          'event or a block to edit it here.',
                style: _label,
              ),
            ],
          },
        ),
      ),
    );
  }

  Widget _time(String label, double time, ValueChanged<double> onChanged) =>
      TimelineField(
        label: label,
        tooltip: session.showFrames.value ? 'In frames' : 'In seconds',
        text: session.showFrames.value
            ? '${session.frameOf(time)}'
            : _trim(time),
        width: 50,
        onSubmitted: (v) {
          final n = _finite(v);
          if (n == null) return;
          onChanged(session.showFrames.value ? n / session.fps : n);
        },
      );

  /// [text] as a number a timeline can hold: `NaN` and `Infinity` parse
  /// as numbers, but no file can save them.
  static double? _finite(String text) {
    final n = double.tryParse(text.trim());
    return n != null && n.isFinite ? n : null;
  }

  /// [text] as an ARGB colour: `AARRGGBB`, or `RRGGBB` for an opaque one,
  /// with or without a `#`. Null when it is neither.
  static int? parseArgb(String text) {
    final hex = text.trim().replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final n = int.tryParse(hex, radix: 16);
    if (n == null) return null;
    return hex.length == 6 ? 0xFF000000 | n : n;
  }

  static String _trim(double v) => v
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  // ── A key ────────────────────────────────────────────────────────────────

  List<Widget> _key(
    BuildContext context,
    TimelineItemRef ref,
    jge.PropertyTrack track,
  ) {
    final key = track.curve.keys[ref.index];
    final value = key.value;
    void set(jge.TimelineKey next, String label) {
      session.updateKey(ref, next, label: label);
      // The key may have moved among its neighbours.
      final index = session.asset.value!.tracks[ref.track] is jge.PropertyTrack
          ? (session.asset.value!.tracks[ref.track] as jge.PropertyTrack)
                .curve
                .keys
                .indexWhere((k) => (k.time - next.time).abs() < 1e-6)
          : -1;
      if (index >= 0) {
        session.selection.value = {TimelineItemRef(ref.track, index)};
      }
    }

    return [
      _time(
        'Time',
        key.time,
        (t) => set(key.copyWith(time: session.snapTime(t)), 'Key time'),
      ),
      if (value is num && !track.isColor)
        TimelineField(
          label: track.isRelative ? 'Offset' : 'Value',
          tooltip: 'The selected key',
          text: _trim(value.toDouble()),
          width: 64,
          onSubmitted: (v) {
            final n = _finite(v);
            if (n != null) set(key.copyWith(value: n), 'Key value');
          },
        )
      else if (track.isColor && value is int)
        TimelineField(
          label: 'Colour',
          tooltip: 'AARRGGBB',
          text: value.toRadixString(16).padLeft(8, '0').toUpperCase(),
          width: 74,
          onSubmitted: (v) {
            final n = parseArgb(v);
            if (n != null) set(key.copyWith(value: n), 'Key value');
          },
        )
      else if (value is bool)
        TimelineToggle(
          label: 'On',
          value: value,
          onChanged: (v) => set(key.copyWith(value: v), 'Key value'),
        )
      else
        TimelineField(
          label: 'Value',
          tooltip: 'Held until the next key',
          text: '$value',
          width: 130,
          onSubmitted: (v) => set(key.copyWith(value: v), 'Key value'),
        ),
      if (value is num)
        TimelineChoice<String>(
          label: 'To next',
          value: key.interpolation == jge.KeyInterpolation.eased
              ? key.easing
              : key.interpolation.name,
          options: [
            jge.KeyInterpolation.bezier.name,
            jge.KeyInterpolation.linear.name,
            jge.KeyInterpolation.step.name,
            ...session.scope.context.easings.names.where((n) => n != 'linear'),
          ],
          text: (v) => switch (v) {
            'bezier' => 'Smooth',
            'linear' => 'Linear',
            'step' => 'Hold',
            _ => v,
          },
          onChanged: (v) {
            final mode = jge.KeyInterpolation.values.asNameMap()[v];
            set(
              mode != null && mode != jge.KeyInterpolation.eased
                  ? key.copyWith(interpolation: mode, easing: '')
                  : key.copyWith(
                      interpolation: jge.KeyInterpolation.eased,
                      easing: v,
                    ),
              'Interpolation',
            );
          },
        ),
      if (value is num && key.interpolation == jge.KeyInterpolation.bezier)
        TimelineChoice<jge.TangentMode>(
          label: 'Handles',
          value: key.tangentMode,
          options: jge.TangentMode.values,
          text: (m) => switch (m) {
            jge.TangentMode.auto => 'Auto',
            jge.TangentMode.flat => 'Flat',
            jge.TangentMode.aligned => 'Aligned',
            jge.TangentMode.broken => 'Broken',
          },
          onChanged: (m) => set(key.copyWith(tangentMode: m), 'Handles'),
        ),
    ];
  }

  // ── An event ─────────────────────────────────────────────────────────────

  List<Widget> _event(TimelineItemRef ref, jge.EventTrack track) {
    final event = track.events[ref.index];
    void set(jge.TimelineEvent next) => session.updateEvent(ref, next);
    return [
      _time(
        'Time',
        event.time,
        (t) => set(event.copyWith(time: session.snapTime(t))),
      ),
      TimelineField(
        label: 'Event',
        tooltip: 'The name listeners hear',
        text: event.name,
        width: 130,
        onSubmitted: (v) {
          if (v.isNotEmpty) set(event.copyWith(name: v));
        },
      ),
      TimelineField(
        label: 'Payload',
        tooltip: 'Whatever the listener wants to be told',
        text: event.payload,
        width: 130,
        onSubmitted: (v) => set(event.copyWith(payload: v)),
      ),
      TimelineToggle(
        label: 'Signal',
        tooltip:
            'Also a timeline signal: starts every Timeline Player that '
            'listens for this name.',
        value: event.signal,
        onChanged: (v) => set(event.copyWith(signal: v)),
      ),
    ];
  }

  // ── A block ──────────────────────────────────────────────────────────────

  List<Widget> _block(
    BuildContext context,
    TimelineItemRef ref,
    jge.BlockTrack track,
  ) {
    final block = track.blocks[ref.index];
    void set(jge.TimelineBlock next) => session.updateBlock(ref, next);
    final valueLabel = track.valueLabel, amountLabel = track.amountLabel;
    return [
      _time(
        'Start',
        block.start,
        (t) => set(block.copyWith(start: session.snapTime(t))),
      ),
      if (!track.isInstant)
        _time('Length', block.length, (t) {
          if (t > 0) set(block.copyWith(length: t));
        }),
      if (valueLabel != null) ...[
        TimelineField(
          label: valueLabel,
          tooltip: valueLabel,
          text: block.value,
          width: 170,
          onSubmitted: (v) => set(block.copyWith(value: v)),
        ),
        _Suggest(
          options: () => _suggestions(track),
          onPicked: (v) => set(block.copyWith(value: v)),
        ),
      ],
      if (track.hasSpeed)
        TimelineField(
          label: 'Speed',
          tooltip: 'How fast it runs inside the block',
          text: _trim(block.speed),
          width: 44,
          onSubmitted: (v) {
            final n = _finite(v);
            if (n != null && n > 0) set(block.copyWith(speed: n));
          },
        ),
      if (amountLabel != null)
        TimelineField(
          label: amountLabel,
          tooltip: amountLabel,
          text: _trim(block.amount),
          width: 50,
          onSubmitted: (v) {
            final n = _finite(v);
            if (n != null) set(block.copyWith(amount: n));
          },
        ),
      if (track.hasSpeed)
        TimelineToggle(
          label: 'Loop',
          value: block.loop,
          onChanged: (v) => set(block.copyWith(loop: v)),
        ),
    ];
  }

  /// What a block's value could be: the bound sprite's clips, the scene's
  /// virtual cameras, the project's files of the right kind.
  List<String> _suggestions(jge.BlockTrack track) {
    final world = session.scope.world;
    if (track is jge.SpriteClipTrack) {
      final entity = track.binding.resolve(world, session.owner);
      if (entity == null) return const [];
      for (final system in world.systems) {
        if (system is jge.SpriteAnimationSystem) {
          return system.atlasOf(entity)?.clipNames.toList() ?? const [];
        }
      }
      return const [];
    }
    if (track is jge.CameraShotTrack) {
      return [
        for (final e in world.query([jge.VirtualCameraComponent]))
          if ((e.name ?? '').isNotEmpty) e.name!,
      ]..sort();
    }
    final extensions = track.valueExtensions;
    if (extensions.isEmpty) return const [];
    final assets = Directory('${session.root}/assets');
    final prefix = '${session.root}/';
    return [
      if (assets.existsSync())
        for (final f in assets.listSync(recursive: true).whereType<File>())
          if (f.path.replaceAll('\\', '/') case final path
              when extensions.any((x) => path.toLowerCase().endsWith('.$x')) &&
                  path != '$prefix${session.path}')
            path.substring(prefix.length),
      // Installed packages' files too, as `packages/<name>/…`.
      for (final key in PackageAssetPaths.of(
        session.root,
      ).packageFiles(endings: [for (final x in extensions) '.$x']))
        if (key != session.path) key,
    ]..sort();
  }
}

class _Suggest extends StatelessWidget {
  const _Suggest({required this.options, required this.onPicked});

  final List<String> Function() options;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(3),
      onTap: () async {
        final found = options();
        final box = context.findRenderObject()! as RenderBox;
        final at = box.localToGlobal(Offset(0, box.size.height));
        final picked = await showTimelineMenu<String>(context, at, [
          if (found.isEmpty)
            timelineMenuItem('', 'Nothing to pick from', enabled: false),
          for (final o in found) timelineMenuItem(o, o),
        ]);
        if (picked != null) onPicked(picked);
      },
      child: Padding(
        padding: EdgeInsets.all(3),
        child: Icon(
          Icons.arrow_drop_down_circle_outlined,
          size: 14,
          color: EditorTheme.primaryBright,
        ),
      ),
    ),
  );
}

TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 10);
TextStyle get _value => TextStyle(
  color: EditorTheme.textPrimary,
  fontSize: 11,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// A small labelled text box that commits on Enter or on losing focus — Tab,
/// a click elsewhere — and before Save while it is typed in. Esc puts back
/// what was there.
class TimelineField extends StatefulWidget {
  const TimelineField({
    super.key,
    required this.label,
    required this.tooltip,
    required this.text,
    required this.width,
    required this.onSubmitted,
  });

  final String label;
  final String tooltip;
  final String text;
  final double width;
  final ValueChanged<String> onSubmitted;

  @override
  State<TimelineField> createState() => _TimelineFieldState();
}

class _TimelineFieldState extends State<TimelineField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.text,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
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
  void didUpdateWidget(TimelineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_focus.hasFocus) {
      _text.text = widget.text;
    }
  }

  void _submit() {
    _keep();
    // Whatever was refused shows as it still is.
    if (mounted) _text.text = widget.text;
  }

  /// What was typed, kept — before Save, the field still being typed in,
  /// keeps it showing.
  void _keep() {
    final v = _text.text.trim();
    if (v != widget.text) widget.onSubmitted(v);
  }

  /// Esc, with a change typed: what was there, and out of the field.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isEscapeDown(event) || _text.text.trim() == widget.text) {
      return KeyEventResult.ignored;
    }
    _text.text = widget.text;
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
        Text(widget.label, style: _label),
        const SizedBox(width: 4),
        SizedBox(
          width: widget.width,
          height: 20,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: _box(),
          ),
        ),
        const SizedBox(width: 10),
      ],
    ),
  );

  Widget _box() => TextField(
    controller: _text,
    focusNode: _focus,
    onSubmitted: (_) => _submit(),
    style: _value,
    decoration: InputDecoration(
      isDense: true,
      filled: true,
      fillColor: EditorTheme.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class TimelineToggle extends StatelessWidget {
  const TimelineToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final body = InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 13,
              color: value ? EditorTheme.primaryBright : EditorTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(label, style: _label),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

class TimelineChoice<T> extends StatelessWidget {
  const TimelineChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: _label),
      const SizedBox(width: 4),
      PopupMenuButton<T>(
        tooltip: label,
        color: EditorTheme.menuBg,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final o in options) timelineMenuItem(o, text(o), height: 28),
        ],
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EditorTheme.inputBg,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('${text(value)} ▾', style: _value),
        ),
      ),
      const SizedBox(width: 10),
    ],
  );
}
