import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:just_editor_core/host.dart';
import 'transform_toolbar.dart';

/// What a right-click on the Gizmos button slides out, for the editor's
/// mode now ([mode]): its gizmos shown or hidden, each kind on or off, and
/// the ways back — every kind, the mode as it starts — or the same in
/// every mode. The other modes keep their own.
class GizmoMenu extends StatefulWidget {
  const GizmoMenu({
    super.key,
    required this.scope,
    required this.settings,
    required this.mode,
    required this.onClose,
  });

  final EditorScope scope;
  final OverlayUiSettings settings;

  /// The mode whose gizmos it sets.
  final GizmoMode mode;

  /// Puts it away: Esc, or the bar's click elsewhere.
  final VoidCallback onClose;

  /// How wide it stands.
  static const double width = 236;

  @override
  State<GizmoMenu> createState() => _GizmoMenuState();
}

class _GizmoMenuState extends State<GizmoMenu> {
  final FocusNode _focus = FocusNode(debugLabel: 'gizmoMenu');

  @override
  void initState() {
    super.initState();
    // Keys to it at once: Esc puts it away, Tab walks the switches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  GizmoModeSettings get _mine => widget.settings.gizmos.of(widget.mode);

  /// The mode's gizmos as [settings]; the other modes as they are.
  void _set(GizmoModeSettings settings) => widget.scope.prefs.change(
    (s) => s.copyWith(gizmos: s.gizmos.withMode(widget.mode, settings)),
  );

  /// Every mode's gizmos as this mode's.
  void _everyMode() {
    final mine = _mine;
    widget.scope.prefs.change(
      (s) => s.copyWith(
        gizmos: GizmoSettings(editor: mine, designer: mine, play: mine),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final mode = widget.mode;
    final gizmos = widget.settings.gizmos;
    final asItStarts = GizmoModeSettings.defaultFor(mode);
    final sameEverywhere = GizmoMode.values.every((m) => gizmos.of(m) == mine);
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FloatingToolFrame(
        settings: widget.settings,
        horizontalPadding: EditorMetrics.space(4),
        child: SizedBox(
          width: GizmoMenu.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Row(
                  children: [
                    Text(
                      'Gizmos',
                      style: TextStyle(
                        color: EditorTheme.textBright,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '· ${mode.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EditorTheme.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _GizmoRow(
                label: 'Show gizmos',
                tooltip:
                    'Everything below, in ${mode.label} only; the other '
                    'modes keep their own. The button switches this too.',
                value: mine.shown,
                strong: true,
                onChanged: (v) => _set(mine.copyWith(shown: v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: EditorDivider(),
              ),
              for (final kind in GizmoKind.values)
                _GizmoRow(
                  label: kind.label,
                  tooltip: kind.description,
                  value: !mine.hidden.contains(kind),
                  // Still set while hidden: ready for when they are shown.
                  dim: !mine.shown,
                  onChanged: (v) => _set(mine.withKind(kind, on: v)),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: EditorDivider(),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 2,
                children: [
                  Tooltip(
                    message: 'Every kind on',
                    child: EditorButton(
                      label: 'All kinds',
                      kind: EditorButtonKind.ghost,
                      onPressed: mine.hidden.isEmpty
                          ? null
                          : () => _set(mine.copyWith(hidden: const {})),
                    ),
                  ),
                  Tooltip(
                    message:
                        '${mode.label} as it starts: gizmos '
                        '${asItStarts.shown ? 'shown' : 'hidden'}, every '
                        'kind on',
                    child: EditorButton(
                      label: 'Reset',
                      kind: EditorButtonKind.ghost,
                      onPressed: mine == asItStarts
                          ? null
                          : () => _set(asItStarts),
                    ),
                  ),
                  Tooltip(
                    message:
                        'The editor, the Level Designer and a play-test '
                        'all as this',
                    child: EditorButton(
                      label: 'Every mode',
                      kind: EditorButtonKind.ghost,
                      onPressed: sameEverywhere ? null : _everyMode,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the menu: what it switches, and the switch. A click
/// anywhere on the line switches it.
class _GizmoRow extends StatelessWidget {
  const _GizmoRow({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
    this.strong = false,
    this.dim = false,
  });

  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// The mode's own switch, over the kinds.
  final bool strong;

  /// A kind while the mode's gizmos are hidden.
  final bool dim;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 600),
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dim
                      ? EditorTheme.textMuted
                      : strong
                      ? EditorTheme.textBright
                      : EditorTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            EditorToggle(value: value, label: label, onChanged: onChanged),
          ],
        ),
      ),
    ),
  );
}
