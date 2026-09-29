/// The Timeline dock's small dialogs: a line of text, who a track is bound
/// to, and which field a new track animates.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../overlay/docks/shared/dock_widgets.dart';
import 'timeline_session.dart';

final _body = TextStyle(color: EditorTheme.textSecondary, fontSize: 12);

InputDecoration _input(String? hint) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: TextStyle(color: EditorTheme.textMuted, fontSize: 12),
  filled: true,
  fillColor: EditorTheme.inputBg,
  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide.none,
  ),
);

/// A dialog's buttons state their own colours: the ambient Material theme
/// here is the light default.
TextButton timelineDialogButton(
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
}) => TextButton(
  onPressed: onPressed,
  child: Text(
    label,
    style: TextStyle(
      color: onPressed == null
          ? EditorTheme.textMuted
          : primary
          ? EditorTheme.primaryBright
          : EditorTheme.textMuted,
      fontSize: 11,
    ),
  ),
);

/// Asks for a line of text; null when cancelled.
Future<String?> promptTimelineText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => EditorLook(
      child: AlertDialog(
        backgroundColor: EditorTheme.dialogBg,
        title: Text(title, style: _body.copyWith(fontSize: 13)),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: text,
            autofocus: true,
            style: _body.copyWith(color: EditorTheme.textPrimary),
            decoration: _input(hint),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ),
        actions: [
          timelineDialogButton('Cancel', () => Navigator.of(context).pop()),
          timelineDialogButton(
            'OK',
            () => Navigator.of(context).pop(text.text.trim()),
            primary: true,
          ),
        ],
      ),
    ),
  );
}

/// Asks who a track acts on; null when cancelled.
Future<jge.TrackBinding?> promptTrackBinding(
  BuildContext context,
  TimelineSession session, {
  jge.TrackBinding initial = jge.TrackBinding.owner,
}) => showDialog<jge.TrackBinding>(
  context: context,
  builder: (context) => EditorLook(
    child: _BindingDialog(session: session, initial: initial),
  ),
);

class _BindingDialog extends StatefulWidget {
  const _BindingDialog({required this.session, required this.initial});

  final TimelineSession session;
  final jge.TrackBinding initial;

  @override
  State<_BindingDialog> createState() => _BindingDialogState();
}

class _BindingDialogState extends State<_BindingDialog> {
  late jge.TrackBindingKind _kind = widget.initial.kind;
  late final TextEditingController _value = TextEditingController(
    text: widget.initial.value,
  );

  jge.TrackBinding get _binding => switch (_kind) {
    jge.TrackBindingKind.self => jge.TrackBinding.owner,
    jge.TrackBindingKind.name => jge.TrackBinding.name(_value.text.trim()),
    jge.TrackBindingKind.tag => jge.TrackBinding.tag(_value.text.trim()),
  };

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = <String>{
      for (final e in widget.session.scope.world.entities)
        if ((e.name ?? '').isNotEmpty) e.name!,
    }.toList()..sort();
    return AlertDialog(
      backgroundColor: EditorTheme.dialogBg,
      title: Text('Bind to', style: _body.copyWith(fontSize: 13)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final (kind, label) in const [
                  (jge.TrackBindingKind.self, 'Self'),
                  (jge.TrackBindingKind.name, 'Entity'),
                  (jge.TrackBindingKind.tag, 'Tag'),
                ])
                  EditorChip(
                    label: label,
                    selected: _kind == kind,
                    onTap: () => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_kind == jge.TrackBindingKind.self)
              Text(
                'Whoever plays the timeline. This is what lets one timeline '
                'animate many entities.',
                style: _body,
              )
            else ...[
              TextField(
                controller: _value,
                autofocus: true,
                style: _body.copyWith(color: EditorTheme.textPrimary),
                decoration: _input(
                  _kind == jge.TrackBindingKind.name
                      ? 'The entity’s name'
                      : 'A tag — the first entity with it',
                ),
                onSubmitted: (_) => Navigator.of(context).pop(_binding),
              ),
              if (_kind == jge.TrackBindingKind.name && names.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 6),
                    children: [
                      for (final n in names)
                        InkWell(
                          onTap: () => setState(() => _value.text = n),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(n, style: _body),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        timelineDialogButton('Cancel', () => Navigator.of(context).pop()),
        timelineDialogButton(
          'Bind',
          () => Navigator.of(context).pop(_binding),
          primary: true,
        ),
      ],
    );
  }
}

/// A field chosen for a new property track.
class PropertyChoice {
  const PropertyChoice(this.binding, this.componentType, this.field);

