import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../dialogs/binding_conflicts_dialog.dart';
import '../../dialogs/confirm_delete_dialog.dart';
import '../../dialogs/new_action_dialog.dart';
import '../../dialogs/scene_actions_dialogs.dart';
import '../../../core/constants/editor_constants.dart';
import '../../../core/serialization/input_bindings_file_generator.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../input_setup/input_setup_properties.dart';
import '../settings/overlay_ui_settings.dart';
import '../shared/snackbar.dart';

// ── Dock toggle button ────────────────────────────────────────────────────────

class InputSetupButton extends StatelessWidget {
  const InputSetupButton({
    super.key,
    required this.settings,
    required this.onPressed,
  });

  final OverlayUiSettings settings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'Input Setup',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(settings.cornerRadius),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8 * settings.compactness,
              vertical: 6 * settings.compactness,
            ),
            child: Icon(
              Icons.keyboard_alt_outlined,
              size: 15 * settings.effectiveTextScale,
              color: settings.themeColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Centered overlay ──────────────────────────────────────────────────────────

/// Which direction of a Vector2-type action's composite binding is being
/// edited — `null` (via [CaptureTarget.direction]) means a plain
/// [ActionType.button] action's whole key list instead.
enum InputDirection { up, down, left, right }

/// What a key/mouse/gamepad capture is currently being recorded into: one
/// action, and — only for [ActionType.vector2] actions being captured via
/// keyboard — which of its four directions. [isGamepad] is mutually
/// exclusive with [direction]: gamepad capture only ever targets a whole
/// [ActionType.button] action's single [InputBinding.gamepadButton] slot —
/// a Vector2 action's gamepad fallback is a direct stick pick (see
/// `ControllerStickRow`), not a captured button, so it never goes through
/// this listening flow at all.
class CaptureTarget {
  const CaptureTarget(this.action, [this.direction, this.isGamepad = false]);

  final String action;
  final InputDirection? direction;
  final bool isGamepad;

  @override
  bool operator ==(Object other) =>
      other is CaptureTarget &&
      other.action == action &&
      other.direction == direction &&
      other.isGamepad == isGamepad;

  @override
  int get hashCode => Object.hash(action, direction, isGamepad);
}

/// Full-screen barrier + centered card — deliberately not `showDialog`, since
/// a `ModalRoute` binds Escape to dismiss by default, which would fight both
/// the rebind-capture flow's own "Escape cancels capture" convention and the
/// fact that `pause` is itself one of the rebindable actions.
class InputSetupOverlay extends StatelessWidget {
  const InputSetupOverlay({
    super.key,
    required this.plugin,
    required this.onClose,
  });

  final JustGameEditorPlugin plugin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black54),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _InputSetupPanelCard(plugin: plugin, onClose: onClose),
            ),
          ),
        ),
      ],
    );
  }
}

class _InputSetupPanelCard extends StatefulWidget {
  const _InputSetupPanelCard({required this.plugin, required this.onClose});

  final JustGameEditorPlugin plugin;
  final VoidCallback onClose;

  @override
  State<_InputSetupPanelCard> createState() => _InputSetupPanelCardState();
}

class _InputSetupPanelCardState extends State<_InputSetupPanelCard> {
  late InputActionSet _draft;

  /// A separate deep copy, snapshotted whenever [_draft] last matched what's
  /// actually on disk (on open, and again after every successful [_save]) —
  /// compared against [_draft] (via [_actionSetsEqual]) to decide whether
  /// the Save button should show at all. Deliberately not the same
  /// reference as [_draft]: mutating [_draft] in place must never also
  /// silently mutate this baseline.
  late InputActionSet _savedSnapshot;
  final FocusNode _captureFocusNode = FocusNode();
  CaptureTarget? _listening;
  String? _selectedMapId;
  String? _selectedAction;

  /// Polls live gamepad state while [_listening]?.isGamepad is true — see
  /// `_startListeningGamepad`. Gamepad events arrive via `just_gamepads`'
  /// `EventChannel`, entirely outside the widget tree, so they can't reuse
  /// `_handleCaptureKey`/`_handleCapturePointer`'s `Focus`/`Listener` path.
  Timer? _gamepadCaptureTimer;

