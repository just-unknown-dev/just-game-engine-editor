part of 'editor_overlay.dart';

// ── Mode ───────────────────────────────────────────────────────────────────────

enum _TimelineMode { sprite, entity }

// ── Transform track (entity timeline only) ────────────────────────────────────

enum _TLTrack { posX, posY, rotation, scaleX, scaleY }

extension on _TLTrack {
  String get label => switch (this) {
    _TLTrack.posX => 'Pos X',
    _TLTrack.posY => 'Pos Y',
    _TLTrack.rotation => 'Rotation',
    _TLTrack.scaleX => 'Scale X',
    _TLTrack.scaleY => 'Scale Y',
  };

  Color get accent => switch (this) {
    _TLTrack.posX => const Color(0xFF7DE6B1),
    _TLTrack.posY => const Color(0xFF7DD8E0),
    _TLTrack.rotation => const Color(0xFFFFC86B),
    _TLTrack.scaleX => const Color(0xFFD9A7FF),
    _TLTrack.scaleY => const Color(0xFFF5746F),
  };
}

// ── Selection typedefs ────────────────────────────────────────────────────────

typedef _KfSel = ({_TLTrack track, int index});
typedef _EvSel = ({int index});

// ── Timeline panel ────────────────────────────────────────────────────────────

class _DockTimelinePanel extends StatefulWidget {
  const _DockTimelinePanel({
    required this.height,
    required this.onResize,
    required this.onClose,
    required this.settings,
    required this.plugin,
  });

  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
  final _OverlayUiSettings settings;
  final JustGameEditorPlugin plugin;

  @override
  State<_DockTimelinePanel> createState() => _DockTimelinePanelState();
}

