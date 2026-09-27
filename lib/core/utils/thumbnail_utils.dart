import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Thumbnail sizing helpers for smooth grid scrolling.
///
/// Requesting a fixed 300px thumbnail for a 70px tile over-decodes ~16x per
/// tile, stalling the raster thread while scrolling. These helpers size the
/// request to the actual tile size × device pixel ratio instead.
class ThumbnailSizes {
  ThumbnailSizes._();

  /// Thumbnail size for a grid tile in a [columns]-column grid.
  ///
  /// Accounts for screen width, inter-tile [spacing], and device pixel ratio.
  /// Clamped to [80, 800]px to avoid degenerate requests on odd layouts.
  static ThumbnailSize forGrid(
    BuildContext context,
    int columns, {
    double spacing = 2,
  }) {
    final media = MediaQuery.of(context);
    final safeColumns = columns.clamp(1, 12);
    final tileCssWidth =
        (media.size.width - spacing * (safeColumns - 1)) / safeColumns;
    final px = (tileCssWidth * media.devicePixelRatio).round().clamp(80, 800);
    return ThumbnailSize.square(px);
  }
}
