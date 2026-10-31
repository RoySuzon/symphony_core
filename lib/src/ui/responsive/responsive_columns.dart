import 'dart:math' as math;

/// Returns how many columns of at least [minTileWidth] fit in [width].
///
/// [spacing] is the gap between two columns. The result is clamped between
/// [minColumns] and [maxColumns] (when given). An infinite or non-positive
/// [width] returns [minColumns].
///
/// ```dart
/// LayoutBuilder(
///   builder: (context, constraints) => GridView.count(
///     crossAxisCount: responsiveColumns(constraints.maxWidth, spacing: 16),
///     crossAxisSpacing: 16,
///     children: tiles,
///   ),
/// );
/// ```
int responsiveColumns(
  double width, {
  double minTileWidth = 280,
  double spacing = 0,
  int minColumns = 1,
  int? maxColumns,
}) {
  assert(minTileWidth > 0, 'minTileWidth must be positive.');
  assert(spacing >= 0, 'spacing must be non-negative.');
  assert(minColumns >= 1, 'minColumns must be at least 1.');
  assert(
    maxColumns == null || maxColumns >= minColumns,
    'maxColumns must be greater than or equal to minColumns.',
  );
  if (!width.isFinite || width <= 0) return minColumns;
  var columns = ((width + spacing) / (minTileWidth + spacing)).floor();
  columns = math.max(columns, minColumns);
  if (maxColumns != null) columns = math.min(columns, maxColumns);
  return columns;
}
