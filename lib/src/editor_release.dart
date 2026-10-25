import 'package:just_asset_store/just_asset_store.dart' show ItemStage;

/// The editor's own release: its version and how finished it is, shown on
/// its start card. Kept equal to `pubspec.yaml`'s version (a test checks).
abstract final class EditorRelease {
  /// This release, as `pubspec.yaml` names it.
  static const String version = '0.1.0-dev.2';

  /// How finished the editor is: the same stages store plugins use.
  static const ItemStage stage = ItemStage.beta;
}
