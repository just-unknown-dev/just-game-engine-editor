part of 'settings_dialog.dart';

// The pages the editor's own settings are on.
const String _appearance = 'appearance';
const String _accessibility = 'accessibility';
const String _editing = 'editing';
const String _snapping = 'snapping';
const String _viewport = 'viewport';
const String _saving = 'saving';
const String _playing = 'playing';
const String _console = 'console';
const String _performance = 'performance';
const String _keyboard = 'keyboard';

bool _same(double a, double b) => (a - b).abs() < 1e-6;

/// A colour as a swatch's id.
String _hex(Color c) => c.toARGB32().toRadixString(16);

const List<(String, Color)> _gridColours = [
  ('White', Color(0xFFFFFFFF)),
  ('Grey', Color(0xFF9AA0A6)),
  ('Sky', Color(0xFF5AC8FA)),
  ('Mint', Color(0xFF63E6BE)),
  ('Amber', Color(0xFFFFC857)),
  ('Rose', Color(0xFFFF7AA2)),
];

const List<(String, Color)> _backdrops = [
  ('Charcoal', Color(0xFF1E1F22)),
  ('Midnight', Color(0xFF0E1726)),
  ('Slate', Color(0xFF2E3440)),
  ('Grey', Color(0xFF55595F)),
  ('Light', Color(0xFFD9DDE3)),
];

const List<(String, Color)> _selectionColours = [
  ('Sky', Color(0xFF5AC8FA)),
  ('Yellow', Color(0xFFFFD60A)),
  ('Magenta', Color(0xFFFF4FD8)),
  ('Orange', Color(0xFFFF9F0A)),
  ('White', Color(0xFFFFFFFF)),
];

/// Every one of the editor's own settings, page by page.
extension _SettingsCatalog on _EditorSettingsDialogState {
  List<_Setting> _settingsFor(OverlayUiSettings s) {
    const d = OverlayUiSettings.defaults();
    final accent = s.themeColor;
    return [
      ..._appearanceSettings(s, d, accent),
      ..._accessibilitySettings(s, d),
      ..._editingSettings(s, d, accent),
      ..._snappingSettings(s, d, accent),
      ..._viewportSettings(s, d, accent),
      ..._savingSettings(s, d, accent),
      ..._playingSettings(s),
      ..._consoleSettings(s, d, accent),
      ..._performanceSettings(s, d, accent),
    ];
  }

  // ── Appearance ─────────────────────────────────────────────────────────

