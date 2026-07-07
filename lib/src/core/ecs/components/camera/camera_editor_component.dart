import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class CameraEditorComponent extends EditorComponent {
  CameraEditorComponent()
    : super(
        id: 'camera_7f1a3d92',
        name: 'Camera',
        type: 'CameraComponent',
        group: 'Camera',
        description:
            'Marks this entity as the scene camera. Drives the main camera '
            'every frame and defines world bounds.',
        allowMultiple: false,
        // Prevents stripping the marker via the Inspector's own remove
        // button — the scene tree's "Delete" guard alone isn't enough,
        // since that would leave an entity that looks like the camera but
        // no longer behaves as one.
        deletable: false,
        componentType: ComponentType.core,
        icon: Icons.camera_alt_rounded,
        accentColor: const Color(0xFF26C6DA),
        factory: () => CameraComponent(),
        fields: [
          EditorComponentField(
            name: 'zoom',
            label: 'Zoom',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(
              step: 0.05,
              fractionDigits: 2,
              min: 0.05,
            ),
            read: (c) => (c as CameraComponent).zoom,
            write: (c, v) => (c as CameraComponent).zoom = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'boundsLeft',
            label: 'Bounds Left',
            kind: EditorFieldKind.decimal,
            read: (c) => (c as CameraComponent).bounds.left,
            write: (c, v) =>
                _setBounds(c as CameraComponent, left: (v as num).toDouble()),
          ),
          EditorComponentField(
            name: 'boundsTop',
            label: 'Bounds Top',
            kind: EditorFieldKind.decimal,
            read: (c) => (c as CameraComponent).bounds.top,
            write: (c, v) =>
                _setBounds(c as CameraComponent, top: (v as num).toDouble()),
          ),
          EditorComponentField(
            name: 'boundsWidth',
            label: 'Bounds Width',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(min: 1.0),
            read: (c) => (c as CameraComponent).bounds.width,
            write: (c, v) =>
                _setBounds(c as CameraComponent, width: (v as num).toDouble()),
          ),
          EditorComponentField(
            name: 'boundsHeight',
            label: 'Bounds Height',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(min: 1.0),
            read: (c) => (c as CameraComponent).bounds.height,
            write: (c, v) =>
                _setBounds(c as CameraComponent, height: (v as num).toDouble()),
          ),
        ],
      );

  static void _setBounds(
    CameraComponent c, {
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    final b = c.bounds;
    c.bounds = Rect.fromLTWH(
      left ?? b.left,
      top ?? b.top,
      width ?? b.width,
      height ?? b.height,
    );
  }
}