  final jge.TrackBinding binding;
  final String componentType;
  final jge.SchemaField field;
}

/// Lists every field of the bound entity that can be keyed; null when
/// cancelled.
Future<PropertyChoice?> promptPropertyTrack(
  BuildContext context,
  TimelineSession session, {
  jge.TrackBinding binding = jge.TrackBinding.owner,
}) => showDialog<PropertyChoice>(
  context: context,
  builder: (context) => EditorLook(
    child: _PropertyDialog(session: session, binding: binding),
  ),
);

class _PropertyDialog extends StatefulWidget {
  const _PropertyDialog({required this.session, required this.binding});

  final TimelineSession session;
  final jge.TrackBinding binding;

  @override
  State<_PropertyDialog> createState() => _PropertyDialogState();
}

class _PropertyDialogState extends State<_PropertyDialog> {
  late jge.TrackBinding _binding = widget.binding;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final entity = _binding.resolve(session.scope.world, session.owner);
    final definitions = session.scope.definitions;
    final existing = {
      for (final t
          in session.asset.value?.propertyTracks ?? const <jge.PropertyTrack>[])
        if (t.binding == _binding) '${t.component}.${t.field}',
    };

    final sections = <Widget>[];
    for (final component in entity?.components ?? const <jge.Component>[]) {
      final definition = definitions.definitionFor(component);
      if (definition == null) continue;
      final fields = [
        for (final f in definition.fields)
          if (jge.PropertyAccess.canAnimate(f) &&
              (definition.hints.fields[f.name]?.visible ?? true))
            f,
      ];
      if (fields.isEmpty) continue;
      sections
        ..add(
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
            child: Text(
              definition.hints.name ?? definition.type,
              style: _body.copyWith(
                color: EditorTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        )
        ..addAll([
          for (final f in fields)
            InkWell(
              onTap: existing.contains('${definition.type}.${f.name}')
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(PropertyChoice(_binding, definition.type, f)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        definition.hints.fields[f.name]?.label ?? f.name,
                        style: _body.copyWith(
                          color:
                              existing.contains('${definition.type}.${f.name}')
                              ? EditorTheme.textMuted
                              : EditorTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      existing.contains('${definition.type}.${f.name}')
                          ? 'has a track'
                          : f.kind.id,
                      style: _body.copyWith(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ]);
    }

    return AlertDialog(
      backgroundColor: EditorTheme.dialogBg,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Animate a field of  ${_binding.label}',
              style: _body.copyWith(fontSize: 13),
            ),
          ),
          timelineDialogButton('Someone else…', () async {
            final next = await promptTrackBinding(
              context,
              session,
              initial: _binding,
            );
            if (next != null && mounted) setState(() => _binding = next);
          }, primary: true),
        ],
      ),
      content: SizedBox(
        width: 360,
        height: 340,
        child: entity == null
            ? Center(
                child: Text(
                  _binding.isSelf
                      ? 'Open the timeline from an entity that plays it to '
                            'pick from its fields.'
                      : 'Nothing in the scene answers to ${_binding.label}.',
                  textAlign: TextAlign.center,
                  style: _body,
                ),
              )
            : ListView(children: sections),
      ),
      actions: [
        timelineDialogButton('Cancel', () => Navigator.of(context).pop()),
      ],
    );
  }
}