  List<_Setting> _appearanceSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _appearance,
      label: 'Accent',
      hint: 'The colour of frames, selections and whatever is switched on.',
      keywords: 'theme colour color',
      isDefault: s.themeId == d.themeId,
      reset: (s) => s.copyWith(themeId: d.themeId, accent: d.accent),
      control: EditorSwatches(
        options: [
          for (final preset in _scope.theme.presets)
            (preset.id, preset.label, preset.data.primary),
        ],
        selectedId: s.themeId,
        onSelected: (id) {
          final preset = _scope.theme.preset(id);
          if (preset == null) return;
          _save(s.copyWith(themeId: id, accent: preset.data.primary));
        },
      ),
    ),
    _Setting(
      page: _appearance,
      label: 'Density',
      hint: 'How much room the toolbars leave around their buttons.',
      keywords: 'compact comfortable spacing padding',
      isDefault: _same(s.compactness, d.compactness),
      reset: (s) => s.copyWith(compactness: d.compactness),
      control: EditorSegmented<OverlayDensity>(
        value: s.density,
        options: [for (final o in OverlayDensity.values) (o, o.label)],
        accent: accent,
        onChanged: (o) => _save(s.copyWith(compactness: o.compactness)),
      ),
    ),
    _Setting(
      page: _appearance,
      label: 'Corner radius',
      hint: 'How round the frames, buttons and dialogs are.',
      keywords: 'rounded corners shape',
      isDefault: _same(s.cornerRadius, d.cornerRadius),
      reset: (s) => s.copyWith(cornerRadius: d.cornerRadius),
      control: _slider(
        s,
        s.cornerRadius,
        OverlayUiSettings.cornerRadiusRange,
        1,
        (v) => s.copyWith(cornerRadius: v),
        unit: 'px',
      ),
    ),
    _Setting(
      page: _appearance,
      label: 'Animation speed',
      hint: 'How quickly the dock panel slides open and shut.',
      keywords: 'motion transitions',
      isDefault: _same(s.animationSpeed, d.animationSpeed),
      reset: (s) => s.copyWith(animationSpeed: d.animationSpeed),
      control: _slider(
        s,
        s.animationSpeed,
        OverlayUiSettings.animationSpeedRange,
        0.1,
        (v) => s.copyWith(animationSpeed: v),
        decimals: 1,
        unit: '×',
      ),
    ),
  ];

  // ── Accessibility ──────────────────────────────────────────────────────

  List<_Setting> _accessibilitySettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
  ) => [
    _Setting(
      page: _accessibility,
      group: 'Reading',
      label: 'Text size',
      hint: 'Scales all of the editor\'s text, on top of the system\'s own.',
      keywords: 'font scale zoom readable accessibility',
      isDefault: _same(s.textScale, d.textScale),
      reset: (s) => s.copyWith(textScale: d.textScale),
      control: _slider(
        s,
        s.textScale,
        OverlayUiSettings.textScaleRange,
        0.05,
        (v) => s.copyWith(textScale: v),
        displayScale: 100,
        unit: '%',
      ),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Reading',
      label: 'Bolder text',
      hint: 'All of the editor\'s text a weight heavier.',
      keywords: 'bold weight font readable',
      value: s.boldText,
      apply: (v) => s.copyWith(boldText: v),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Seeing',
      label: 'High contrast',
      hint:
          'Brighter secondary text, lines between regions that show, '
          'stronger selection and outlines.',
      keywords: 'contrast visibility vision low',
      value: s.highContrast,
      apply: (v) => s.copyWith(highContrast: v),
    ),
    _Setting(
      page: _accessibility,
      group: 'Seeing',
      label: 'Colour-blind safe colours',
      hint:
          'Errors, warnings, success and information in colours told apart '
          'by everyone — no red against green.',
      keywords: 'color colour blind deuteranopia protanopia status',
      isDefault: !s.colourBlindSafe,
      reset: (s) => s.copyWith(colourBlindSafe: false),
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // What they look like now.
          for (final (colour, name) in [
            (EditorTheme.error, 'Error'),
            (EditorTheme.warning, 'Warning'),
            (EditorTheme.success, 'Success'),
            (EditorTheme.info, 'Information'),
          ])
            Tooltip(
              message: name,
              child: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const SizedBox(width: 4),
          EditorToggle(
            value: s.colourBlindSafe,
            label: 'Colour-blind safe colours',
            accent: s.themeColor,
            onChanged: (v) => _save(s.copyWith(colourBlindSafe: v)),
          ),
        ],
      ),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Moving',
      label: 'Reduce motion',
      hint: 'Nothing slides, fades or eases: every change happens at once.',
      keywords: 'animation motion vestibular',
      value: s.reduceMotion,
      apply: (v) => s.copyWith(reduceMotion: v),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Moving',
      label: 'Longer timings',
      hint:
          'Tooltips come sooner and stay a while; messages stay on screen '
          'longer before they go.',
      keywords: 'time tooltip message snackbar slow',
      value: s.longerTimings,
      apply: (v) => s.copyWith(longerTimings: v),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Pointing and keyboard',
      label: 'Bigger targets',
      hint:
          'Every button, tab and row at least 32 px rather than 24: easier '
          'to hit, and the chrome gets roomier.',
      keywords: 'size touch click target motor',
      value: s.largeTargets,
      apply: (v) => s.copyWith(largeTargets: v),
    ),
    _toggleSetting(
      s,
      page: _accessibility,
      group: 'Pointing and keyboard',
      label: 'Always-visible focus',
      hint:
          'Outline whatever has the keyboard, however it got there — not '
          'only while Tab is being used.',
      keywords: 'focus keyboard outline ring tab',
      value: s.alwaysShowFocus,
      apply: (v) => s.copyWith(alwaysShowFocus: v),
    ),
  ];

  // ── Editing ────────────────────────────────────────────────────────────

  List<_Setting> _editingSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _editing,
      group: 'History',
      label: 'Undo steps',
      hint:
          'How far Ctrl+Z can go back. More keeps more in memory; fewer '
          'drops the oldest at once.',
      keywords: 'undo redo history memory limit',
      isDefault: s.undoLimit == d.undoLimit,
      reset: (s) => s.copyWith(undoLimit: d.undoLimit),
      control: _slider(
        s,
        s.undoLimit.toDouble(),
        OverlayUiSettings.undoLimitRange,
        10,
        (v) => s.copyWith(undoLimit: v.round()),
      ),
    ),
    _toggleSetting(
      s,
      page: _editing,
      group: 'Asking first',
      label: 'Confirm deletes',
      hint:
          'Ask before deleting what is selected — from the keyboard, a '
          'menu or the scene tree.',
      keywords: 'delete confirm ask remove prompt',
      value: s.confirmDelete,
      apply: (v) => s.copyWith(confirmDelete: v),
    ),
    _Setting(
      page: _editing,
      group: 'Asking first',
      label: 'Closing a scene',
      hint: 'When closing a scene asks first.',
      keywords: 'close scene confirm prompt unsaved',
      isDefault: s.closePrompt == d.closePrompt,
      reset: (s) => s.copyWith(closePrompt: d.closePrompt),
      control: EditorSegmented<ClosePrompt>(
        value: s.closePrompt,
        options: const [
          (ClosePrompt.unsaved, 'With unsaved changes'),
          (ClosePrompt.always, 'Always'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(closePrompt: v)),
      ),
    ),
  ];

  // ── Snapping ───────────────────────────────────────────────────────────

  /// A step as a chip says it.
  static String _step(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  List<_Setting> _snappingSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _snapping,
      group: 'Moving',
      label: 'Snapping',
      hint:
          'Moving, turning and scaling snap, in the viewport and the Level '
          'Designer. The same switch as the magnet over the viewport and '
          'the designer\'s Snap; Ctrl while dragging there moves freely.',
      keywords: 'snap grid snapping align magnet on off',
      isDefault: s.gridSnappingEnabled == d.gridSnappingEnabled,
      reset: (s) => s.copyWith(gridSnappingEnabled: d.gridSnappingEnabled),
      control: EditorToggle(
        value: s.gridSnappingEnabled,
        label: 'Snapping',
        accent: accent,
        onChanged: (v) => _save(s.copyWith(gridSnappingEnabled: v)),
      ),
    ),
    _Setting(
      page: _snapping,
      group: 'Moving',
      label: 'Move step',
      hint:
          'What moving snaps in, whatever the grid drawn: keep a 32 grid '
          'and move in 8s. Grid is the grid\'s own size. Right-click the '
          'magnet to change it from the viewport.',
      keywords: 'snap step move increment translate position grid value',
      isDefault: _same(s.moveStep, d.moveStep),
      reset: (s) => s.copyWith(moveStep: d.moveStep),
      control: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          for (final step in QuickSnapBar.steps)
            EditorChip(
              label: step == 0 ? 'Grid (${_step(s.gridSize)})' : _step(step),
              selected: _same(s.moveStep, step),
              onTap: () => _save(s.copyWith(moveStep: step)),
            ),
        ],
      ),
    ),
    _Setting(
      page: _snapping,
      group: 'Moving',
      label: 'Move step in 3-D',
      hint:
          'What moving snaps in, in a 3-D scene, in metres: the gizmo, the '
          'handles, where the Level Designer places things, and its grid.',
      keywords: 'snap step move increment metres 3d space grid',
      isDefault: _same(s.moveStep3D, d.moveStep3D),
      reset: (s) => s.copyWith(moveStep3D: d.moveStep3D),
      control: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          for (final step in MoveStep3DField.steps)
            EditorChip(
              label: MoveStep3DField.label(step),
              selected: _same(s.moveStep3D, step),
              onTap: () => _save(s.copyWith(moveStep3D: step)),
            ),
        ],
      ),
    ),
    _Setting(
      page: _snapping,
      group: 'Moving',
      label: 'Nudge distance',
      hint:
          'How far an arrow key moves the selection in the Level Designer: '
          'the move step, or a distance of its own. Shift and an arrow '
          'always moves one unit.',
      keywords: 'arrow keys move nudge step',
      isDefault: _same(s.nudgeDistance, d.nudgeDistance),
      reset: (s) => s.copyWith(nudgeDistance: d.nudgeDistance),
      control: EditorSegmented<double>(
        value: s.nudgeDistance,
        options: const [
          (0, 'Move step'),
          (1, '1'),
          (2, '2'),
          (4, '4'),
          (8, '8'),
          (16, '16'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(nudgeDistance: v)),
      ),
    ),
    _Setting(
      page: _snapping,
      group: 'Turning and scaling',
      label: 'Rotation step',
      hint:
          'How far a snapped turn moves at a time: the rotate handle, and '
          'the Level Designer\'s.',
      keywords: 'snap angle degrees turn rotate increment',
      isDefault: _same(s.rotationStep, d.rotationStep),
      reset: (s) => s.copyWith(rotationStep: d.rotationStep),
      control: _slider(
        s,
        s.rotationStep,
        OverlayUiSettings.rotationStepRange,
        1,
        (v) => s.copyWith(rotationStep: v),
        unit: '°',
      ),
    ),
    _Setting(
      page: _snapping,
      group: 'Turning and scaling',
      label: 'Scale step',
      hint: 'What a snapped scale moves in: at 10 %, 1.0, 1.1, 1.2…',
      keywords: 'snap scale size increment',
      isDefault: _same(s.scaleStep, d.scaleStep),
      reset: (s) => s.copyWith(scaleStep: d.scaleStep),
      control: _slider(
        s,
        s.scaleStep,
        OverlayUiSettings.scaleStepRange,
        0.01,
        (v) => s.copyWith(scaleStep: v),
        displayScale: 100,
        unit: '%',
      ),
    ),
    _toggleSetting(
      s,
      page: _snapping,
      group: 'Level Designer',
      label: 'Smart snap',
      hint:
          'Also snap to other things\' edges and centres, and to ruler '
          'guides.',
      keywords: 'smart snap edges align guides designer',
      value: s.smartSnap,
      fallback: d.smartSnap,
      apply: (v) => s.copyWith(smartSnap: v),
    ),
  ];

  // ── Viewport ───────────────────────────────────────────────────────────

  List<_Setting> _viewportSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _viewport,
      group: 'Grid',
      label: 'Show grid',
      hint:
          'Draw the grid behind the level while editing. A play-test '
          'hides it.',
      keywords: 'lines',
      isDefault: s.showGrid == d.showGrid,
      reset: (s) => s.copyWith(showGrid: d.showGrid),
      control: EditorToggle(
        value: s.showGrid,
        label: 'Show grid',
        accent: accent,
        onChanged: (v) => _save(s.copyWith(showGrid: v)),
      ),
    ),
    _Setting(
      page: _viewport,
      group: 'Grid',
      label: 'Grid size',
      hint:
          'World units between grid lines. The Level Designer’s grid '
          'control sets this too.',
      keywords: 'cell spacing units',
      isDefault: _same(s.gridSize, d.gridSize),
      reset: (s) => s.copyWith(gridSize: d.gridSize),
      control: _slider(
        s,
        s.gridSize,
        OverlayUiSettings.gridSizeRange,
        1,
        (v) => s.copyWith(gridSize: v),
        unit: 'u',
      ),
    ),
    _Setting(
      page: _viewport,
      group: 'Grid',
      label: 'Grid colour',
      hint: 'The colour of the grid\'s lines, and of a tile map\'s cells.',
      keywords: 'grid lines color colour',
      isDefault: s.gridColour == d.gridColour,
      reset: (s) => s.copyWith(gridColour: d.gridColour),
      control: EditorSwatches(
        options: [
          for (final (name, colour) in _gridColours)
            (_hex(colour), name, colour),
        ],
        selectedId: _hex(s.gridColour),
        onSelected: (id) => _save(
          s.copyWith(
            gridColour: _gridColours.firstWhere((c) => _hex(c.$2) == id).$2,
          ),
        ),
      ),
    ),
    _Setting(
      page: _viewport,
      group: 'Grid',
      label: 'Grid strength',
      hint: 'How strongly the grid shows over the level.',
      keywords: 'grid opacity alpha faint visible',
      isDefault: _same(s.gridOpacity, d.gridOpacity),
      reset: (s) => s.copyWith(gridOpacity: d.gridOpacity),
      control: _slider(
        s,
        s.gridOpacity,
        OverlayUiSettings.gridOpacityRange,
        0.05,
        (v) => s.copyWith(gridOpacity: v),
        displayScale: 100,
        unit: '%',
      ),
    ),
    _Setting(
      page: _viewport,
      group: 'Drawing',
      label: 'Backdrop',
      hint:
          'What the viewport shows behind the level while editing. A '
          'play-test uses the game\'s own.',
      keywords: 'background clear colour color',
      isDefault: s.backdrop == d.backdrop,
      reset: (s) => s.copyWith(clearBackdrop: true),
      control: EditorSwatches(
        options: [
          ('game', 'The game\'s own', const Color(0xFF1A1A2E)),
          for (final (name, colour) in _backdrops) (_hex(colour), name, colour),
        ],
        selectedId: s.backdrop == null ? 'game' : _hex(s.backdrop!),
        onSelected: (id) => _save(
          id == 'game'
              ? s.copyWith(clearBackdrop: true)
              : s.copyWith(
                  backdrop: _backdrops.firstWhere((c) => _hex(c.$2) == id).$2,
                ),
        ),
      ),
    ),
    for (final mode in GizmoMode.values)
      _Setting(
        page: _viewport,
        group: 'Gizmos',
        label: switch (mode) {
          GizmoMode.editor => 'Gizmos while editing',
          GizmoMode.designer => 'Gizmos in the Level Designer',
          GizmoMode.play => 'Gizmos in a play-test',
        },
        hint:
            'Draw the editor\'s aids over the level ${switch (mode) {
              GizmoMode.editor => 'while editing',
              GizmoMode.designer => 'with the Level Designer open',
              GizmoMode.play => 'during a play-test',
            }}: markers, camera frames, light and sound reach, collider and '
            'selection outlines, a kit\'s paths and bounds. The button '
            'above snapping switches this while there; right-click it for '
            'which kinds.',
        keywords: 'gizmos outlines markers icons colliders overlays clean',
        isDefault: s.gizmos.of(mode) == d.gizmos.of(mode),
        reset: (s) =>
            s.copyWith(gizmos: s.gizmos.withMode(mode, d.gizmos.of(mode))),
        control: EditorToggle(
          value: s.gizmos.of(mode).shown,
          label: 'Gizmos in ${mode.label}',
          accent: accent,
          onChanged: (v) => _save(
            s.copyWith(
              gizmos: s.gizmos.withMode(
                mode,
                s.gizmos.of(mode).copyWith(shown: v),
              ),
            ),
          ),
        ),
      ),
    _Setting(
      page: _viewport,
      group: 'Drawing',
      label: 'Handle size',
      hint:
          'How big the move, scale and turn handles are drawn — and how '
          'far off the pointer still takes hold of one.',
      keywords: 'gizmo handles size arrows',
      isDefault: _same(s.gizmoScale, d.gizmoScale),
      reset: (s) => s.copyWith(gizmoScale: d.gizmoScale),
      control: _slider(
        s,
        s.gizmoScale,
        OverlayUiSettings.gizmoScaleRange,
        0.05,
        (v) => s.copyWith(gizmoScale: v),
        displayScale: 100,
        unit: '%',
      ),
    ),
    _Setting(
      page: _viewport,
      group: 'Drawing',
      label: 'Selection colour',
      hint:
          'The outline round what is selected, in the viewport and the '
          'Level Designer. As built, each has its own.',
      keywords: 'selection outline highlight colour color',
      isDefault: s.selectionColour == d.selectionColour,
      reset: (s) => s.copyWith(clearSelectionColour: true),
      control: EditorSwatches(
        options: [
          ('default', 'As built', const Color(0xFF40E0D0)),
          for (final (name, colour) in _selectionColours)
            (_hex(colour), name, colour),
        ],
        selectedId: s.selectionColour == null
            ? 'default'
            : _hex(s.selectionColour!),
        onSelected: (id) => _save(
          id == 'default'
              ? s.copyWith(clearSelectionColour: true)
              : s.copyWith(
                  selectionColour: _selectionColours
                      .firstWhere((c) => _hex(c.$2) == id)
                      .$2,
                ),
        ),
      ),
    ),
  ];

  // ── Saving ─────────────────────────────────────────────────────────────

  List<_Setting> _savingSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _saving,
      group: 'Autosave',
      label: 'Autosave',
      hint: 'How often a scene with unsaved changes is saved for you.',
      keywords: 'autosave backup interval minutes crash',
      isDefault: _same(s.autosaveMinutes, d.autosaveMinutes),
      reset: (s) => s.copyWith(autosaveMinutes: d.autosaveMinutes),
      control: EditorSegmented<double>(
        value: s.autosaveMinutes,
        options: const [
          (0, 'Off'),
          (1, '1 min'),
          (2, '2 min'),
          (5, '5 min'),
          (10, '10 min'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(autosaveMinutes: v)),
      ),
    ),
    _Setting(
      page: _saving,
      group: 'Autosave',
      label: 'Autosave does',
      hint:
          'A backup goes to .editor_backups in the project and leaves the '
          'scene file alone until you save; if the editor closes first, '
          'opening the scene offers the changes back. Or the scene itself '
          'is saved.',
      keywords: 'autosave backup save mode recover',
      isDefault: s.autosaveMode == d.autosaveMode,
      reset: (s) => s.copyWith(autosaveMode: d.autosaveMode),
      control: EditorSegmented<AutosaveMode>(
        value: s.autosaveMode,
        options: const [
          (AutosaveMode.backup, 'Keep a backup'),
          (AutosaveMode.save, 'Save the scene'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(autosaveMode: v)),
      ),
    ),
    _Setting(
      page: _saving,
      group: 'Autosave',
      label: 'Backups kept',
      hint: 'For each scene; older ones are deleted.',
      keywords: 'backups history keep count',
      isDefault: s.backupsToKeep == d.backupsToKeep,
      reset: (s) => s.copyWith(backupsToKeep: d.backupsToKeep),
      control: _slider(
        s,
        s.backupsToKeep.toDouble(),
        OverlayUiSettings.backupsRange,
        1,
        (v) => s.copyWith(backupsToKeep: v.round()),
      ),
    ),
    _toggleSetting(
      s,
      page: _saving,
      group: 'Starting',
      label: 'Reopen the last scene',
      hint: 'Open the scene you were working on when the editor last closed.',
      keywords: 'startup start open last scene session restore',
      value: s.reopenLastScene,
      fallback: d.reopenLastScene,
      apply: (v) => s.copyWith(reopenLastScene: v),
    ),
    _toggleSetting(
      s,
      page: _saving,
      group: 'Starting',
      label: 'Reopen the Level Designer',
      hint: 'And the Level Designer, if it was open on it.',
      keywords: 'startup designer level session restore',
      value: s.reopenDesigner,
      fallback: d.reopenDesigner,
      apply: (v) => s.copyWith(reopenDesigner: v),
    ),
  ];

  // ── Play-testing ───────────────────────────────────────────────────────

  List<_Setting> _playingSettings(OverlayUiSettings s) => [
    _toggleSetting(
      s,
      page: _playing,
      label: 'Pause on error',
      hint:
          'Pause the play-test the moment an error is logged, with the game '
          'as it was when it happened.',
      keywords: 'play test pause error exception break debug',
      value: s.pauseOnError,
      apply: (v) => s.copyWith(pauseOnError: v),
    ),
    _toggleSetting(
      s,
      page: _playing,
      label: 'Step aside while playing',
      hint:
          'The game fills the window while it runs, with the play controls '
          'in a small bar at the top. Pausing brings the editor back.',
      keywords: 'play test hide chrome fullscreen panels',
      value: s.hideChromeWhilePlaying,
      apply: (v) => s.copyWith(hideChromeWhilePlaying: v),
    ),
  ];

  // ── Console and messages ───────────────────────────────────────────────

  List<_Setting> _consoleSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _console,
      group: 'Console',
      label: 'Lines kept',
      hint: 'How much the Console holds; the oldest lines go first.',
      keywords: 'console log lines entries limit history',
      isDefault: s.consoleMaxEntries == d.consoleMaxEntries,
      reset: (s) => s.copyWith(consoleMaxEntries: d.consoleMaxEntries),
      control: _slider(
        s,
        s.consoleMaxEntries.toDouble(),
        OverlayUiSettings.consoleEntriesRange,
        100,
        (v) => s.copyWith(consoleMaxEntries: v.round()),
      ),
    ),
    _Setting(
      page: _console,
      group: 'Console',
      label: 'Levels shown at first',
      hint:
          'What a new Console shows. One already open keeps the filter it '
          'has.',
      keywords: 'console log levels filter debug info warning error',
      isDefault: s.consoleHiddenLevels.isEmpty,
      reset: (s) => s.copyWith(consoleHiddenLevels: const []),
      control: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          for (final level in DebuggerLogLevel.values)
            EditorChip(
              label: '${level.name[0].toUpperCase()}${level.name.substring(1)}',
              selected: !s.consoleHiddenLevels.contains(level.name),
              onTap: () {
                final hidden = {...s.consoleHiddenLevels};
                if (!hidden.remove(level.name)) hidden.add(level.name);
                _save(
                  s.copyWith(
                    consoleHiddenLevels: [
                      for (final l in DebuggerLogLevel.values)
                        if (hidden.contains(l.name)) l.name,
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    ),
    _toggleSetting(
      s,
      page: _console,
      group: 'Console',
      label: 'Show times',
      hint: 'The time beside each line.',
      keywords: 'console timestamp time clock',
      value: s.consoleTimestamps,
      fallback: d.consoleTimestamps,
      apply: (v) => s.copyWith(consoleTimestamps: v),
    ),
    _Setting(
      page: _console,
      group: 'Messages',
      label: 'Messages',
      hint:
          'Which messages appear over the editor. Important: warnings and '
          'errors. A task\'s progress always shows.',
      keywords: 'messages snackbar notifications quiet toast',
      isDefault: s.messageLevel == d.messageLevel,
      reset: (s) => s.copyWith(messageLevel: d.messageLevel),
      control: EditorSegmented<MessageLevel>(
        value: s.messageLevel,
        options: const [
          (MessageLevel.all, 'All'),
          (MessageLevel.important, 'Important'),
          (MessageLevel.errors, 'Errors only'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(messageLevel: v)),
      ),
    ),
  ];

  // ── Performance ────────────────────────────────────────────────────────

  List<_Setting> _performanceSettings(
    OverlayUiSettings s,
    OverlayUiSettings d,
    Color accent,
  ) => [
    _Setting(
      page: _performance,
      label: 'Target frame rate',
      hint:
          'The rate the game aims for: the status bar and the Profiler '
          'measure each frame against its budget — 16.7 ms at 60.',
      keywords: 'fps frame rate budget target hz',
      isDefault: _same(s.targetFps, d.targetFps),
      reset: (s) => s.copyWith(targetFps: d.targetFps),
      control: EditorSegmented<double>(
        value: s.targetFps,
        options: const [
          (30, '30'),
          (60, '60'),
          (90, '90'),
          (120, '120'),
          (144, '144'),
        ],
        accent: accent,
        onChanged: (v) => _save(s.copyWith(targetFps: v)),
      ),
    ),
    _Setting(
      page: _performance,
      label: 'Status bar refresh',
      hint:
          'How often the status bar and the Profiler’s history update. '
          'Shorter is livelier, and costs a little more.',
      keywords: 'metrics fps sampling interval ticker',
      isDefault: _same(s.metricRefreshMs, d.metricRefreshMs),
      reset: (s) => s.copyWith(metricRefreshMs: d.metricRefreshMs),
      control: _slider(
        s,
        s.metricRefreshMs,
        OverlayUiSettings.metricRefreshRange,
        10,
        (v) => s.copyWith(metricRefreshMs: v),
        unit: 'ms',
      ),
    ),
  ];
}
