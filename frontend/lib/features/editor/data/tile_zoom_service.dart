import 'dart:math' as math;
import 'dart:typed_data';

/// Tile-based zoom service — foundation for high-resolution zoomed rendering.
///
/// When the user zooms in beyond the base render resolution (2400px), the
/// current image becomes blurry. This service computes which tiles need to be
/// rendered at a higher resolution and manages the tile cache.
///
/// ### Architecture (preparation for pdfrx migration)
/// 1. The base page is rendered at 2400px max edge (existing renderer).
/// 2. When zoom > 1.5x, this service computes visible tiles.
/// 3. Each visible tile is rendered at native resolution from the PDF.
/// 4. Tiles are composited on top of the base image.
///
/// This service defines the tiling contract; the actual tile rendering
/// requires either pdfrx's built-in tiling or custom platform-channel calls
/// to PDFium (both future work).
class TileZoomService {
  const TileZoomService();

  /// Standard tile size (256×256 is common in map/PDF tile renderers).
  static const int tileSize = 256;

  /// Minimum zoom level at which tiling activates (below this, the base
  /// render is sharp enough).
  static const double tileActivationZoom = 1.5;

  /// Compute which tiles are visible at the current viewport.
  ///
  /// [viewportRect] is the visible area in page-normalised 0..1 coordinates.
  /// [zoom] is the current zoom level.
  /// [pageWidth]/[pageHeight] are the page's native dimensions in PDF points.
  ///
  /// Returns a list of tile coordinates that need to be rendered.
  List<TileCoord> visibleTiles({
    required double viewportLeft,
    required double viewportTop,
    required double viewportWidth,
    required double viewportHeight,
    required double zoom,
    required double pageWidth,
    required double pageHeight,
  }) {
    if (zoom < tileActivationZoom) return []; // base render is sufficient

    // Compute the render resolution at this zoom level.
    final renderW = (pageWidth * zoom).round();
    final renderH = (pageHeight * zoom).round();

    // How many tiles cover the full page at this resolution.
    final tilesX = (renderW / tileSize).ceil();
    final tilesY = (renderH / tileSize).ceil();

    // Which tiles are in the viewport (convert normalised → tile indices).
    final startX = (viewportLeft * tilesX).floor().clamp(0, tilesX - 1);
    final startY = (viewportTop * tilesY).floor().clamp(0, tilesY - 1);
    final endX = ((viewportLeft + viewportWidth) * tilesX).ceil().clamp(0, tilesX - 1);
    final endY = ((viewportTop + viewportHeight) * tilesY).ceil().clamp(0, tilesY - 1);

    final tiles = <TileCoord>[];
    for (var y = startY; y <= endY; y++) {
      for (var x = startX; x <= endX; x++) {
        tiles.add(TileCoord(x: x, y: y, zoom: zoom));
      }
    }
    return tiles;
  }

  /// Compute the pixel rect a tile covers on the rendered page.
  TileRect tilePixelRect(TileCoord tile, double pageWidth, double pageHeight) {
    final renderW = (pageWidth * tile.zoom).round();
    final renderH = (pageHeight * tile.zoom).round();
    final x = tile.x * tileSize;
    final y = tile.y * tileSize;
    final w = math.min(tileSize, renderW - x);
    final h = math.min(tileSize, renderH - y);
    return TileRect(x: x, y: y, width: w, height: h);
  }
}

/// A tile coordinate (grid position + zoom level).
class TileCoord {
  final int x;
  final int y;
  final double zoom;

  const TileCoord({required this.x, required this.y, required this.zoom});

  @override
  bool operator ==(Object other) =>
      other is TileCoord && other.x == x && other.y == y && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);

  @override
  String toString() => 'Tile($x,$y @${zoom.toStringAsFixed(1)}x)';
}

/// A pixel rectangle on the rendered page.
class TileRect {
  final int x, y, width, height;
  const TileRect({required this.x, required this.y, required this.width, required this.height});
}
