part of 'material_2d_workspace.dart';

/// The 2-D material window's view: the stage, its tools and keys.
extension Material2DWorkspaceStage on Material2DWorkspaceState {
  // ── The view ──────────────────────────────────────────────────────────

  // Both stages draw alike: one with the material, one without.
  void _view2(void Function(Material2DStage s) apply) {
    apply(stage);
    apply(plainStage);
    _repaint.value++;
  }

  /// Draws a pixel of what is shown [zoom] logical pixels big; null fits it
  /// to the preview.
  void setZoom(double? zoom) {
    _view2((s) => s.zoom = zoom);
    // The zoom controls say so; the window is not built again for each
    // turn of the wheel.
    _framing.value++;
  }

  /// One step of [zoomSteps] in (+1) or out (-1), around [around] — a
  /// point of the preview of [size] — or its middle.
  void zoomBy(int steps, {Offset? around, Size? size}) {
    final now = stage.scale;
    final next = steps > 0
        ? Material2DWorkspaceState.zoomSteps.firstWhere(
            (z) => z > now * 1.001,
            orElse: () => Material2DWorkspaceState.zoomSteps.last,
          )
        : Material2DWorkspaceState.zoomSteps.lastWhere(
            (z) => z < now * 0.999,
            orElse: () => Material2DWorkspaceState.zoomSteps.first,
          );
    if (around != null && size != null && now > 0) {
      // What is under the pointer stays there.
      final p = around - size.center(Offset.zero);
      final pan = p - (p - stage.pan) * (next / now);
      _view2((s) => s.pan = pan);
    }
    setZoom(next);
  }

  /// Fits what is shown to the preview again, in its middle.
  void fit() {
    _view2(
      (s) => s
        ..zoom = null
        ..pan = Offset.zero,
    );
    _framing.value++;
  }

  /// Moves what is shown by [delta] logical pixels.
  void panBy(Offset delta) => _view2((s) => s.pan = s.pan + delta);

  /// Goes to [seconds] into the preview.
  void scrub(double seconds) {
    _unshown = 0;
    _clock.value = seconds.clamp(0, Material2DWorkspaceState.loop).toDouble();
    stage.time = plainStage.time = _clock.value;
    _repaint.value++;
  }

  /// Sets the light: where it is (a share of the preview across and
  /// down), its colour, how high it is, how far it reaches, how bright.
  void setLight({
    Offset? at,
    Color? color,
    double? height,
    double? reach,
    double? strength,
  }) {
    _view2((s) {
      if (at != null) s.light = at;
      if (color != null) s.lightColor = color;
      if (height != null) s.lightHeight = height;
      if (reach != null) s.lightReach = reach;
      if (strength != null) s.lightStrength = strength;
    });
    // Only what shows the light follows it: its handle and settings.
    _lightMoved.value++;
  }

  /// Sizes the material's panel [width] logical pixels wide.
  void setPanelWidth(double width) {
    _panelWidth = Material2DWorkspaceState._lastPanelWidth = width
        .clamp(220, 560)
        .toDouble();
    _widths.value++;
  }

  /// Sizes the effects panel [width] logical pixels wide.
  void setEffectsWidth(double width) {
    _effectsWidth = Material2DWorkspaceState._lastEffectsWidth = width
        .clamp(260, 640)
        .toDouble();
    _widths.value++;
  }

  /// Switches [effect] on (one undo step) and shows its card, unfolded.
  void addEffect(String effect) {
    _folds.set('2d.$effect', false);
    change((x) => x.withEffect(effect, true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKeys[effect]?.currentContext;
      if (card != null && card.mounted) {
        Scrollable.ensureVisible(card, alignment: 0.1);
      }
    });
  }

  /// Takes [effect] out of the material, as one undo step: switched off
  /// and its values gone. In a variant its own values go, and it is
  /// switched off over its parent's only when the parent has it on.
  void removeEffect(String effect) {
    if (_solo == effect) _solo = null;
    final m = material;
    if (!m.isVariant) {
      edit(
        Material2DWorkspaceState.resetEffect(
          m,
          effect,
        ).withEffect(effect, false),
      );
      return;
    }
    final mine = m.withoutEffectOverride(effect);
    final parentHasIt = MaterialChain.resolve2D(
      widget.path,
      (p) => p == widget.path ? mine : _parent(p),
    ).value.isOn(effect);
    edit(parentHasIt ? mine.withEffect(effect, false) : mine);
  }

  /// Opens the menu of the effects that are off below [anchor], grouped
  /// and searched, and switches on the one picked.
  Future<void> openAddEffect(BuildContext anchor) async {
    final m = shown;
    final groups = [
      for (final group in Material2DWorkspaceState.groupsOf(m.kind))
        PickMenuGroup(Material2DWorkspaceState._groups[group]!, [
          for (final e in Material2DEffects.forKind(m.kind))
            if (e.group == group && !m.isOn(e.id))
              PickMenuItem(e.id, e.label, detail: e.description),
        ]),
    ]..removeWhere((g) => g.items.isEmpty);
    final picked = await showPickMenu<String>(
      anchor,
      groups: groups,
      hint: 'Search effects',
    );
    if (picked != null && mounted) addEffect(picked);
  }

