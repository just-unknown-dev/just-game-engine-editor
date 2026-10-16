import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'tileset_session.dart';

/// A tile's animation: the frames it shows, each for so long, and a
/// preview playing them.
///
/// Select the frames in the grid and press *Animate selection* to make the
/// lowest of them play through all of them; then adjust each frame here.
class TileAnimationEditor extends StatelessWidget {
  const TileAnimationEditor({super.key, required this.session});

  final TilesetSession session;

  @override
  Widget build(BuildContext context) {
    final id = session.primary;
    if (id == null) return const SizedBox.shrink();
    final ts = session.data;
    final frames = ts.tile(id)?.animation ?? const <TileFrame>[];
    final many = session.selection.value.length > 1;

    void write(List<TileFrame> next, {Object? mergeKey}) =>
        session.setAnimation(id, next, mergeKey: mergeKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (frames.length > 1)
          Center(
            child: _Preview(
              key: ValueKey(('preview', id)),
              image: session.image.value,
              tileset: ts,
              def: ts.tile(id)!,
              tileId: id,
            ),
          ),
        for (var i = 0; i < frames.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _Thumb(
                  image: session.image.value,
                  source: ts.contains(frames[i].tileId)
                      ? ts.sourceRect(frames[i].tileId)
                      : null,
                ),
                const SizedBox(width: 6),
                Text('tile', style: _label),
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  child: MiniNumberField(
                    value: frames[i].tileId.toDouble(),
                    fractionDigits: 0,
                    onSubmitted: (v) {
                      final tile = v.round().clamp(0, ts.tileCount - 1);
                      write(
                        [...frames]
                          ..[i] = TileFrame(tile, frames[i].durationMs),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 52,
                  child: MiniNumberField(
                    value: frames[i].durationMs.toDouble(),
                    fractionDigits: 0,
                    onSubmitted: (v) => write(
                      [...frames]
                        ..[i] = TileFrame(
                          frames[i].tileId,
                          v.round().clamp(1, 60000),
                        ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Text('ms', style: _label),
                const Spacer(),
                _Icon(
                  icon: Icons.arrow_upward,
                  tooltip: 'Earlier',
                  onTap: i == 0
                      ? null
                      : () {
                          final next = [...frames];
                          final f = next.removeAt(i);
                          next.insert(i - 1, f);
                          write(next);
                        },
                ),
                _Icon(
                  icon: Icons.close,
                  tooltip: 'Remove the frame',
                  onTap: () => write([...frames]..removeAt(i)),
                ),
              ],
            ),
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: () {
                final last = frames.isEmpty ? null : frames.last;
                final nextTile = last == null
                    ? id
                    : (last.tileId + 1).clamp(0, ts.tileCount - 1);
                write([
                  ...frames,
                  TileFrame(nextTile, last?.durationMs ?? 120),
                ]);
              },
              child: const Text('Add frame', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: many ? () => session.animateSelection() : null,
              child: const Text(
                'Animate selection',
                style: TextStyle(fontSize: 11),
              ),
            ),
            if (frames.isNotEmpty)
              TextButton(
                onPressed: () => write(const []),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        if (frames.length == 1)
          Text(
            'One frame shows as a still tile: add another to animate.',
            style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
          ),
      ],
    );
  }
}

TextStyle get _label => TextStyle(
  fontSize: 11,
  color: EditorTheme.textSecondary,
);

class _Icon extends StatelessWidget {
  const _Icon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          icon,
          size: 13,
          color: onTap == null
              ? EditorTheme.textMuted
              : EditorTheme.textSecondary,
        ),
      ),
    ),
  );
}

/// A small picture of one tile.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.source});

  final ui.Image? image;
  final Rect? source;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: EditorTheme.surfaceDark,
      border: Border.all(color: EditorTheme.border),
    ),
    child: image == null || source == null
        ? null
        : CustomPaint(painter: _TilePainter(image!, source!)),
  );
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.image, this.source);

  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.none,
  );

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.image != image || old.source != source;
}

/// The animation, playing.
class _Preview extends StatefulWidget {
  const _Preview({
    super.key,
    required this.image,
    required this.tileset,
    required this.def,
    required this.tileId,
  });

  final ui.Image? image;
  final TilesetData tileset;
  final TileDef def;
  final int tileId;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.def.frameAt(widget.tileId, _clock.elapsedMilliseconds);
    final ts = widget.tileset;
    final scale =
        64 / (ts.tileWidth > ts.tileHeight ? ts.tileWidth : ts.tileHeight);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      width: ts.tileWidth * scale,
      height: ts.tileHeight * scale,
      decoration: BoxDecoration(border: Border.all(color: EditorTheme.border)),
      child: widget.image == null || !ts.contains(shown)
          ? null
          : CustomPaint(
              painter: _TilePainter(widget.image!, ts.sourceRect(shown)),
            ),
    );
  }
}
