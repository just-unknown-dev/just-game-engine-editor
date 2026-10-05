/// Opening the colour picker from the editor.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:just_colours/just_colours.dart';

import '../../core/scope/editor_scope.dart';
import '../../core/theme/editor_material_theme.dart';
import '../kit/key_claim.dart';
import '../kit/look.dart';

/// Opens the colour picker beside [context]'s widget, in the editor's look,
/// offering the project's palettes and gradients and an eyedropper on the
/// viewport. Each change goes to [onPreview] while it is open; the choice
/// comes back when it closes, null when cancelled.
Future<ColourSelection?> showEditorColourPicker(
  BuildContext context, {
  required ColourSelection initial,
  ColourDialogView view = ColourDialogView.both,
  String? title,
  bool showTint = false,
  ValueChanged<ColourSelection>? onPreview,
}) {
  final scope = EditorScopeProvider.maybeOf(context);
  final theme = editorMaterialTheme();
  return ColourPopover.show(
    context,
    initialSelection: initial,
    view: view,
    title: title,
    showTint: showTint,
    library: scope?.colours.library,
    sampler: scope == null
        ? null
        : (at) => sampleViewport(scope.viewportCaptureKey, at),
    onChanged: onPreview,
    builder: (context, child) => Theme(
      data: theme,
      child: EditorLook(
        // Every key is the picker's while it has the focus: Delete takes a
        // gradient colour away, not the selected entity; Ctrl+Z does not
        // undo under a colour being shown live.
        child: EditorKeyClaim(claims: _claimsAll, child: child),
      ),
    ),
  );
}

bool _claimsAll(KeyEvent event) => true;

/// The colour the viewport shows at [global], read off the game drawn under
/// [key]'s repaint boundary — gizmos and all. Null away from the viewport.
Future<Color?> sampleViewport(GlobalKey key, Offset global) async {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderRepaintBoundary || !box.attached) return null;
  final local = box.globalToLocal(global);
  if (!(Offset.zero & box.size).contains(local)) return null;
  final image = await box.toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final x = local.dx.floor().clamp(0, image.width - 1);
    final y = local.dy.floor().clamp(0, image.height - 1);
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  } finally {
    image.dispose();
  }
}