  /// The sprite selected in the scene, if one is: its image and the part
  /// of it it shows.
  Sprite? get selectedSprite {
    final entity = widget.workspace.scope.sceneState.selectedEntity.value;
    final renderable = entity?.getComponent<RenderableComponent>()?.renderable;
    return renderable is Sprite && renderable.image != null ? renderable : null;
  }

  /// The image file of the sprite selected in the scene, if it has one.
  String? get selectedSpritePath {
    final entity = widget.workspace.scope.sceneState.selectedEntity.value;
    final path = entity?.getComponent<SpriteComponent>()?.spritePath ?? '';
    return path.isEmpty ? null : path;
  }

  /// The image of the sprite the preview shows, when it is one of the
  /// game's: the selected sprite's (Selected), or the sprite Auto picked.
  String? get shownSpritePath => switch (_subject) {
    Material2DSubject.selected => selectedSpritePath,
    Material2DSubject.auto => _user?.spritePath,
    _ => null,
  };

  /// [m] with every effect but [solo] left out: what the preview draws
  /// while one is soloed.
  Material2DFile _soloed(Material2DFile m) {
    var file = m;
    for (final e in Material2DEffects.forKind(shown.kind)) {
      if (e.id != _solo && shown.isOn(e.id)) {
        file = file.withEffect(e.id, false);
      }
    }
    return file;
  }

  // The stage shows what the workspace does. (The plain stage reads the
  // material through the stage's library.)
  void _sync() {
    if (!mounted || !_loaded) return;
    _syncScene();
    stage.library.preview(widget.path, _solo == null ? drawn : _soloed(drawn));
    final sprite = _subject == Material2DSubject.selected
        ? selectedSprite
        : null;
    final auto = _subject == Material2DSubject.auto;
    final quality = auto
        ? ((_user?.pixelArt ?? false)
              ? FilterQuality.none
              : FilterQuality.medium)
        : (sprite?.filterQuality ?? FilterQuality.medium);
    for (final s in [stage, plainStage]) {
      s
        ..background = _lightBackground
            ? const Color(0xFFD9DDE3)
            : const Color(0xFF2A2E35)
        ..show(
          widget.path,
          kind: shown.kind,
          subject: _subject,
          image: auto ? _userImage : sprite?.image,
          source: sprite?.sourceRect,
          user: auto ? _user : null,
          quality: quality,
          lit: _lit && shown.kind == Material2DKind.sprite,
        );
    }
    _repaint.value++;
    _extensionView.changed();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final screen = shown.kind == Material2DKind.screen;
    // Space held shows the subject without the material.
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !WorkspaceKeyScope.isTyping) {
      if (event is KeyDownEvent) setHoldingPlain(true);
      if (event is KeyUpEvent) setHoldingPlain(false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Ctrl is Cmd on macOS.
    final ctrl = EditorKeys.primaryPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl) {
      if (WorkspaceKeyScope.isTyping) return KeyEventResult.ignored;
      // A chord is not a bare key: Alt+C, or Ctrl+C on a Mac, is not C.
      if (HardwareKeyboard.instance.isAltPressed || EditorKeys.otherPressed) {
        return KeyEventResult.ignored;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyF:
          fit();
        case LogicalKeyboardKey.digit1:
          setZoom(1);
        case LogicalKeyboardKey.digit2:
          setZoom(2);
        case LogicalKeyboardKey.digit4:
          setZoom(4);
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.numpadAdd:
          zoomBy(1);
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          zoomBy(-1);
        case LogicalKeyboardKey.keyL when !screen:
          setLit(!_lit);
        case LogicalKeyboardKey.keyN when !screen:
          setShowNormals(!stage.showNormals);
        case LogicalKeyboardKey.keyT when !screen:
          setTiled(!stage.tiled);
        case LogicalKeyboardKey.keyC:
          setCompare(_compareAt == null ? 0.5 : null);
        case LogicalKeyboardKey.keyB:
          setLightBackground(!_lightBackground);
        case LogicalKeyboardKey.keyP:
          setPlaying(!_playing);
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyZ when shift:
      case LogicalKeyboardKey.keyY:
        redo();
      case LogicalKeyboardKey.keyZ:
        undo();
      case LogicalKeyboardKey.keyS:
        save();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // The three panels side by side, as wide as they are dragged to. A drag
  // builds only this row: the panels are the ones the window was built
  // with, and are laid out again.
  Widget _panels(Widget fields, Widget preview, Widget effects) =>
      ValueListenableBuilder<int>(
        valueListenable: _widths,
        builder: (context, _, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: _panelWidth, child: fields),
            PanelResizeHandle(onDrag: (dx) => setPanelWidth(_panelWidth + dx)),
            Expanded(child: preview),
            PanelResizeHandle(
              onDrag: (dx) => setEffectsWidth(_effectsWidth - dx),
            ),
            SizedBox(width: _effectsWidth, child: effects),
          ],
        ),
      );
}