class _DockTimelinePanelState extends State<_DockTimelinePanel>
    with SingleTickerProviderStateMixin {
  static const double _labelW = 68.0;
  static const double _rulerH = 22.0;
  static const double _frameTrackH = 36.0;
  static const double _trackH = 26.0;
  static const double _eventTrackH = 26.0;
  static const double _pxPerSecDefault = 120.0;

  final ScrollController _hscroll = ScrollController();
  double _scrollOffset = 0.0;
  double _pxPerSec = _pxPerSecDefault;
  _KfSel? _selectedKf;
  _EvSel? _selectedEv;
  _TimelineMode _mode = _TimelineMode.sprite;
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _hscroll.addListener(() {
      if (mounted) setState(() => _scrollOffset = _hscroll.offset);
    });
    _ticker = createTicker((_) {
      final playing = _mode == _TimelineMode.sprite
          ? (_asc?.isPlaying ?? false)
          : (_acc?.isPlaying ?? false);
      if (playing && mounted) setState(() {});
    });
    _ticker.start();
    widget.plugin.sceneState.addListener(_onSceneChanged);
  }

  @override
  void dispose() {
    _hscroll.dispose();
    _ticker.dispose();
    widget.plugin.sceneState.removeListener(_onSceneChanged);
    super.dispose();
  }

  void _onSceneChanged() {
    if (!mounted) return;
    final hasSprite = _asc != null;
    final hasEntity = _acc != null;
    final nextMode = (!hasSprite && hasEntity)
        ? _TimelineMode.entity
        : _TimelineMode.sprite;
    setState(() {
      _selectedKf = null;
      _selectedEv = null;
      if (!_hasBoth) _mode = nextMode;
    });
  }

  // ── Active components ────────────────────────────────────────────────────

  dynamic get _entity => widget.plugin.sceneState.selectedEntity;

  AnimatedSpriteComponent? get _asc {
    final e = _entity;
    if (e == null) return null;
    try {
      return (e as dynamic).getComponent<AnimatedSpriteComponent>();
    } catch (_) {
      return null;
    }
  }

  AnimationControllerComponent? get _acc {
    final e = _entity;
    if (e == null) return null;
    try {
      return (e as dynamic).getComponent<AnimationControllerComponent>();
    } catch (_) {
      return null;
    }
  }

  bool get _hasBoth => _asc != null && _acc != null;

  bool get _hasAny => _asc != null || _acc != null;

  // ── Sprite sheet image for thumbnails ───────────────────────────────────

  ui.Image? get _spriteImage {
    try {
      final e = _entity as dynamic;
      final rc = e.getComponent<RenderableComponent>();
      final renderable = rc?.renderable;
      if (renderable is Sprite) return renderable.image;
    } catch (_) {}
    return null;
  }

  // ── Layout helpers ───────────────────────────────────────────────────────

  double get _contentH => _mode == _TimelineMode.sprite
      ? _rulerH + _frameTrackH + _eventTrackH
      : _rulerH + _TLTrack.values.length * _trackH + _eventTrackH;

  double get _eventsRowTop => _mode == _TimelineMode.sprite
      ? _rulerH + _frameTrackH
      : _rulerH + _TLTrack.values.length * _trackH;

  double get _elapsed => _mode == _TimelineMode.sprite
      ? (_asc?.elapsed ?? 0.0)
      : (_acc?.elapsed ?? 0.0);

  double get _duration => _mode == _TimelineMode.sprite
      ? (_asc?.clipDuration ?? 0.0)
      : (_acc?.duration ?? 1.0);

  double _trackTop(_TLTrack track) =>
      _rulerH + _TLTrack.values.indexOf(track) * _trackH;

  double _timeToX(double t) => t * _pxPerSec;
  double _xToTime(double x) => (x + _scrollOffset) / _pxPerSec;

  double _contentWidth() =>
      (_timeToX(_duration + 2.0)).clamp(400.0, 4000.0);

  // ── Event helpers ────────────────────────────────────────────────────────

  List<AnimationEvent> get _events {
    if (_mode == _TimelineMode.sprite) {
      return _asc?.activeClipData?.events ?? const [];
    }
    return _acc?.events ?? const [];
  }

  // ── Keyframe helpers (entity mode) ───────────────────────────────────────

  List<int> _kfIndicesForTrack(_TLTrack track) {
    final acc = _acc;
    if (acc == null) return [];
    return [
      for (int i = 0; i < acc.keyframes.length; i++)
        if (_hasValue(acc.keyframes[i], track)) i,
    ];
  }

  bool _hasValue(TransformKeyframe kf, _TLTrack track) => switch (track) {
    _TLTrack.posX => kf.posX != null,
    _TLTrack.posY => kf.posY != null,
    _TLTrack.rotation => kf.rotation != null,
    _TLTrack.scaleX => kf.scaleX != null,
    _TLTrack.scaleY => kf.scaleY != null,
  };

  double _currentTransformValue(_TLTrack track) {
    final e = _entity;
    if (e == null) return 0.0;
    try {
      final t = (e as dynamic).getComponent<TransformComponent>();
      if (t == null) return 0.0;
      return switch (track) {
        _TLTrack.posX => (t.position.x as double),
        _TLTrack.posY => (t.position.y as double),
        _TLTrack.rotation => (t.rotation as double),
        _TLTrack.scaleX => (t.scale.x as double),
        _TLTrack.scaleY => (t.scale.y as double),
      };
    } catch (_) {
      return 0.0;
    }
  }

  // ── Playback controls ────────────────────────────────────────────────────

  void _play() {
    if (_mode == _TimelineMode.sprite) {
      _asc?.isPlaying = true;
    } else {
      _acc?.isPlaying = true;
    }
    setState(() {});
  }

  void _pause() {
    if (_mode == _TimelineMode.sprite) {
      _asc?.isPlaying = false;
    } else {
      _acc?.isPlaying = false;
    }
    setState(() {});
  }

  void _stop() {
    if (_mode == _TimelineMode.sprite) {
      _asc?.stop();
    } else {
      _acc?.stop();
    }
    setState(() {});
  }

  void _toggleLoop() {
    if (_mode == _TimelineMode.sprite) {
      final asc = _asc;
      if (asc != null) asc.loop = !asc.loop;
    } else {
      final acc = _acc;
      if (acc != null) acc.loop = !acc.loop;
    }
    setState(() {});
  }

  void _scrubTo(double time) {
    if (_mode == _TimelineMode.sprite) {
      final asc = _asc;
      if (asc == null) return;
      final clip = asc.activeClipData;
      final dur = clip != null && clip.frames.isNotEmpty
          ? clip.frames.length / (clip.fps ?? asc.defaultFps)
          : 0.0;
      asc.elapsed = time.clamp(0.0, dur > 0 ? dur : double.infinity);
      if (clip != null && clip.frames.isNotEmpty) {
        final fps = clip.fps ?? asc.defaultFps;
        asc.frameIndex = (asc.elapsed * fps)
            .floor()
            .clamp(0, clip.frames.length - 1);
      }
    } else {
      final acc = _acc;
      if (acc == null) return;
      acc.elapsed = time.clamp(0.0, acc.duration);
    }
    setState(() {});
  }

  void _switchClip(String name) {
    final asc = _asc;
    if (asc == null) return;
    asc.switchClip(name, blend: false);
    setState(() {});
  }

  // ── Keyframe add / move / delete (entity mode) ───────────────────────────

  void _addKeyframeAt(double time, _TLTrack track) {
    final acc = _acc;
    if (acc == null) return;
    final val = _currentTransformValue(track);
    final kf = TransformKeyframe(
      time: time,
      posX: track == _TLTrack.posX ? val : null,
      posY: track == _TLTrack.posY ? val : null,
      rotation: track == _TLTrack.rotation ? val : null,
      scaleX: track == _TLTrack.scaleX ? val : null,
      scaleY: track == _TLTrack.scaleY ? val : null,
    );
    acc.addOrUpdateKeyframe(kf);
    setState(() => _selectedKf = null);
  }

  void _deleteSelectedKf() {
    final sel = _selectedKf;
    final acc = _acc;
    if (sel == null || acc == null) return;

    final indices = _kfIndicesForTrack(sel.track);
    if (sel.index >= indices.length) return;
    final realIdx = indices[sel.index];

    final kf = acc.keyframes[realIdx];
    final updated = TransformKeyframe(
      time: kf.time,
      posX: sel.track == _TLTrack.posX ? null : kf.posX,
      posY: sel.track == _TLTrack.posY ? null : kf.posY,
      rotation: sel.track == _TLTrack.rotation ? null : kf.rotation,
      scaleX: sel.track == _TLTrack.scaleX ? null : kf.scaleX,
      scaleY: sel.track == _TLTrack.scaleY ? null : kf.scaleY,
      easing: kf.easing,
    );

    final hasAny = updated.posX != null ||
        updated.posY != null ||
        updated.rotation != null ||
        updated.scaleX != null ||
        updated.scaleY != null;
    if (hasAny) {
      acc.keyframes[realIdx] = updated;
    } else {
      acc.removeKeyframe(realIdx);
    }
    setState(() => _selectedKf = null);
  }

  void _moveKf(_KfSel sel, double dx) {
    final acc = _acc;
    if (acc == null) return;

    final indices = _kfIndicesForTrack(sel.track);
    if (sel.index >= indices.length) return;
    final realIdx = indices[sel.index];

    final dt = dx / _pxPerSec;
    final newTime =
        (acc.keyframes[realIdx].time + dt).clamp(0.0, double.infinity);
    acc.moveKeyframe(realIdx, newTime);

    final newIndices = _kfIndicesForTrack(sel.track);
    final newRealIdx = acc.keyframes.indexWhere(
      (k) => (k.time - newTime).abs() < 0.001,
    );
    final newSelIdx = newIndices.indexOf(newRealIdx);
    setState(() =>
        _selectedKf = (track: sel.track, index: newSelIdx < 0 ? sel.index : newSelIdx));
  }

  // ── Event add / move / delete ────────────────────────────────────────────

  Future<void> _addEventPrompt(double time) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Add Event',
          style: TextStyle(
            color: EditorTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
          cursorColor: EditorTheme.primaryMuted,
          decoration: InputDecoration(
            hintText: 'event_name',
            hintStyle: const TextStyle(color: EditorTheme.textMuted, fontSize: 12),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: EditorTheme.textMuted),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: EditorTheme.primaryMuted),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              'Add',
              style: TextStyle(color: EditorTheme.primaryMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    _addEventAt(time, name.trim());
  }

  void _addEventAt(double time, String name) {
    final ev = AnimationEvent(time: time, name: name);
    if (_mode == _TimelineMode.sprite) {
      _asc?.activeClipData?.addEvent(ev);
    } else {
      _acc?.addEvent(ev);
    }
    setState(() => _selectedEv = null);
  }

  void _deleteSelectedEv() {
    final sel = _selectedEv;
    if (sel == null) return;
    if (_mode == _TimelineMode.sprite) {
      _asc?.activeClipData?.removeEvent(sel.index);
    } else {
      _acc?.removeEvent(sel.index);
    }
    setState(() => _selectedEv = null);
  }

  void _moveEv(_EvSel sel, double dx) {
    final events = _events;
    if (sel.index >= events.length) return;
    final dt = dx / _pxPerSec;
    final newTime = (events[sel.index].time + dt).clamp(0.0, _duration);
    if (_mode == _TimelineMode.sprite) {
      _asc?.activeClipData?.moveEvent(sel.index, newTime);
    } else {
      _acc?.moveEvent(sel.index, newTime);
    }
    setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF41B1B1B),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              _PanelResizeHandle(onDrag: widget.onResize),
              _buildHeader(),
              if (_hasBoth) _buildModeTabStrip(),
              if (_hasAny)
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              if (_hasAny) _buildTransport(),
              if (_hasAny)
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              Expanded(
                child: !_hasAny ? _buildEmpty() : _buildDopeSheet(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final entityName = _entity != null
        ? 'Entity #${(_entity as dynamic).id}'
        : 'No selection';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF7DE6B1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.movie_filter_rounded,
              size: 11,
              color: Color(0xFF7DE6B1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Timeline',
            style: TextStyle(
              fontSize: 11 * widget.settings.effectiveTextScale,
              fontWeight: FontWeight.w600,
              color: EditorTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entityName,
            style: const TextStyle(fontSize: 10, color: EditorTheme.textMuted),
          ),
          const Spacer(),
          if (_mode == _TimelineMode.sprite && _asc != null && _asc!.clips.isNotEmpty)
            _buildClipDropdown(_asc!),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
            color: EditorTheme.textSecondary,
            iconSize: 14,
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabStrip() {
    return Container(
      height: 28,
      color: const Color(0xFF141414),
      child: Row(
        children: [
          _buildModeTab(_TimelineMode.sprite, Icons.movie_filter_rounded, 'Sprite'),
          _buildModeTab(_TimelineMode.entity, Icons.timeline_rounded, 'Entity'),
        ],
      ),
    );
  }

  Widget _buildModeTab(_TimelineMode mode, IconData icon, String label) {
    final isActive = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = mode;
        _selectedKf = null;
        _selectedEv = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? EditorTheme.primaryMuted : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isActive ? EditorTheme.primaryMuted : EditorTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? EditorTheme.textPrimary : EditorTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipDropdown(AnimatedSpriteComponent asc) {
    return DropdownButton<String>(
      value: asc.clips.containsKey(asc.activeClip) ? asc.activeClip : null,
      hint: const Text('clip', style: TextStyle(fontSize: 10, color: EditorTheme.textMuted)),
      style: const TextStyle(fontSize: 10, color: EditorTheme.textPrimary),
      dropdownColor: const Color(0xFF1E1E1E),
      underline: const SizedBox.shrink(),
      isDense: true,
      items: asc.clips.keys
          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
          .toList(),
      onChanged: (v) { if (v != null) _switchClip(v); },
    );
  }

  Widget _buildTransport() {
    final isPlaying = _mode == _TimelineMode.sprite
        ? (_asc?.isPlaying ?? false)
        : (_acc?.isPlaying ?? false);
    final loop = _mode == _TimelineMode.sprite
        ? (_asc?.loop ?? false)
        : (_acc?.loop ?? false);
    final fps = _mode == _TimelineMode.sprite
        ? (_asc?.activeClipData?.fps ?? _asc?.defaultFps ?? 12.0)
        : null;

    final bool hasKfSel = _mode == _TimelineMode.entity && _selectedKf != null;
    final bool hasEvSel = _selectedEv != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: <Widget>[
          _TLIconBtn(
            icon: Icons.skip_previous_rounded,
            onTap: () => _scrubTo(0),
            tooltip: 'Rewind',
          ),
          _TLIconBtn(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            accent: const Color(0xFF7DE6B1),
            onTap: isPlaying ? _pause : _play,
            tooltip: isPlaying ? 'Pause' : 'Play',
          ),
          _TLIconBtn(
            icon: Icons.stop_rounded,
            onTap: _stop,
            tooltip: 'Stop',
          ),
          _TLIconBtn(
            icon: Icons.repeat_rounded,
            accent: loop ? const Color(0xFF7DE6B1) : null,
            onTap: _toggleLoop,
            tooltip: 'Loop',
          ),
          const SizedBox(width: 6),
          if (fps != null)
            Text(
              '${fps.toStringAsFixed(1)} fps',
              style: const TextStyle(fontSize: 10, color: EditorTheme.textMuted),
            )
          else
            Text(
              '${_duration.toStringAsFixed(2)} s',
              style: const TextStyle(fontSize: 10, color: EditorTheme.textMuted),
            ),
          const Spacer(),
          _TLIconBtn(
            icon: Icons.zoom_out_rounded,
            onTap: () => setState(() => _pxPerSec = (_pxPerSec / 1.5).clamp(30.0, 600.0)),
            tooltip: 'Zoom out',
          ),
          _TLIconBtn(
            icon: Icons.zoom_in_rounded,
            onTap: () => setState(() => _pxPerSec = (_pxPerSec * 1.5).clamp(30.0, 600.0)),
            tooltip: 'Zoom in',
          ),
          if (hasKfSel) ...[
            const SizedBox(width: 4),
            _TLIconBtn(
              icon: Icons.delete_outline_rounded,
              accent: EditorTheme.error,
              onTap: _deleteSelectedKf,
              tooltip: 'Delete keyframe',
            ),
          ],
          if (hasEvSel) ...[
            const SizedBox(width: 4),
            _TLIconBtn(
              icon: Icons.event_busy_rounded,
              accent: EditorTheme.error,
              onTap: _deleteSelectedEv,
              tooltip: 'Delete event',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'Select an entity with AnimatedSpriteComponent or AnimationControllerComponent',
        style: TextStyle(fontSize: 11, color: EditorTheme.textMuted),
      ),
    );
  }

  Widget _buildDopeSheet() {
    final contentW = _contentWidth();
    final playheadX = _timeToX(_elapsed) - _scrollOffset;

    return Row(
      children: <Widget>[
        SizedBox(width: _labelW, child: _buildLabelColumn()),
        Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  SingleChildScrollView(
                    controller: _hscroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentW,
                      height: _contentH,
                      child: Stack(
                        children: <Widget>[
                          CustomPaint(
                            size: Size(contentW, _contentH),
                            painter: _TimelineGridPainter(
                              mode: _mode,
                              duration: _duration,
                              pxPerSec: _pxPerSec,
                              asc: _mode == _TimelineMode.sprite ? _asc : null,
                              spriteImage: _mode == _TimelineMode.sprite
                                  ? _spriteImage
                                  : null,
                              eventsRowTop: _eventsRowTop,
                              eventTrackH: _eventTrackH,
                              trackH: _trackH,
                              rulerH: _rulerH,
                              frameTrackH: _frameTrackH,
                              currentFrameIndex: _mode == _TimelineMode.sprite
                                  ? (_asc?.frameIndex ?? -1)
                                  : -1,
                            ),
                          ),
                          // Gesture detector placed BELOW diamonds so that
                          // diamond GestureDetectors (rendered on top) absorb
                          // their own taps/drags and win the gesture arena.
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onDoubleTapDown: (d) {
                                final y = d.localPosition.dy;
                                final time = d.localPosition.dx / _pxPerSec;

                                // Events track
                                if (y >= _eventsRowTop &&
                                    y < _eventsRowTop + _eventTrackH) {
                                  _addEventPrompt(time);
                                  return;
                                }

                                // Transform tracks (entity mode)
                                if (_mode == _TimelineMode.entity) {
                                  for (final track in _TLTrack.values) {
                                    final top = _trackTop(track);
                                    if (y >= top && y < top + _trackH) {
                                      _addKeyframeAt(time, track);
                                      break;
                                    }
                                  }
                                }
                              },
                              onTapDown: (d) {
                                if (d.localPosition.dy < _rulerH) {
                                  _scrubTo(d.localPosition.dx / _pxPerSec);
                                }
                              },
                              onHorizontalDragUpdate: (d) {
                                // In entity mode only allow scrubbing in the
                                // ruler; track-area drags belong to the
                                // keyframe diamonds above this widget.
                                final maxY = _mode == _TimelineMode.sprite
                                    ? _rulerH + _frameTrackH
                                    : _rulerH;
                                if (d.localPosition.dy < maxY) {
                                  _scrubTo(_xToTime(d.localPosition.dx));
                                }
                              },
                            ),
                          ),
                          // Transform keyframe diamonds (entity mode only)
                          // Rendered above the gesture detector so they absorb
                          // their own tap/drag events.
                          if (_mode == _TimelineMode.entity && _acc != null)
                            for (final track in _TLTrack.values)
                              ..._buildKfWidgets(track),
                          // Event diamonds (both modes)
                          ..._buildEvWidgets(),
                        ],
                      ),
                    ),
                  ),
                  // Playhead
                  if (playheadX >= 0 && playheadX <= constraints.maxWidth)
                    Positioned(
                      left: playheadX,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) =>
                            _scrubTo(_xToTime(playheadX + d.delta.dx)),
                        child: Container(
                          width: 2,
                          color: const Color(0xFFF5746F),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF5746F),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLabelColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: _rulerH,
          child: const Center(
            child: Text(
              's',
              style: TextStyle(fontSize: 9, color: EditorTheme.textMuted),
            ),
          ),
        ),
        if (_mode == _TimelineMode.sprite)
          _TrackLabel(label: 'Frames', height: _frameTrackH, color: EditorTheme.textMuted),
        if (_mode == _TimelineMode.entity)
          for (final track in _TLTrack.values)
            _TrackLabel(label: track.label, height: _trackH, color: track.accent),
        _TrackLabel(
          label: 'Events',
          height: _eventTrackH,
          color: const Color(0xFFFFD580),
        ),
      ],
    );
  }

  // ── Keyframe diamond widgets (entity mode) ───────────────────────────────

  List<Widget> _buildKfWidgets(_TLTrack track) {
    final acc = _acc;
    if (acc == null) return [];
    final indices = _kfIndicesForTrack(track);
    final top = _trackTop(track);
    final centerY = top + _trackH / 2;

    return [
      for (int i = 0; i < indices.length; i++)
        () {
          final kf = acc.keyframes[indices[i]];
          final x = _timeToX(kf.time);
          final isSel = _selectedKf?.track == track && _selectedKf?.index == i;
          return Positioned(
            left: x - 6,
            top: centerY - 6,
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedEv = null;
                _selectedKf = isSel ? null : (track: track, index: i);
              }),
              onHorizontalDragUpdate: (d) {
                final sel = (track: track, index: i);
                setState(() { _selectedKf = sel; _selectedEv = null; });
                _moveKf(sel, d.delta.dx);
              },
              child: _KfDiamond(color: isSel ? Colors.white : track.accent, size: 12),
            ),
          );
        }(),
    ];
  }

  // ── Event diamond widgets (both modes) ───────────────────────────────────

  List<Widget> _buildEvWidgets() {
    final events = _events;
    final centerY = _eventsRowTop + _eventTrackH / 2;

    return [
      for (int i = 0; i < events.length; i++)
        () {
          final ev = events[i];
          final x = _timeToX(ev.time);
          final isSel = _selectedEv?.index == i;
          return Positioned(
            left: x - 6,
            top: centerY - 6,
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedKf = null;
                _selectedEv = isSel ? null : (index: i);
              }),
              onHorizontalDragUpdate: (d) {
                setState(() { _selectedEv = (index: i); _selectedKf = null; });
                _moveEv((index: i), d.delta.dx);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _KfDiamond(
                    color: isSel ? Colors.white : const Color(0xFFFFD580),
                    size: 12,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    ev.name,
                    style: TextStyle(
                      fontSize: 8,
                      color: isSel
                          ? Colors.white
                          : const Color(0xFFFFD580).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        }(),
    ];
  }
}

// ── Grid painter (mode-aware) ─────────────────────────────────────────────────

class _TimelineGridPainter extends CustomPainter {
  const _TimelineGridPainter({
    required this.mode,
    required this.duration,
    required this.pxPerSec,
    required this.eventsRowTop,
    required this.eventTrackH,
    required this.trackH,
    required this.rulerH,
    required this.frameTrackH,
    this.asc,
    this.spriteImage,
    this.currentFrameIndex = -1,
  });

  final _TimelineMode mode;
  final double duration;
  final double pxPerSec;
  final double eventsRowTop;
  final double eventTrackH;
  final double trackH;
  final double rulerH;
  final double frameTrackH;
  final AnimatedSpriteComponent? asc;
  final ui.Image? spriteImage;
  // Passed as an immutable snapshot so shouldRepaint can detect frame changes.
  final int currentFrameIndex;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawRuler(canvas, size);
    if (mode == _TimelineMode.sprite) {
      _drawFrameTrack(canvas, size);
    }
    _drawEventsRow(canvas, size);
    _drawDividers(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    if (mode == _TimelineMode.entity) {
      for (int i = 0; i < _TLTrack.values.length; i++) {
        if (i % 2 == 1) {
          final y = rulerH + i * trackH;
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, trackH),
            Paint()..color = const Color(0xFF181818),
          );
        }
      }
    }
    // Subtle events row background
    canvas.drawRect(
      Rect.fromLTWH(0, eventsRowTop, size.width, eventTrackH),
      Paint()..color = const Color(0xFF1C1A10),
    );
  }

  void _drawRuler(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, rulerH),
      Paint()..color = const Color(0xFF202020),
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    final double interval;
    if (pxPerSec >= 200) {
      interval = 0.1;
    } else if (pxPerSec >= 60) {
      interval = 0.5;
    } else if (pxPerSec >= 20) {
      interval = 1.0;
    } else {
      interval = 5.0;
    }

    final totalSec = size.width / pxPerSec;
    for (double t = 0; t <= totalSec + interval; t += interval) {
      final x = t * pxPerSec;
      final isMajor = (t % 1.0) < 0.001 || (t % 1.0) > 0.999;
      canvas.drawLine(
        Offset(x, isMajor ? 0 : rulerH * 0.5),
        Offset(x, rulerH),
        isMajor ? majorPaint : linePaint,
      );
      if (isMajor) {
        _drawText(
          canvas,
          '${t.toStringAsFixed(t < 1 ? 1 : 0)}s',
          Offset(x + 2, 2),
          const Color(0xFFAAAAAA),
          8,
        );
      }
    }

    // Frame ticks (sprite mode only)
    if (mode == _TimelineMode.sprite && asc != null) {
      final clip = asc!.activeClipData;
      if (clip != null && clip.frames.isNotEmpty) {
        final fps = clip.fps ?? asc!.defaultFps;
        final frameDur = 1.0 / fps;
        final tickPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        for (int f = 0; f < clip.frames.length; f++) {
          final x = f * frameDur * pxPerSec;
          canvas.drawLine(
            Offset(x, rulerH - 5),
            Offset(x, rulerH),
            tickPaint,
          );
        }
      }
    }
  }

  void _drawFrameTrack(Canvas canvas, Size size) {
    final clip = asc?.activeClipData;
    if (clip == null || clip.frames.isEmpty) {
      canvas.drawRect(
        Rect.fromLTWH(0, rulerH, size.width, frameTrackH),
        Paint()..color = const Color(0xFF1A1A1A),
      );
      return;
    }

    final fps = clip.fps ?? asc!.defaultFps;
    final frameDur = 1.0 / fps;
    final currentFrame = currentFrameIndex.clamp(0, clip.frames.length - 1);
    final image = spriteImage;
    final fw = asc!.frameWidth.toDouble();
    final fh = asc!.frameHeight.toDouble();
    // columns may be 0 if the component was built without explicit config;
    // fall back to computing it from the image width.
    final cols = asc!.columns > 0
        ? asc!.columns
        : (image != null && fw > 0 ? (image.width / fw).floor() : 0);

    for (int f = 0; f < clip.frames.length; f++) {
      final x = f * frameDur * pxPerSec;
      final w = frameDur * pxPerSec;
      final isActive = f == currentFrame;

      final cellRect = Rect.fromLTWH(x + 1, rulerH + 2, w - 2, frameTrackH - 4);

      canvas.drawRect(
        cellRect,
        Paint()
          ..color = isActive
              ? const Color(0xFF7DE6B1).withValues(alpha: 0.25)
              : const Color(0xFF7DE6B1).withValues(alpha: 0.07),
      );

      // Draw sprite thumbnail if image is available and cell is wide enough
      if (image != null && w >= 12 && fw > 0 && fh > 0) {
        final absFrame = clip.frames[f];
        final col = cols > 0 ? absFrame % cols : 0;
        final row = cols > 0 ? absFrame ~/ cols : 0;
        final srcRect = Rect.fromLTWH(col * fw, row * fh, fw, fh);

        // Fit thumbnail inside cell with padding
        final padding = 2.0;
        final availW = cellRect.width - padding * 2;
        final availH = cellRect.height - padding * 2;
        final scale = math.min(availW / fw, availH / fh);
        final dw = fw * scale;
        final dh = fh * scale;
        final dx = cellRect.left + padding + (availW - dw) / 2;
        final dy = cellRect.top + padding + (availH - dh) / 2;
        final dstRect = Rect.fromLTWH(dx, dy, dw, dh);

        canvas.drawImageRect(image, srcRect, dstRect, Paint());
      } else if (w > 8) {
        _drawText(
          canvas,
          '${f + 1}',
          Offset(x + 2, rulerH + 4),
          isActive
              ? const Color(0xFF7DE6B1)
              : Colors.white.withValues(alpha: 0.3),
          7,
        );
      }

      // Active frame border
      if (isActive) {
        canvas.drawRect(
          cellRect,
          Paint()
            ..color = const Color(0xFF7DE6B1).withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  void _drawEventsRow(Canvas canvas, Size size) {
    // Subtle dashed-style border at top of events row
    final borderPaint = Paint()
      ..color = const Color(0xFFFFD580).withValues(alpha: 0.15)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, eventsRowTop),
      Offset(size.width, eventsRowTop),
      borderPaint,
    );
  }

  void _drawDividers(Canvas canvas, Size size) {
    final divPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, rulerH), Offset(size.width, rulerH), divPaint);

    if (mode == _TimelineMode.sprite) {
      canvas.drawLine(
        Offset(0, rulerH + frameTrackH),
        Offset(size.width, rulerH + frameTrackH),
        divPaint,
      );
    } else {
      for (int i = 1; i < _TLTrack.values.length; i++) {
        final y = rulerH + i * trackH;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), divPaint);
      }
      canvas.drawLine(
        Offset(0, eventsRowTop),
        Offset(size.width, eventsRowTop),
        divPaint,
      );
    }

    // Vertical grid lines every second
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    final totalSec = size.width / pxPerSec;
    for (double t = 1; t <= totalSec; t += 1) {
      final x = t * pxPerSec;
      canvas.drawLine(Offset(x, rulerH), Offset(x, size.height), gridPaint);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_TimelineGridPainter old) =>
      old.mode != mode ||
      old.duration != duration ||
      old.pxPerSec != pxPerSec ||
      old.asc != asc ||
      old.spriteImage != spriteImage ||
      old.currentFrameIndex != currentFrameIndex;
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _TrackLabel extends StatelessWidget {
  const _TrackLabel({
    required this.label,
    required this.height,
    required this.color,
  });

  final String label;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _KfDiamond extends StatelessWidget {
  const _KfDiamond({required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DiamondPainter(color: color)),
    );
  }
}

class _DiamondPainter extends CustomPainter {
  const _DiamondPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(size.width, cy)
      ..lineTo(cx, size.height)
      ..lineTo(0, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DiamondPainter old) => old.color != color;
}

class _TLIconBtn extends StatelessWidget {
  const _TLIconBtn({
    required this.icon,
    required this.onTap,
    this.accent,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: accent ?? EditorTheme.textSecondary),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}
