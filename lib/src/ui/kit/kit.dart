/// The parts the editor is built from — buttons, fields, controls, the
/// shapes of panels and dialogs — in its colours and at its sizes, so every
/// panel, dock and dialog looks like one editor, and a module's too.
///
/// Colours come from `EditorTheme`, sizes from `EditorMetrics`; both follow
/// the settings.
library;

export '../overlay/shared/dialog_frame.dart' show EditorDialogFrame;
export 'buttons.dart';
export 'controls.dart';
export 'dialogs.dart';
export 'fields.dart';
export 'focus.dart';
export 'layout.dart';
export 'look.dart';
export 'workspace.dart';
