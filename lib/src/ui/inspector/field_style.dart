/// One look for every control in the inspector.
///
/// A row is a label of [labelWidth] and then its control, and every control
/// — a number, a line of text, a dropdown, a colour, an asset, a yes or no —
/// is the same box: the same fill, border, corner, height and type size. The
/// numbers used to be darker, shorter and a size larger than the rest, and a
/// bool was a bare checkbox, so a panel of them read as a jumble.
///
/// Anything added later takes its look from here rather than inventing one.
library;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

abstract final class InspectorField {
  /// The label column, left of every control.
  static const double labelWidth = 96;

  static const double fontSize = 11;
  static const double radius = 4;

  /// Inside a box, around its text.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 8,
  );

  /// What a box comes out at with [padding] and [fontSize]. Anything that is
  /// not a text field — a dropdown, a swatch, a toggle — is given this so a
  /// row of them sits on one line.
  ///
  /// Measured, not guessed: `inspector_look_test.dart` renders a real text
  /// field and fails if this drifts from it.
  static const double height = 33;

  static final Color fill = EditorTheme.inputBg;

  static final TextStyle labelStyle = TextStyle(
    color: EditorTheme.textMuted,
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle valueStyle = TextStyle(
    color: EditorTheme.textPrimary,
    fontSize: fontSize,
  );

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: color),
  );

  /// What a text field in the inspector looks like. [prefix] rides inside
  /// the box, before the value — an axis letter, say — so every box on every
  /// row starts at the same place whether or not it has one.
  static InputDecoration decoration({Widget? prefix, Color? borderColor}) =>
      InputDecoration(
        isDense: true,
        contentPadding: padding,
        filled: true,
        fillColor: fill,
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: _border(borderColor ?? EditorTheme.border),
        enabledBorder: _border(borderColor ?? EditorTheme.border),
        focusedBorder: _border(EditorTheme.primaryMutedLight),
      );

  /// The same box for what is not a text field.
  static BoxDecoration boxDecoration({Color? borderColor}) => BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? EditorTheme.border),
  );
}
