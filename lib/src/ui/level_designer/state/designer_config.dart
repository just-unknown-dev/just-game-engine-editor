/// The designer's tunables that used to be literals: which grid sizes the
/// status bar offers, which brush sizes `[` and `]` step through, how many
/// camera bookmark slots the digit keys address.
///
/// One per scope; pass a different one to `EditorScope(config: ...)` for a
/// game whose tiles are 24 units or whose brushes go to 9.
class DesignerConfig {
  const DesignerConfig({
    this.gridSizes = const [8, 16, 32, 64, 128],
    this.brushSizes = const [1, 3, 5],
    this.bookmarkSlots = 9,
  }) : assert(bookmarkSlots >= 0 && bookmarkSlots <= 9);

  /// Grid sizes the status bar offers, in world units.
  final List<double> gridSizes;

  /// Brush sizes the paint tool cycles through, in cells; odd, ascending.
  final List<int> brushSizes;

  /// How many camera bookmarks the digit keys 1–9 store and recall.
  final int bookmarkSlots;

  /// The next brush size up from [current], or [current] at the top.
  int largerBrush(int current) =>
      brushSizes.firstWhere((s) => s > current, orElse: () => current);

  /// The next brush size down from [current], or [current] at the bottom.
  int smallerBrush(int current) =>
      brushSizes.lastWhere((s) => s < current, orElse: () => current);
}
