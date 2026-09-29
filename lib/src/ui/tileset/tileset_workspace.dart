import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import '../kit/kit.dart';
import '../inspector/field_rows.dart';
import '../timeline/timeline_dialogs.dart';
import 'collision_shape_editor.dart';
import 'create_tileset_dialog.dart';
import 'tile_animation_editor.dart';
import 'tile_properties_editor.dart';
import 'tileset_session.dart';
import 'wang_set_editor.dart';

/// The Tileset Editor: a `.tileset.json` — or a new one cut from an image —
/// with each tile's collision, animation and properties.
///
/// Its undo is its own, and the level sees the tileset as last saved:
/// saving tells every map drawing it to read it again.
class TilesetEditor extends StatefulWidget {
  const TilesetEditor({
    super.key,
    required this.root,
    this.path,
    this.newTilesetFolder = 'assets/tilesets',
    this.onClose,
    this.onSaved,
    this.fullScreen,
    this.onToggleFullScreen,
    this.setCloseGuard,
    this.loadImage,
    this.readText,
    this.writeText,
  });

  /// The project folder paths are relative to.
  final String root;

  /// A `.tileset.json` to open, or a `.png` to cut a new tileset from; null
  /// to choose an image.
  final String? path;

  /// Where a new tileset is saved.
  final String newTilesetFolder;

  final VoidCallback? onClose;

  /// A tileset was written to the path given.
  final ValueChanged<String>? onSaved;

  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  /// Where to leave the question to ask before the editor opens something
  /// else over this; see [WorkspaceContext.setCloseGuard].
  final void Function(Future<bool> Function()? guard)? setCloseGuard;

  // Seams for tests.
  final TilesetImageLoader? loadImage;
  final TilesetTextReader? readText;
  final TilesetTextWriter? writeText;

  @override
  State<TilesetEditor> createState() => TilesetEditorState();
}

class TilesetEditorState extends State<TilesetEditor> {
  TilesetSession? _session;
  String? _error;
  bool _creating = false;
  VoidCallback? _stopMessages;
  String? _toast;
  Timer? _toastTimer;

  double _zoom = 2;
  bool _showCollision = true;

  /// A drag-select in progress: where it started, in columns and rows.
  (int, int)? _dragFrom;

  /// Where Shift+click selects from.
  int? _anchor;

  /// Painting terrains onto tiles' corners and edges, rather than picking
  /// tiles.
  bool _terrainMode = false;
  int? _wangSet;
  int _wangColor = 1;
  int _wangStroke = 0;

  TilesetSession? get session => _session;

  @override
  void initState() {
    super.initState();
    widget.setCloseGuard?.call(_mayLeave);
    final path = widget.path;
    if (path == null || !path.toLowerCase().endsWith('.tileset.json')) {
      _creating = true;
    } else {
      _open(path);
    }
  }

  Future<void> _open(String path) async {
    try {
      final s = await TilesetSession.open(
        path,
        root: widget.root,
        readText: widget.readText,
        loadImage: widget.loadImage,
        writeText: widget.writeText,
      );
      if (!mounted) return s.dispose();
      _adopt(s);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open $path: $e');
    }
  }

  Future<void> _create(TilesetCut cut) async {
    try {
      final s = await TilesetSession.create(
        image: cut.image,
        name: cut.name,
        tileWidth: cut.tileWidth,
        tileHeight: cut.tileHeight,
        margin: cut.margin,
        spacing: cut.spacing,
        root: widget.root,
        loadImage: widget.loadImage,
        writeText: widget.writeText,
      );
      if (!mounted) return s.dispose();
      setState(() => _creating = false);
      _adopt(s);
      s.say('Cut into ${s.data.tileCount} tiles: select some to edit them');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the tileset: $e');
    }
  }

  void _adopt(TilesetSession s) {
    _stopMessages = s.message.watch(() => _showToast(s.message.value));
    final tile = s.data.tileWidth;
    setState(() {
      _session = s;
      _zoom = tile <= 16 ? 3 : (tile <= 32 ? 2 : 1);
    });
  }

  void _showToast(String? text) {
    if (!mounted || text == null) return;
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    widget.setCloseGuard?.call(null);
    _toastTimer?.cancel();
    _stopMessages?.call();
    _session?.dispose();
    super.dispose();
  }