  bool get _isDirty => !_actionSetsEqual(_draft, _savedSnapshot);

  @override
  void initState() {
    super.initState();
    _draft = _copyActionSet(widget.plugin.engine.actions.actionSet);
    _savedSnapshot = _copyActionSet(_draft);

    final mapIds = _draft.allMapIds;
    _selectedMapId = mapIds.isEmpty ? null : mapIds.first;
    if (_selectedMapId != null) {
      final actionsInMap = _actionsInMap(_selectedMapId!);
      _selectedAction = actionsInMap.isEmpty ? null : actionsInMap.first;
    }
  }

  /// [_draft.allActionKeys] (the developer's explicit drag-order, gap-filled
  /// for anything missing) filtered down to just [mapId] — the order Pane 2
  /// actually renders, and what `_reorderActionsInMap` reorders within.
  List<String> _actionsInMap(String mapId) => _draft.allActionKeys
      .where((key) => _draft.defs[key]?.mapId == mapId)
      .toList();

  @override
  void dispose() {
    _gamepadCaptureTimer?.cancel();
    _captureFocusNode.dispose();
    super.dispose();
  }

  // ── Deep copy (so edits stay a local draft until Save) ──────────────────

  static InputActionSet _copyActionSet(InputActionSet source) {
    return InputActionSet(
      {
        for (final entry in source.defs.entries)
          entry.key: _copyAction(entry.value),
      },
      List.of(source.mapOrder),
      List.of(source.actionOrder),
    );
  }

  static InputAction _copyAction(InputAction action) => InputAction(
    mapId: action.mapId,
    type: action.type,
    button: _copyBinding(action.button),
    vector2: _copyVector2(action.vector2),
  );

  static InputBinding _copyBinding(InputBinding binding) => InputBinding(
    keys: List.of(binding.keys),
    mouseButton: binding.mouseButton,
    gamepadButton: binding.gamepadButton,
    touch: binding.touch,
    touchPosition: binding.touchPosition,
  );

  static Vector2Binding _copyVector2(Vector2Binding vector2) => Vector2Binding(
    up: List.of(vector2.up),
    down: List.of(vector2.down),
    left: List.of(vector2.left),
    right: List.of(vector2.right),
    gamepadStick: vector2.gamepadStick,
    useMouseAim: vector2.useMouseAim,
  );

  // ── Deep equality (drives [_isDirty] / whether Save is shown) ────────────
  //
  // None of InputActionSet/InputAction/InputBinding/Vector2Binding override
  // `==`, so this can't just be `_draft == _savedSnapshot` — compared
  // field-by-field instead. Compares the gap-filled `allMapIds`/
  // `allActionKeys` (not the raw `mapOrder`/`actionOrder` lists) so a pure
  // reorder (which changes relative order, not membership) is correctly
  // detected as a change via `listEquals`' order-sensitivity, while a
  // display-order difference that's purely an artifact of gap-filling
  // (nothing actually moved) is not.

  static bool _actionSetsEqual(InputActionSet a, InputActionSet b) {
    if (!listEquals(a.allMapIds, b.allMapIds)) return false;
    if (!listEquals(a.allActionKeys, b.allActionKeys)) return false;
    if (a.defs.length != b.defs.length) return false;
    for (final entry in a.defs.entries) {
      final other = b.defs[entry.key];
      if (other == null || !_actionsEqual(entry.value, other)) return false;
    }
    return true;
  }

  static bool _actionsEqual(InputAction a, InputAction b) =>
      a.mapId == b.mapId &&
      a.type == b.type &&
      _bindingsEqual(a.button, b.button) &&
      _vector2sEqual(a.vector2, b.vector2);

  static bool _bindingsEqual(InputBinding a, InputBinding b) =>
      listEquals(a.keys, b.keys) &&
      a.mouseButton == b.mouseButton &&
      a.gamepadButton == b.gamepadButton &&
      a.touch == b.touch &&
      a.touchPosition == b.touchPosition;

