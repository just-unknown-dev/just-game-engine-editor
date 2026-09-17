part of 'editor_overlay.dart';

/// Actions that get a static "how this works on mobile" note instead of the
/// generic draggable-on-screen-button UI — `interact` renders as a
/// context-sensitive tap prompt near whatever's interactable, not a fixed
/// button, so there's nothing to place. `move` doesn't need listing here at
/// all since it's excluded by `ActionType.vector2` (the always-on virtual
/// joystick), not by name.
const List<String> _touchInfoOnlyActions = <String>['interact'];

// ── Pane 3: Action Properties ───────────────────────────────────────────────────

class _ActionPropertiesPane extends StatelessWidget {
  const _ActionPropertiesPane({
    required this.action,
    required this.def,
    required this.allDefs,
    required this.listening,
    required this.controller,
    required this.onStartListening,
    required this.onCancelListening,
    required this.onRemoveKey,
    required this.onRemoveMouseButton,
    required this.onToggleTouch,
    required this.onMoveTouch,
    required this.onStartListeningGamepad,
    required this.onRemoveGamepadButton,
    required this.onSetGamepadStick,
    required this.onSetUseMouseAim,
  });

  final String action;
  final InputAction def;
  final Map<String, InputAction> allDefs;
  final _CaptureTarget? listening;

  /// Live controller state — read for the currently-active gamepad's brand
  /// (for label glyphs) and polled by `_gamepadCaptureTimer` during capture;
  /// see `overlay_input_setup_panel.part.dart`.
  final ControllerInput controller;

  final void Function(String action, {_Direction? direction}) onStartListening;
  final VoidCallback onCancelListening;
  final void Function(
    String action,
    LogicalKeyboardKey key, {
    _Direction? direction,
  })
  onRemoveKey;
  final ValueChanged<String> onRemoveMouseButton;
  final void Function(String action, {Alignment? position}) onToggleTouch;
  final void Function(String action, Alignment position) onMoveTouch;
  final ValueChanged<String> onStartListeningGamepad;
  final ValueChanged<String> onRemoveGamepadButton;
  final void Function(String action, GamepadStick? stick) onSetGamepadStick;
  final void Function(String action, bool enabled) onSetUseMouseAim;

  bool _isListening(_Direction? direction) =>
      listening == _CaptureTarget(action, direction);

  bool get _isListeningGamepad =>
      listening == _CaptureTarget(action, null, true);