  /// Saves, asking for a name the first time. Returns whether it saved.
  Future<bool> save() async {
    final s = _session;
    if (s == null) return false;
    var target = s.path;
    if (target == null) {
      final name = await promptTimelineText(
        context,
        title: 'Name this tileset',
        initial: s.data.name,
        hint: 'grassland',
      );
      if (name == null || name.isEmpty) return false;
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
      target = '${widget.newTilesetFolder}/$safe.tileset.json';
      if (widget.writeText == null &&
          File('${widget.root}/$target').existsSync()) {
        s.say('$target already exists: choose another name');
        return false;
      }
    }
    try {
      final saved = await s.save(to: target);
      widget.onSaved?.call(saved);
      return true;
    } catch (e) {
      s.say('Could not save: $e');
      return false;
    }
  }

  /// Whether it is fine to go: nothing unsaved, or the author said what
  /// to do with it.
  Future<bool> _mayLeave() => mayLeaveUnsaved(
    context,
    dirty: _session?.isDirty ?? false,
    title: 'Save changes to this tileset?',
    save: save,
  );

  Future<void> close() async {
    if (await _mayLeave()) widget.onClose?.call();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final s = _session;
    if (s == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      save();
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? s.redo() : s.undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      s.redo();
    } else if (ctrl && key == LogicalKeyboardKey.keyA) {
      s.selection.value = {for (var i = 0; i < s.data.tileCount; i++) i};
    } else if (key == LogicalKeyboardKey.escape) {
      s.selection.value = const {};
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── Picking tiles ────────────────────────────────────────────────────────

  (int, int)? _cellAt(Offset local, {bool clamp = false}) {
    final ts = _session!.data;
    if (ts.columns <= 0) return null;
    final p = local / _zoom;
    var col = ((p.dx - ts.margin) / (ts.tileWidth + ts.spacing)).floor();
    var row = ((p.dy - ts.margin) / (ts.tileHeight + ts.spacing)).floor();
    if (clamp) {
      col = col.clamp(0, ts.columns - 1);
      row = row.clamp(0, ts.rows - 1);
    }
    if (col < 0 || row < 0 || col >= ts.columns || row >= ts.rows) return null;
    return ts.contains(row * ts.columns + col) ? (col, row) : null;
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    if (_terrainMode) {
      _paintWang(e.localPosition, start: true);
      return;
    }
    final s = _session!;
    final at = _cellAt(e.localPosition);
    if (at == null) return;
    final id = at.$2 * s.data.columns + at.$1;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      final next = {...s.selection.value};
      next.contains(id) ? next.remove(id) : next.add(id);
      s.selection.value = next;
      _anchor = id;
      return;
    }
    if (keys.isShiftPressed && _anchor != null) {
      final a = _anchor!;
      s.selection.value = {
        for (var i = a < id ? a : id; i <= (a < id ? id : a); i++) i,
      };
      return;
    }
    _anchor = id;
    _dragFrom = at;
    s.selection.value = {id};
  }

  void _move(PointerMoveEvent e) {
    if (_terrainMode) {
      if (e.buttons == kPrimaryButton) _paintWang(e.localPosition);
      return;
    }
    final from = _dragFrom;
    if (from == null) return;
    final at = _cellAt(e.localPosition, clamp: true);
    if (at == null) return;
    final s = _session!;
    final ts = s.data;
    final c0 = from.$1 < at.$1 ? from.$1 : at.$1;
    final c1 = from.$1 < at.$1 ? at.$1 : from.$1;
    final r0 = from.$2 < at.$2 ? from.$2 : at.$2;
    final r1 = from.$2 < at.$2 ? at.$2 : from.$2;
    final next = {
      for (var r = r0; r <= r1; r++)
        for (var c = c0; c <= c1; c++)
          if (ts.contains(r * ts.columns + c)) r * ts.columns + c,
    };
    if (!setEquals(next, s.selection.value)) s.selection.value = next;
  }

  /// Gives the corner or edge under [local] the chosen terrain; with Alt,
  /// none; with Shift, the whole tile. A drag is one undo step.
  void _paintWang(Offset local, {bool start = false}) {
    final s = _session!;
    final ts = s.data;
    final set = _wangSet;
    if (set == null || set >= ts.wangSets.length) {
      if (start) s.say('Add a terrain set first: + beside TERRAIN SETS');
      return;
    }
    final at = _cellAt(local);
    if (at == null) return;
    final id = at.$2 * ts.columns + at.$1;
    final keys = HardwareKeyboard.instance;
    final color = keys.isAltPressed ? 0 : _wangColor;
    if (start) _wangStroke++;
    final w = ts.wangSets[set];
    if (keys.isShiftPressed) {
      if (start) s.fillWangIds(set, [id], color);
      return;
    }
    final r = ts.sourceRect(id);
    final slot = wangSlotAt(
      local / _zoom - r.topLeft,
      r.width,
      r.height,
      w.type,
    );
    if ((w.wangIds[id]?[slot] ?? 0) == color) return;
    s.setWangSlot(set, id, slot, color, mergeKey: ('wang', _wangStroke));
  }

  void _setTerrainMode(bool on) {
    final s = _session!;
    setState(() {
      _terrainMode = on;
      if (on && _wangSet == null && s.data.wangSets.isNotEmpty) _wangSet = 0;
    });
  }

  // ── Building ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_creating) {
      return Column(
        children: [
          _barShell(),
          Expanded(
            child: CreateTilesetForm(
              root: widget.root,
              image: widget.path,
              loadImage: widget.loadImage,
              onCreate: _create,
              onCancel: widget.onClose,
            ),
          ),
          if (_error != null) _messageLine(_error!),
        ],
      );
    }
    final s = _session;
    if (s == null) {
      return ColoredBox(
        color: EditorTheme.panelBg,
        child: Center(
          child: _error == null
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(color: EditorTheme.textSecondary),
                    ),
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Close'),
                    ),
                  ],
                ),
        ),
      );
    }
    return WorkspaceKeyScope(
      onKey: _onKey,
      child: Material(
        color: EditorTheme.panelBg,
        child: SignalConsumer(
          signals: [s.revision, s.selection, s.image],
          builder: (context, _) => Column(
            children: [
              _bar(s),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _grid(s)),
                    VerticalDivider(width: 1, color: EditorTheme.border),
                    SizedBox(width: 310, child: _inspector(s)),
                  ],
                ),
              ),
              _messageLine(
                _toast ??
                    '${s.data.columns} × ${s.data.rows} tiles of '
                        '${s.data.tileWidth} × ${s.data.tileHeight} px · '
                        'Shift+click a range, Ctrl+click to add, drag a block',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const String _title = 'Tileset Editor';

  /// The header while an image is being cut into a new tileset.
  Widget _barShell() => WorkspaceHeader(
    icon: Icons.grid_view,
    title: _title,
    showHistory: false,
    fullScreen: widget.fullScreen,
    onToggleFullScreen: widget.onToggleFullScreen,
    onClose: widget.onClose == null ? null : close,
  );

  Widget _bar(TilesetSession s) => WorkspaceHeader(
    icon: Icons.grid_view,
    title: _title,
    file: s.fileName,
    dirty: s.isDirty,
    onSave: save,
    onUndo: s.canUndo ? s.undo : null,
    onRedo: s.canRedo ? s.redo : null,
    fullScreen: widget.fullScreen,
    onToggleFullScreen: widget.onToggleFullScreen,
    onClose: widget.onClose == null ? null : close,
    tools: [
      EditorIconButton(
        icon: Icons.zoom_out,
        tooltip: 'Smaller',
        onTap: () => setState(() => _zoom = (_zoom / 1.5).clamp(0.5, 8)),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '${(_zoom * 100).round()}%',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
        ),
      ),
      EditorIconButton(
        icon: Icons.zoom_in,
        tooltip: 'Larger',
        onTap: () => setState(() => _zoom = (_zoom * 1.5).clamp(0.5, 8)),
      ),
      const SizedBox(width: 12),
      EditorIconButton(
        icon: Icons.border_outer,
        tooltip: 'Show collision on the tiles',
        isActive: _showCollision,
        onTap: () => setState(() => _showCollision = !_showCollision),
      ),
      const SizedBox(width: 12),
      EditorIconButton(
        icon: Icons.grid_on,
        tooltip: 'Tiles: collision, animation and properties',
        isActive: !_terrainMode,
        onTap: () => _setTerrainMode(false),
      ),
      EditorIconButton(
        icon: Icons.landscape_outlined,
        tooltip: 'Terrains: which corners and edges of which tiles are which',
        isActive: _terrainMode,
        onTap: () => _setTerrainMode(true),
      ),
    ],
  );

  Widget _messageLine(String text) => Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: EditorTheme.surfaceDark,
      border: Border(top: BorderSide(color: EditorTheme.border)),
    ),
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
    ),
  );

  Widget _grid(TilesetSession s) {
    final ts = s.data;
    final image = s.image.value;
    final width = (image?.width ?? ts.imageWidth) * _zoom;
    final height = (image?.height ?? ts.imageHeight) * _zoom;
    return ColoredBox(
      color: const Color(0xFF1E1E22),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Listener(
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: (_) => _dragFrom = null,
              onPointerSignal: (e) {
                if (e is PointerScrollEvent &&
                    HardwareKeyboard.instance.isControlPressed) {
                  setState(() {
                    _zoom = (e.scrollDelta.dy < 0 ? _zoom * 1.25 : _zoom / 1.25)
                        .clamp(0.5, 8);
                  });
                }
              },
              child: CustomPaint(
                key: const ValueKey('tileset-grid'),
                size: Size(width.toDouble(), height.toDouble()),
                painter: _GridPainter(
                  tileset: ts,
                  image: image,
                  zoom: _zoom,
                  selected: _terrainMode ? const {} : s.selection.value,
                  showCollision: _showCollision && !_terrainMode,
                  wang:
                      _terrainMode &&
                          _wangSet != null &&
                          _wangSet! < ts.wangSets.length
                      ? ts.wangSets[_wangSet!]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inspector(TilesetSession s) {
    if (_terrainMode) {
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [
          WangSetEditor(
            session: s,
            set: _wangSet,
            color: _wangColor,
            onSet: (i) => setState(() => _wangSet = i),
            onColor: (c) => setState(() => _wangColor = c),
          ),
        ],
      );
    }
    final selected = s.selection.value;
    final ts = s.data;
    if (selected.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [
          const _Heading('TILESET'),
          _Line(
            label: 'Name',
            child: MiniTextField(
              value: ts.name,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) s.rename(v.trim());
              },
            ),
          ),
          ReadonlyRow(label: 'Image', value: ts.image),
          ReadonlyRow(
            label: 'Tiles',
            value:
                '${ts.tileWidth} × ${ts.tileHeight} px, ${ts.columns} × ${ts.rows}'
                '${ts.margin != 0 ? ', margin ${ts.margin}' : ''}'
                '${ts.spacing != 0 ? ', spacing ${ts.spacing}' : ''}',
          ),
          _Line(
            label: 'Draw offset',
            child: Row(
              children: [
                Expanded(
                  child: MiniNumberField(
                    value: ts.tileOffsetX,
                    fractionDigits: 0,
                    onSubmitted: (v) => s.setTileOffset(v, ts.tileOffsetY),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: MiniNumberField(
                    value: ts.tileOffsetY,
                    fractionDigits: 0,
                    onSubmitted: (v) => s.setTileOffset(ts.tileOffsetX, v),
                  ),
                ),
              ],
            ),
          ),
          if (s.imageResized)
            _Warning(
              'The image is now ${s.image.value!.width} × '
              '${s.image.value!.height}; this tileset was cut from '
              '${ts.imageWidth} × ${ts.imageHeight}. Tiles past the old '
              'edge are not in it.',
            ),
          if (s.imageError != null) _Warning('Image: ${s.imageError}'),
          const SizedBox(height: 12),
          Text(
            'Select tiles to give them collision, animation and properties. '
            'A tileset\'s tiles are numbered from the top left, row by row.',
            style: TextStyle(fontSize: 11, color: EditorTheme.textMuted),
          ),
        ],
      );
    }
    final id = s.primary!;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _Heading(
          selected.length == 1
              ? 'TILE $id'
              : '${selected.length} TILES (FIELDS SHOW TILE $id)',
        ),
        const SizedBox(height: 4),
        const _Heading('COLLISION'),
        CollisionEditor(session: s),
        const SizedBox(height: 12),
        const _Heading('ANIMATION'),
        TileAnimationEditor(session: s),
        const SizedBox(height: 12),
        const _Heading('PROPERTIES'),
        TilePropertiesEditor(session: s),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: EditorTheme.textMuted,
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 14, color: EditorTheme.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: EditorTheme.warning),
          ),
        ),
      ],
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.tileset,
    required this.image,
    required this.zoom,
    required this.selected,
    required this.showCollision,
    this.wang,
  });

  final TilesetData tileset;
  final ui.Image? image;
  final double zoom;
  final Set<int> selected;
  final bool showCollision;

  /// A terrain set whose corners and edges to show.
  final WangSetData? wang;

  /// Where slot [slot]'s marker sits on a tile at [r].
  static Rect slotRect(Rect r, int slot) {
    final m = (r.width < r.height ? r.width : r.height) / 4;
    return switch (slot) {
      WangSetData.topLeft => Rect.fromLTWH(r.left, r.top, m, m),
      WangSetData.topRight => Rect.fromLTWH(r.right - m, r.top, m, m),
      WangSetData.bottomRight => Rect.fromLTWH(r.right - m, r.bottom - m, m, m),
      WangSetData.bottomLeft => Rect.fromLTWH(r.left, r.bottom - m, m, m),
      WangSetData.top => Rect.fromLTWH(r.center.dx - m, r.top, 2 * m, m / 1.5),
      WangSetData.bottom => Rect.fromLTWH(
        r.center.dx - m,
        r.bottom - m / 1.5,
        2 * m,
        m / 1.5,
      ),
      WangSetData.left => Rect.fromLTWH(
        r.left,
        r.center.dy - m,
        m / 1.5,
        2 * m,
      ),
      _ => Rect.fromLTWH(r.right - m / 1.5, r.center.dy - m, m / 1.5, 2 * m),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ts = tileset;
    canvas
      ..save()
      ..scale(zoom);
    final img = image;
    if (img != null) {
      canvas.drawImage(
        img,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = const Color(0x40FFFFFF);
    final marker = Paint()..color = const Color(0xFFFFB74D);
    for (var id = 0; id < ts.tileCount; id++) {
      final r = ts.sourceRect(id);
      canvas.drawRect(r, grid);
      final def = ts.tile(id);
      if (def == null) continue;
      final collision = def.collision;
      if (showCollision && collision != null) {
        final color = Color(MapCollisionKinds.resolve(collision.kind).color);
        for (final shape in collision.shapes) {
          final path = Path()
            ..addPolygon([
              for (final p in shape.outline()) p + r.topLeft,
            ], true);
          canvas
            ..drawPath(path, Paint()..color = color.withValues(alpha: 0.3))
            ..drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1 / zoom
                ..color = color,
            );
        }
      }
      if (def.isAnimated) {
        final s = r.width / 4;
        canvas.drawPath(
          Path()
            ..moveTo(r.right - s, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right, r.top + s)
            ..close(),
          marker,
        );
      }
    }
    final w = wang;
    if (w != null) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / zoom
        ..color = const Color(0xCC000000);
      for (final e in w.wangIds.entries) {
        if (!ts.contains(e.key)) continue;
        final r = ts.sourceRect(e.key);
        for (final slot in w.slots) {
          final c = e.value[slot];
          if (c < 1 || c > w.colors.length) continue;
          final marker = slotRect(r, slot);
          canvas
            ..drawRect(marker, Paint()..color = Color(w.colors[c - 1].color))
            ..drawRect(marker, outline);
        }
      }
    }
    final fill = Paint()
      ..color = EditorTheme.primaryBright.withValues(alpha: 0.25);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / zoom
      ..color = EditorTheme.primaryBright;
    for (final id in selected) {
      if (!ts.contains(id)) continue;
      final r = ts.sourceRect(id);
      canvas
        ..drawRect(r, fill)
        ..drawRect(r, edge);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