  static bool _vector2sEqual(Vector2Binding a, Vector2Binding b) =>
      listEquals(a.up, b.up) &&
      listEquals(a.down, b.down) &&
      listEquals(a.left, b.left) &&
      listEquals(a.right, b.right) &&
      a.gamepadStick == b.gamepadStick &&
      a.useMouseAim == b.useMouseAim;

  // ── Selection ─────────────────────────────────────────────────────────────

  void _selectMap(String mapId) {
    if (_listening != null) _cancelListening();
    setState(() {
      _selectedMapId = mapId;
      final actionsInMap = _actionsInMap(mapId);
      _selectedAction = actionsInMap.isEmpty ? null : actionsInMap.first;
    });
  }

  void _selectAction(String action) {
    if (_listening != null) _cancelListening();
    setState(() => _selectedAction = action);
  }

  // ── Add / delete maps and actions ─────────────────────────────────────────

  Future<void> _addMap() async {
    final name = await promptSceneName(
      context,
      title: 'New Action Map',
      actionLabel: 'Create',
      validate: (value) {
        if (value.isEmpty) return 'Name required';
        if (_draft.allMapIds.contains(value)) {
          return 'A map named "$value" already exists';
        }
        return null;
      },
    );
    if (name == null || !mounted) return;
    setState(() {
      _draft.mapOrder.add(name);
      _selectedMapId = name;
      _selectedAction = null;
    });
    EditorMessenger.of(context).showSnackBar(
      const EditorSnackBarEntry(
        message: 'Map added',
        type: EditorSnackBarType.success,
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _deleteMap(String mapId) async {
    if (_listening != null && _draft.defs[_listening!.action]?.mapId == mapId) {
      _cancelListening();
    }
    final actionCount = _draft.defs.values
        .where((def) => def.mapId == mapId)
        .length;
    final message = actionCount == 0
        ? 'This deletes the empty map "$mapId". This cannot be undone.'
        : 'This deletes "$mapId" and its $actionCount '
              '${actionCount == 1 ? 'action' : 'actions'}. This cannot be '
              'undone.';
    final confirmed = await confirmDelete(
      context,
      title: 'Delete map?',
      message: message,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      final deletedActions = _draft.defs.entries
          .where((entry) => entry.value.mapId == mapId)
          .map((entry) => entry.key)
          .toSet();
      _draft.defs.removeWhere((_, def) => def.mapId == mapId);
      _draft.mapOrder.remove(mapId);
      _draft.actionOrder.removeWhere(deletedActions.contains);
      if (_selectedMapId == mapId) {
        final remaining = _draft.allMapIds;
        _selectedMapId = remaining.isEmpty ? null : remaining.first;
        _selectedAction = null;
        if (_selectedMapId != null) {
          final actionsInMap = _actionsInMap(_selectedMapId!);
          _selectedAction = actionsInMap.isEmpty ? null : actionsInMap.first;
        }
      }
    });
    EditorMessenger.of(context).showSnackBar(
      const EditorSnackBarEntry(
        message: 'Map deleted',
        type: EditorSnackBarType.success,
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _addAction() async {
    final mapId = _selectedMapId;
    if (mapId == null) return;
    final result = await promptNewAction(
      context,
      validateName: (value) {
        if (value.isEmpty) return 'Name required';
        if (_draft.defs.containsKey(value)) {
          return 'An action named "$value" already exists';
        }
        return null;
      },
    );
    if (result == null || !mounted) return;
    final (name, type) = result;
    setState(() {
      _draft.defs[name] = InputAction(mapId: mapId, type: type);
      _draft.actionOrder.add(name);
      _selectedAction = name;
    });
    EditorMessenger.of(context).showSnackBar(
      const EditorSnackBarEntry(
        message: 'Action added',
        type: EditorSnackBarType.success,
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _deleteAction(String action) async {
    if (_listening?.action == action) _cancelListening();
    final confirmed = await confirmDelete(
      context,
      title: 'Delete action?',
      message:
          'This deletes "${prettifyActionName(action)}" and all its '
          'bindings. This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _draft.defs.remove(action);
      _draft.actionOrder.remove(action);
      if (_selectedAction == action) _selectedAction = null;
    });
    EditorMessenger.of(context).showSnackBar(
      const EditorSnackBarEntry(
        message: 'Action deleted',
        type: EditorSnackBarType.success,
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  // ── Reordering ────────────────────────────────────────────────────────────
  //
  // Both panes wire `ReorderableListView.onReorderItem` (not the deprecated
  // `onReorder`) — its `newIndex` already accounts for the dragged item's
  // own removal, so a plain `removeAt`/`insert` pair is correct as-is with
  // no further index adjustment needed.

  void _reorderMaps(int oldIndex, int newIndex) {
    if (_listening != null) _cancelListening();
    setState(() {
      final ids = _draft.allMapIds;
      final id = ids.removeAt(oldIndex);
      ids.insert(newIndex, id);
      _draft.mapOrder
        ..clear()
        ..addAll(ids);
    });
  }

  /// Reorders only the actions currently displayed for [mapId] (Pane 2 is
  /// always filtered to one map) — splices the reordered subsequence back
  /// into their original absolute positions within the *global*
  /// `actionOrder`, so every other map's actions' relative order is left
  /// completely undisturbed.
  void _reorderActionsInMap(String mapId, int oldIndex, int newIndex) {
    if (_listening != null) _cancelListening();
    setState(() {
      final full = _draft.allActionKeys;
      final slotIndices = <int>[
        for (var i = 0; i < full.length; i++)
          if (_draft.defs[full[i]]?.mapId == mapId) i,
      ];
      final inMap = [for (final i in slotIndices) full[i]];

      final moved = inMap.removeAt(oldIndex);
      inMap.insert(newIndex, moved);

      for (var i = 0; i < slotIndices.length; i++) {
        full[slotIndices[i]] = inMap[i];
      }
      _draft.actionOrder
        ..clear()
        ..addAll(full);
    });
  }

  // ── Key/mouse capture ─────────────────────────────────────────────────────

  void _startListening(String action, {InputDirection? direction}) {
    _gamepadCaptureTimer?.cancel();
    _gamepadCaptureTimer = null;
    setState(() => _listening = CaptureTarget(action, direction));
    _captureFocusNode.requestFocus();
  }

  void _cancelListening() {
    _gamepadCaptureTimer?.cancel();
    _gamepadCaptureTimer = null;
    setState(() => _listening = null);
  }

  // ── Gamepad capture ────────────────────────────────────────────────────────

  /// Starts "press any gamepad button" capture for [action] — polls live
  /// controller state on a short timer rather than reusing the
  /// `Focus`/`Listener` key/mouse path (see [_gamepadCaptureTimer]'s doc
  /// comment). Polls `isButtonDown` (level, not `isButtonPressed`'s
  /// one-frame edge) deliberately: this timer's ~60Hz cadence isn't
  /// synchronized with the engine's own frame loop that drives
  /// `ControllerInput`'s edge detection, so relying on a single-frame press
  /// edge risks missing it between polls — a held-down level is guaranteed
  /// to be caught on the very next poll and stays true for the whole hold,
  /// with no such race.
  void _startListeningGamepad(String action) {
    _gamepadCaptureTimer?.cancel();
    setState(() => _listening = CaptureTarget(action, null, true));
    _captureFocusNode.requestFocus();
    _gamepadCaptureTimer = Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      final controller = widget.plugin.engine.input.controller;
      for (var button = 0; button <= GamepadButton.dpadRight; button++) {
        if (controller.isButtonDown(button)) {
          _applyGamepadButton(action, button);
          return;
        }
      }
    });
  }

  void _applyGamepadButton(String action, int button) {
    _gamepadCaptureTimer?.cancel();
    _gamepadCaptureTimer = null;
    setState(() {
      final current = _draft.defs[action];
      if (current != null) {
        _draft.defs[action] = InputAction(
          mapId: current.mapId,
          type: current.type,
          button: InputBinding(
            keys: current.button.keys,
            mouseButton: current.button.mouseButton,
            gamepadButton: button,
            touch: current.button.touch,
            touchPosition: current.button.touchPosition,
          ),
          vector2: current.vector2,
        );
      }
      _listening = null;
    });
  }

  void _removeGamepadButton(String action) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: InputBinding(
          keys: current.button.keys,
          mouseButton: current.button.mouseButton,
          gamepadButton: null,
          touch: current.button.touch,
          touchPosition: current.button.touchPosition,
        ),
        vector2: current.vector2,
      );
    });
  }

  /// No capture/listening step needed — unlike a button, the developer is
  /// picking from exactly two known options with no ambiguity to resolve.
  void _setGamepadStick(String action, GamepadStick? stick) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      final v = current.vector2;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: current.button,
        vector2: Vector2Binding(
          up: v.up,
          down: v.down,
          left: v.left,
          right: v.right,
          gamepadStick: stick,
          useMouseAim: v.useMouseAim,
        ),
      );
    });
  }