  @override
  Widget build(BuildContext context) {
    final isTouchEnabled =
        def.type == ActionType.button &&
        def.button.touch == TouchBindingKind.onScreenButton &&
        def.button.touchPosition != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _prettifyActionName(action),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: EditorTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: <Widget>[
              _InfoChip(
                label: def.type == ActionType.vector2 ? 'Vector 2' : 'Button',
              ),
              _InfoChip(label: _prettifyActionName(def.mapId)),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionHeader('Desktop / Web'),
          const SizedBox(height: 6),
          if (def.type == ActionType.button)
            _ActionBindingRow(
              binding: def.button,
              isListening: _isListening(null),
              onStartListening: () => onStartListening(action),
              onCancelListening: onCancelListening,
              onRemoveKey: (key) => onRemoveKey(action, key),
              onRemoveMouseButton: () => onRemoveMouseButton(action),
            )
          else ...<Widget>[
            _DirectionBindingRow(
              label: 'Up',
              keys: def.vector2.up,
              isListening: _isListening(_Direction.up),
              onStartListening: () =>
                  onStartListening(action, direction: _Direction.up),
              onCancelListening: onCancelListening,
              onRemoveKey: (key) =>
                  onRemoveKey(action, key, direction: _Direction.up),
            ),
            _DirectionBindingRow(
              label: 'Down',
              keys: def.vector2.down,
              isListening: _isListening(_Direction.down),
              onStartListening: () =>
                  onStartListening(action, direction: _Direction.down),
              onCancelListening: onCancelListening,
              onRemoveKey: (key) =>
                  onRemoveKey(action, key, direction: _Direction.down),
            ),
            _DirectionBindingRow(
              label: 'Left',
              keys: def.vector2.left,
              isListening: _isListening(_Direction.left),
              onStartListening: () =>
                  onStartListening(action, direction: _Direction.left),
              onCancelListening: onCancelListening,
              onRemoveKey: (key) =>
                  onRemoveKey(action, key, direction: _Direction.left),
            ),
            _DirectionBindingRow(
              label: 'Right',
              keys: def.vector2.right,
              isListening: _isListening(_Direction.right),
              onStartListening: () =>
                  onStartListening(action, direction: _Direction.right),
              onCancelListening: onCancelListening,
              onRemoveKey: (key) =>
                  onRemoveKey(action, key, direction: _Direction.right),
            ),
            const SizedBox(height: 10),
            _MouseAimToggleRow(
              enabled: def.vector2.useMouseAim,
              onChanged: (enabled) => onSetUseMouseAim(action, enabled),
            ),
          ],
          const SizedBox(height: 18),
          const _SectionHeader('Mobile'),
          const SizedBox(height: 6),
          if (def.type == ActionType.vector2)
            const _MobileInfoRow(
              text:
                  'Uses the always-on virtual joystick — no separate setup '
                  'needed.',
            )
          else if (_touchInfoOnlyActions.contains(action))
            const _MobileInfoRow(
              text: 'Shown as a tap-to-interact prompt, not a draggable button.',
            )
          else ...<Widget>[
            _MobileToggleRow(
              enabled: isTouchEnabled,
              onChanged: (enabled) => onToggleTouch(
                action,
                position: enabled
                    ? (def.button.touchPosition ?? Alignment.center)
                    : null,
              ),
            ),
            if (isTouchEnabled) ...<Widget>[
              const SizedBox(height: 8),
              _TouchLayoutPreview(
                selectedAction: action,
                allDefs: allDefs,
                onMove: (position) => onMoveTouch(action, position),
              ),
            ],
          ],
          const SizedBox(height: 18),
          const _SectionHeader('Controller'),
          const SizedBox(height: 6),
          _ControllerDetectedRow(controller: controller),
          const SizedBox(height: 8),
          if (def.type == ActionType.button)
            _ControllerButtonRow(
              binding: def.button,
              controller: controller,
              isListening: _isListeningGamepad,
              onStartListening: () => onStartListeningGamepad(action),
              onCancelListening: onCancelListening,
              onRemove: () => onRemoveGamepadButton(action),
            )
          else
            _ControllerStickRow(
              selected: def.vector2.gamepadStick,
              onSelect: (stick) => onSetGamepadStick(action, stick),
            ),
        ],
      ),
    );
  }
}

// ── Desktop / Web ────────────────────────────────────────────────────────────────

/// Shared chip row for one key list (+ optional mouse button) — the
/// building block both the whole-action binding row (button-type actions)
/// and each per-direction row (vector2-type actions) render through.
class _KeyChipRow extends StatelessWidget {
  const _KeyChipRow({
    required this.keys,
    required this.mouseButton,
    required this.isListening,
    required this.onStartListening,
    required this.onCancelListening,
    required this.onRemoveKey,
    this.onRemoveMouseButton,
  });