  void _setUseMouseAim(String action, bool enabled) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      final v = current.vector2;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: current.button,
        vector2: Vector2Binding(
          up: v.up,
          down: v.down,
          left: v.left,
          right: v.right,
          gamepadStick: v.gamepadStick,
          useMouseAim: enabled,
        ),
      );
    });
  }

  KeyEventResult _handleCaptureKey(FocusNode node, KeyEvent event) {
    final target = _listening;
    if (target == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelListening();
      return KeyEventResult.handled;
    }
    // Gamepad capture is exclusively driven by `_gamepadCaptureTimer`
    // polling `ControllerInput`, not by keyboard events — swallow any
    // non-Escape key so it isn't misinterpreted as a keyboard binding while
    // gamepad capture is in progress.
    if (target.isGamepad) return KeyEventResult.handled;
    setState(() {
      final current = _draft.defs[target.action];
      if (current == null) {
        _listening = null;
        return;
      }
      if (target.direction == null) {
        if (!current.button.keys.contains(event.logicalKey)) {
          _draft.defs[target.action] = InputAction(
            mapId: current.mapId,
            type: current.type,
            button: InputBinding(
              keys: [...current.button.keys, event.logicalKey],
              mouseButton: current.button.mouseButton,
              gamepadButton: current.button.gamepadButton,
              touch: current.button.touch,
              touchPosition: current.button.touchPosition,
            ),
            vector2: current.vector2,
          );
        }
      } else {
        final v = current.vector2;
        final existing = _keysForDirection(v, target.direction!);
        if (!existing.contains(event.logicalKey)) {
          _draft.defs[target.action] = InputAction(
            mapId: current.mapId,
            type: current.type,
            button: current.button,
            vector2: _withDirection(v, target.direction!, [
              ...existing,
              event.logicalKey,
            ]),
          );
        }
      }
      _listening = null;
    });
    return KeyEventResult.handled;
  }

  void _handleCapturePointer(PointerDownEvent event) {
    final target = _listening;
    // Vector2Binding has no mouse field — a click while capturing a
    // direction has nothing sensible to do, so it's ignored outright rather
    // than falling through to undefined behavior.
    if (target == null || target.direction != null) return;
    int? button;
    for (var i = 0; i < 3; i++) {
      if (event.buttons & (1 << i) != 0) {
        button = i;
        break;
      }
    }
    if (button == null) return;
    setState(() {
      final current = _draft.defs[target.action];
      if (current == null) {
        _listening = null;
        return;
      }
      _draft.defs[target.action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: InputBinding(
          keys: current.button.keys,
          mouseButton: button,
          gamepadButton: current.button.gamepadButton,
          touch: current.button.touch,
          touchPosition: current.button.touchPosition,
        ),
        vector2: current.vector2,
      );
      _listening = null;
    });
  }

  static List<LogicalKeyboardKey> _keysForDirection(
    Vector2Binding v,
    InputDirection direction,
  ) => switch (direction) {
    InputDirection.up => v.up,
    InputDirection.down => v.down,
    InputDirection.left => v.left,
    InputDirection.right => v.right,
  };

  static Vector2Binding _withDirection(
    Vector2Binding v,
    InputDirection direction,
    List<LogicalKeyboardKey> keys,
  ) => switch (direction) {
    InputDirection.up => Vector2Binding(
      up: keys,
      down: v.down,
      left: v.left,
      right: v.right,
      gamepadStick: v.gamepadStick,
      useMouseAim: v.useMouseAim,
    ),
    InputDirection.down => Vector2Binding(
      up: v.up,
      down: keys,
      left: v.left,
      right: v.right,
      gamepadStick: v.gamepadStick,
      useMouseAim: v.useMouseAim,
    ),
    InputDirection.left => Vector2Binding(
      up: v.up,
      down: v.down,
      left: keys,
      right: v.right,
      gamepadStick: v.gamepadStick,
      useMouseAim: v.useMouseAim,
    ),
    InputDirection.right => Vector2Binding(
      up: v.up,
      down: v.down,
      left: v.left,
      right: keys,
      gamepadStick: v.gamepadStick,
      useMouseAim: v.useMouseAim,
    ),
  };

  // ── Editing helpers (called from the properties pane) ────────────────────

  void _removeKey(
    String action,
    LogicalKeyboardKey key, {
    InputDirection? direction,
  }) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      if (direction == null) {
        _draft.defs[action] = InputAction(
          mapId: current.mapId,
          type: current.type,
          button: InputBinding(
            keys: current.button.keys.where((k) => k != key).toList(),
            mouseButton: current.button.mouseButton,
            gamepadButton: current.button.gamepadButton,
            touch: current.button.touch,
            touchPosition: current.button.touchPosition,
          ),
          vector2: current.vector2,
        );
      } else {
        final v = current.vector2;
        final remaining = _keysForDirection(
          v,
          direction,
        ).where((k) => k != key).toList();
        _draft.defs[action] = InputAction(
          mapId: current.mapId,
          type: current.type,
          button: current.button,
          vector2: _withDirection(v, direction, remaining),
        );
      }
    });
  }

  void _removeMouseButton(String action) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: InputBinding(
          keys: current.button.keys,
          mouseButton: null,
          gamepadButton: current.button.gamepadButton,
          touch: current.button.touch,
          touchPosition: current.button.touchPosition,
        ),
        vector2: current.vector2,
      );
    });
  }

  /// Toggles whether [action] shows an on-screen button — `position: null`
  /// turns it off; enabling without an explicit position drops a fresh
  /// button at screen center for the developer to drag into place.
  void _setTouchEnabled(String action, {Alignment? position}) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: InputBinding(
          keys: current.button.keys,
          mouseButton: current.button.mouseButton,
          gamepadButton: current.button.gamepadButton,
          touch: position == null
              ? TouchBindingKind.none
              : TouchBindingKind.onScreenButton,
          touchPosition: position,
        ),
        vector2: current.vector2,
      );
    });
  }

  void _moveTouchButton(String action, Alignment position) {
    setState(() {
      final current = _draft.defs[action];
      if (current == null) return;
      _draft.defs[action] = InputAction(
        mapId: current.mapId,
        type: current.type,
        button: InputBinding(
          keys: current.button.keys,
          mouseButton: current.button.mouseButton,
          gamepadButton: current.button.gamepadButton,
          touch: TouchBindingKind.onScreenButton,
          touchPosition: position,
        ),
        vector2: current.vector2,
      );
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  /// Formats [findBindingConflicts]' output into one human-readable line per
  /// conflict, e.g. `'R is bound to both Reload and Skill Spit (player)'` —
  /// reuses this file's own key/mouse/gamepad label helpers so the wording
  /// matches what the properties pane already shows for each binding type.
  List<String> _describeBindingConflicts(List<BindingConflict> conflicts) {
    final controller = widget.plugin.engine.input.controller;
    return conflicts.map((c) {
      final names = c.actionIds.map(prettifyActionName).join(' and ');
      final input = switch (c.source) {
        ConflictSource.key => keyLabel(c.key!),
        ConflictSource.mouseButton => mouseButtonLabel(c.mouseButton!),
        ConflictSource.gamepadButton => gamepadButtonLabelForController(
          controller,
          c.gamepadButton!,
        ),
      };
      return '$input is bound to both $names (${c.mapId})';
    }).toList();
  }

  Future<void> _save() async {
    final conflicts = findBindingConflicts(_draft);
    if (conflicts.isNotEmpty) {
      final proceed = await confirmSaveWithBindingConflicts(
        context,
        conflictDescriptions: _describeBindingConflicts(conflicts),
      );
      if (!proceed) return;
    }
    if (!mounted) return;
    await InputBindingsFileGenerator.writeBindings(_draft);
    widget.plugin.engine.actions.applyActions(_draft);
    if (!mounted) return;
    // Re-baseline so the Save button (only shown while _isDirty) disappears
    // again immediately — a fresh copy, not just reassigning the reference,
    // so subsequent edits to _draft can't also silently mutate this baseline.
    setState(() => _savedSnapshot = _copyActionSet(_draft));
    EditorMessenger.of(context).showSnackBar(
      const EditorSnackBarEntry(
        message: 'Input bindings saved',
        type: EditorSnackBarType.success,
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = widget.plugin.scope.prefs.settings.value;
    final accent = settings.themeColor;

    final mapIds = _draft.allMapIds;
    final actionsInSelectedMap = _selectedMapId == null
        ? const <String>[]
        : _actionsInMap(_selectedMapId!);
    final selectedDef = _selectedAction == null
        ? null
        : _draft.defs[_selectedAction];

    return Material(
      color: Colors.transparent,
      child: Focus(
        focusNode: _captureFocusNode,
        onKeyEvent: _handleCaptureKey,
        child: Listener(
          onPointerDown: _handleCapturePointer,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF41B1B1B),
              borderRadius: BorderRadius.circular(settings.cornerRadius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(accent),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 130,
                        child: _ActionMapListPane(
                          mapIds: mapIds,
                          selectedMapId: _selectedMapId,
                          onSelect: _selectMap,
                          onAdd: _addMap,
                          onDelete: _deleteMap,
                          onReorder: _reorderMaps,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      SizedBox(
                        width: 180,
                        child: _ActionListPane(
                          actions: actionsInSelectedMap,
                          defs: _draft.defs,
                          selectedAction: _selectedAction,
                          onSelect: _selectAction,
                          onAdd: _selectedMapId == null ? null : _addAction,
                          onDelete: _deleteAction,
                          onReorder: _selectedMapId == null
                              ? null
                              : (oldIndex, newIndex) => _reorderActionsInMap(
                                  _selectedMapId!,
                                  oldIndex,
                                  newIndex,
                                ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      Expanded(
                        child: _selectedAction == null || selectedDef == null
                            ? const Center(
                                child: Text(
                                  'No action selected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: EditorTheme.textMuted,
                                  ),
                                ),
                              )
                            : ActionPropertiesPane(
                                action: _selectedAction!,
                                def: selectedDef,
                                allDefs: _draft.defs,
                                listening: _listening,
                                controller:
                                    widget.plugin.engine.input.controller,
                                onStartListening: _startListening,
                                onCancelListening: _cancelListening,
                                onRemoveKey: _removeKey,
                                onRemoveMouseButton: _removeMouseButton,
                                onToggleTouch: _setTouchEnabled,
                                onMoveTouch: _moveTouchButton,
                                onStartListeningGamepad: _startListeningGamepad,
                                onRemoveGamepadButton: _removeGamepadButton,
                                onSetGamepadStick: _setGamepadStick,
                                onSetUseMouseAim: _setUseMouseAim,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.keyboard_alt_outlined, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Input Setup',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EditorTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Action Maps → Actions → Properties. Configure every '
                  'platform for an action in one place.',
                  style: TextStyle(fontSize: 9, color: EditorTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_isDirty)
            TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              child: const Text('Save'),
            ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
            color: EditorTheme.textSecondary,
            iconSize: 16,
            splashRadius: 16,
          ),
        ],
      ),
    );
  }
}

// ── Pane 1: Action Maps ─────────────────────────────────────────────────────────

class _ActionMapListPane extends StatelessWidget {
  const _ActionMapListPane({
    required this.mapIds,
    required this.selectedMapId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
  });

  final List<String> mapIds;
  final String? selectedMapId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PaneHeader(label: 'Action Maps', onAdd: onAdd),
        Expanded(
          child: mapIds.isEmpty
              ? const SizedBox.shrink()
              : ReorderableListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  onReorderItem: onReorder,
                  children: <Widget>[
                    for (final mapId in mapIds)
                      _SelectableRow(
                        key: ValueKey(mapId),
                        label: prettifyActionName(mapId),
                        isSelected: mapId == selectedMapId,
                        onTap: () => onSelect(mapId),
                        onDelete: () => onDelete(mapId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Pane 2: Actions ─────────────────────────────────────────────────────────────

class _ActionListPane extends StatelessWidget {
  const _ActionListPane({
    required this.actions,
    required this.defs,
    required this.selectedAction,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
  });

  final List<String> actions;
  final Map<String, InputAction> defs;
  final String? selectedAction;
  final ValueChanged<String> onSelect;

  /// `null` disables the "+" (no map selected to add into).
  final VoidCallback? onAdd;
  final ValueChanged<String> onDelete;

  /// `null` disables reordering (no map selected).
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PaneHeader(label: 'Actions', onAdd: onAdd),
        Expanded(
          child: actions.isEmpty
              ? const SizedBox.shrink()
              : ReorderableListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  onReorderItem: onReorder ?? (_, _) {},
                  buildDefaultDragHandles: onReorder != null,
                  children: <Widget>[
                    for (final action in actions)
                      _SelectableRow(
                        key: ValueKey(action),
                        label: prettifyActionName(action),
                        icon: defs[action]?.type == ActionType.vector2
                            ? Icons.open_with_rounded
                            : Icons.touch_app_rounded,
                        isSelected: action == selectedAction,
                        onTap: () => onSelect(action),
                        onDelete: () => onDelete(action),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Shared "<label>" + "+" header for Panes 1/2 — matches
/// `scene_tree_panel.dart`'s header `IconButton` styling
/// (`Icons.add_rounded`, tight `BoxConstraints`, `EditorTheme.primary`).
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.label, required this.onAdd});

  final String label;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: EditorTheme.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            iconSize: 15,
            color: onAdd == null ? EditorTheme.textMuted : EditorTheme.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}

/// Shared selected-row idiom for Panes 1/2 — matches
/// `scene_tree_panel.dart`'s `_EntityTreeRow` styling (`InkWell` →
/// `AnimatedContainer`, `EditorTheme.selectionBg` when selected).
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.onDelete,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  /// `null` hides the delete affordance entirely.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: isSelected ? EditorTheme.selectionBg : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: <Widget>[
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected ? EditorTheme.primary : EditorTheme.textMuted,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? EditorTheme.textPrimary
                      : EditorTheme.textSecondary,
                ),
              ),
            ),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 13,
                    color: EditorTheme.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared chip/capture widgets (used by Pane 3, in overlay_input_setup_properties.part.dart) ──

String keyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  return label.isEmpty ? (key.debugName ?? '?') : label;
}

String mouseButtonLabel(int button) => switch (button) {
  0 => 'LMB',
  1 => 'RMB',
  2 => 'MMB',
  _ => 'MB$button',
};

class BindingChip extends StatelessWidget {
  const BindingChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: EditorTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 12,
              color: EditorTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class ListeningChip extends StatelessWidget {
  const ListeningChip({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCancel,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: EditorTheme.primaryMuted.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: EditorTheme.primaryMuted),
        ),
        child: const Text(
          'Listening… (Esc to cancel)',
          style: TextStyle(fontSize: 9, color: EditorTheme.textPrimary),
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

/// Turns a camelCase action/map name into a readable label, e.g.
/// `skillErraticDash` -> `Skill Erratic Dash`.
String prettifyActionName(String name) {
  final buffer = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (i == 0) {
      buffer.write(char.toUpperCase());
    } else if (isUpper) {
      buffer
        ..write(' ')
        ..write(char);
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