  final List<LogicalKeyboardKey> keys;
  final int? mouseButton;
  final bool isListening;
  final VoidCallback onStartListening;
  final VoidCallback onCancelListening;
  final ValueChanged<LogicalKeyboardKey> onRemoveKey;
  final VoidCallback? onRemoveMouseButton;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final key in keys)
          _BindingChip(label: _keyLabel(key), onRemove: () => onRemoveKey(key)),
        if (mouseButton != null && onRemoveMouseButton != null)
          _BindingChip(
            label: _mouseButtonLabel(mouseButton!),
            onRemove: onRemoveMouseButton!,
          ),
        if (isListening)
          _ListeningChip(onCancel: onCancelListening)
        else
          InkWell(
            onTap: onStartListening,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 13,
                color: EditorTheme.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionBindingRow extends StatelessWidget {
  const _ActionBindingRow({
    required this.binding,
    required this.isListening,
    required this.onStartListening,
    required this.onCancelListening,
    required this.onRemoveKey,
    required this.onRemoveMouseButton,
  });

  final InputBinding binding;
  final bool isListening;
  final VoidCallback onStartListening;
  final VoidCallback onCancelListening;
  final ValueChanged<LogicalKeyboardKey> onRemoveKey;
  final VoidCallback onRemoveMouseButton;

  @override
  Widget build(BuildContext context) {
    return _KeyChipRow(
      keys: binding.keys,
      mouseButton: binding.mouseButton,
      isListening: isListening,
      onStartListening: onStartListening,
      onCancelListening: onCancelListening,
      onRemoveKey: onRemoveKey,
      onRemoveMouseButton: onRemoveMouseButton,
    );
  }
}

class _DirectionBindingRow extends StatelessWidget {
  const _DirectionBindingRow({
    required this.label,
    required this.keys,
    required this.isListening,
    required this.onStartListening,
    required this.onCancelListening,
    required this.onRemoveKey,
  });

  final String label;
  final List<LogicalKeyboardKey> keys;
  final bool isListening;
  final VoidCallback onStartListening;
  final VoidCallback onCancelListening;
  final ValueChanged<LogicalKeyboardKey> onRemoveKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _KeyChipRow(
              keys: keys,
              mouseButton: null,
              isListening: isListening,
              onStartListening: onStartListening,
              onCancelListening: onCancelListening,
              onRemoveKey: onRemoveKey,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile ────────────────────────────────────────────────────────────────────────

class _MobileInfoRow extends StatelessWidget {
  const _MobileInfoRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: EditorTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 10, color: EditorTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileToggleRow extends StatelessWidget {
  const _MobileToggleRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Switch(
          value: enabled,
          onChanged: onChanged,
          activeThumbColor: EditorTheme.primary,
        ),
        const SizedBox(width: 4),
        Text(
          enabled ? 'On-screen button enabled' : 'On-screen button disabled',
          style: const TextStyle(fontSize: 10, color: EditorTheme.textSecondary),
        ),
      ],
    );
  }
}

/// Desktop/Web-section toggle for [Vector2Binding.useMouseAim] — only
/// meaningful for a mouse-driven action like `aim` (not `move`, which has no
/// sensible "point the cursor to move" interpretation, but nothing stops a
/// developer from enabling it on any Vector2 action). Deliberately not
/// mutually exclusive with [gamepadStick] in the Controller section below —
/// `resolveAimDirection` (`lib/game/systems/aim_direction.dart`) treats
/// mouse as the lowest-priority fallback after the virtual joystick and
/// gamepad stick, so having both configured is normal, not a conflict.
class _MouseAimToggleRow extends StatelessWidget {
  const _MouseAimToggleRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Switch(
          value: enabled,
          onChanged: onChanged,
          activeThumbColor: EditorTheme.primary,
        ),
        const SizedBox(width: 4),
        Text(
          enabled ? 'Mouse aim enabled' : 'Mouse aim disabled',
          style: const TextStyle(fontSize: 10, color: EditorTheme.textSecondary),
        ),
      ],
    );
  }
}

/// A phone-screen-shaped preview: every other enabled on-screen button shows
/// as a dimmed, non-interactive dot for spatial context, while the selected
/// action's own dot is fully opaque — tap or drag anywhere in the box to
/// place it.
class _TouchLayoutPreview extends StatelessWidget {
  const _TouchLayoutPreview({
    required this.selectedAction,
    required this.allDefs,
    required this.onMove,
  });

  final String selectedAction;
  final Map<String, InputAction> allDefs;
  final ValueChanged<Alignment> onMove;

  @override
  Widget build(BuildContext context) {
    final selectedPosition = allDefs[selectedAction]?.button.touchPosition;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          void handleLocal(Offset local) {
            final dx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
            final dy = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
            onMove(Alignment(dx, dy));
          }

          return GestureDetector(
            onPanUpdate: (details) => handleLocal(details.localPosition),
            onTapDown: (details) => handleLocal(details.localPosition),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Stack(
                children: <Widget>[
                  for (final entry in allDefs.entries)
                    if (entry.key != selectedAction &&
                        entry.value.type == ActionType.button &&
                        entry.value.button.touch ==
                            TouchBindingKind.onScreenButton &&
                        entry.value.button.touchPosition != null)
                      IgnorePointer(
                        child: Align(
                          alignment: entry.value.button.touchPosition!,
                          child: _TouchDot(
                            label: _prettifyActionName(entry.key),
                            dimmed: true,
                          ),
                        ),
                      ),
                  if (selectedPosition != null)
                    IgnorePointer(
                      child: Align(
                        alignment: selectedPosition,
                        child: _TouchDot(
                          label: _prettifyActionName(selectedAction),
                          dimmed: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TouchDot extends StatelessWidget {
  const _TouchDot({required this.label, required this.dimmed});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: dimmed
            ? Colors.white.withValues(alpha: 0.08)
            : EditorTheme.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dimmed
              ? Colors.white.withValues(alpha: 0.15)
              : EditorTheme.primary,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: dimmed ? EditorTheme.textMuted : Colors.white,
        ),
      ),
    );
  }
}

// ── Controller ───────────────────────────────────────────────────────────────────

/// Shows which physical controller (if any) is currently detected —
/// [ControllerInput.activeGamepadName]/`isConnected`, refreshed on its own
/// short timer rather than relying on this pane's own rebuild cycle (which
/// otherwise only happens on selection changes, capture, or Save), since a
/// developer plugging in a controller wants to see it appear here
/// immediately without needing to touch anything else in the panel first —
/// the same reasoning `_gamepadCaptureTimer` already uses for capture.
class _ControllerDetectedRow extends StatefulWidget {
  const _ControllerDetectedRow({required this.controller});

  final ControllerInput controller;

  @override
  State<_ControllerDetectedRow> createState() => _ControllerDetectedRowState();
}

class _ControllerDetectedRowState extends State<_ControllerDetectedRow> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.controller.isConnected;
    final name = widget.controller.activeGamepadName;
    final text = isConnected
        ? (name == null || name.isEmpty ? 'Controller detected' : name)
        : 'No controller detected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isConnected
                ? Icons.sports_esports_rounded
                : Icons.sports_esports_outlined,
            size: 13,
            color: isConnected ? EditorTheme.primary : EditorTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isConnected ? FontWeight.w600 : FontWeight.w400,
                color: isConnected
                    ? EditorTheme.textPrimary
                    : EditorTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Button-action gamepad binding: a chip for the currently-bound button (if
/// any, brand-labeled via [ControllerInput.activeGamepadType]) plus a "+" to
/// capture the next gamepad button pressed — mirrors [_ActionBindingRow]'s
/// shape but drives capture through `_gamepadCaptureTimer` instead of the
/// `Focus`/`Listener` key/mouse path, since gamepad events never reach the
/// widget tree at all (see that timer's doc comment).
class _ControllerButtonRow extends StatelessWidget {
  const _ControllerButtonRow({
    required this.binding,
    required this.controller,
    required this.isListening,
    required this.onStartListening,
    required this.onCancelListening,
    required this.onRemove,
  });

  final InputBinding binding;
  final ControllerInput controller;
  final bool isListening;
  final VoidCallback onStartListening;
  final VoidCallback onCancelListening;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bound = binding.gamepadButton;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (bound != null)
          _BindingChip(
            label: gamepadButtonLabelForController(controller, bound),
            onRemove: onRemove,
          ),
        if (isListening)
          _ListeningChip(onCancel: onCancelListening)
        else
          InkWell(
            onTap: onStartListening,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 13,
                color: EditorTheme.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Vector2-action gamepad fallback: pick which stick (if any) drives this
/// action when no bound key is held — a direct three-way choice, not a
/// capture flow, since there's no ambiguity to resolve (unlike a button
/// press, "left stick" vs. "right stick" are exactly two known options).
class _ControllerStickRow extends StatelessWidget {
  const _ControllerStickRow({required this.selected, required this.onSelect});

  final GamepadStick? selected;
  final ValueChanged<GamepadStick?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _StickChoiceChip(
          label: 'None',
          isSelected: selected == null,
          onTap: () => onSelect(null),
        ),
        _StickChoiceChip(
          label: gamepadStickLabel(GamepadStick.left),
          isSelected: selected == GamepadStick.left,
          onTap: () => onSelect(GamepadStick.left),
        ),
        _StickChoiceChip(
          label: gamepadStickLabel(GamepadStick.right),
          isSelected: selected == GamepadStick.right,
          onTap: () => onSelect(GamepadStick.right),
        ),
      ],
    );
  }
}

class _StickChoiceChip extends StatelessWidget {
  const _StickChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? EditorTheme.primaryMuted.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? EditorTheme.primaryMuted
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isSelected ? EditorTheme.textPrimary : EditorTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Small shared bits ─────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          color: EditorTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: EditorTheme.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }
}
