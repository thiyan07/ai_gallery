import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/drawing_layer.dart';
import '../providers/edit_session_provider.dart';

/// Drawing panel with brush controls, color picker, and canvas.
class DrawPanel extends ConsumerStatefulWidget {
  final String photoId;

  const DrawPanel({super.key, required this.photoId});

  @override
  ConsumerState<DrawPanel> createState() => _DrawPanelState();
}

class _DrawPanelState extends ConsumerState<DrawPanel> {
  Color _selectedColor = Colors.white;
  double _brushSize = 0.01;
  double _brushOpacity = 1.0;
  BrushType _brushType = BrushType.round;
  bool _isEraser = false;
  List<StrokePoint> _currentStrokePoints = [];

  static const _presetColors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;
    final drawingLayer = session.recipe.drawingLayer;

    return Container(
      color: Colors.black,
      height: 280,
      child: Column(
        children: [
          // Color picker row
          _buildColorPicker(),
          // Brush size and opacity
          _buildBrushControls(),
          // Action buttons
          _buildActionButtons(controller, drawingLayer),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _presetColors.length,
        itemBuilder: (context, index) {
          final color = _presetColors[index];
          final isSelected = _selectedColor == color && !_isEraser;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedColor = color;
                _isEraser = false;
              });
            },
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBrushControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text(
                  'Size',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _brushSize,
                  min: 0.003,
                  max: 0.05,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _brushSize = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text(
                  'Opacity',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _brushOpacity,
                  min: 0.1,
                  max: 1.0,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _brushOpacity = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    EditSessionController controller,
    DrawingLayer drawingLayer,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.brush,
            label: 'Brush',
            isActive: !_isEraser,
            onTap: () => setState(() => _isEraser = false),
          ),
          _ActionButton(
            icon: Icons.auto_fix_high,
            label: 'Eraser',
            isActive: _isEraser,
            onTap: () => setState(() => _isEraser = true),
          ),
          _ActionButton(
            icon: Icons.undo,
            label: 'Undo',
            isActive: false,
            onTap: drawingLayer.isNotEmpty
                ? () {
                    final newLayer = drawingLayer.removeLastStroke();
                    controller.setDrawing(newLayer);
                  }
                : null,
          ),
          _ActionButton(
            icon: Icons.delete_outline,
            label: 'Clear',
            isActive: false,
            onTap: drawingLayer.isNotEmpty
                ? () {
                    final newLayer = drawingLayer.clear();
                    controller.setDrawing(newLayer);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  /// Convert normalized coordinates to stroke points.
  StrokePoint _normalizePoint(Offset point, Size canvasSize) {
    return StrokePoint(
      x: (point.dx / canvasSize.width).clamp(0.0, 1.0),
      y: (point.dy / canvasSize.height).clamp(0.0, 1.0),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: onTap == null
                ? Colors.white24
                : isActive
                    ? Colors.blue
                    : Colors.white70,
            size: 24,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? Colors.white24
                  : isActive
                      ? Colors.blue
                      : Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawing canvas widget that handles touch input.
class DrawingCanvas extends StatefulWidget {
  final DrawingLayer layer;
  final Color brushColor;
  final double brushSize;
  final double brushOpacity;
  final BrushType brushType;
  final bool isEraser;
  final ValueChanged<DrawingLayer> onStrokeUpdate;
  final VoidCallback onStrokeEnd;

  const DrawingCanvas({
    super.key,
    required this.layer,
    required this.brushColor,
    required this.brushSize,
    required this.brushOpacity,
    required this.brushType,
    required this.isEraser,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<StrokePoint> _currentPoints = [];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        painter: _DrawingPainter(
          layer: widget.layer,
          brushColor: widget.brushColor,
          brushSize: widget.brushSize,
          brushOpacity: widget.brushOpacity,
          isEraser: widget.isEraser,
          currentPoints: _currentPoints,
        ),
        size: Size.infinite,
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    _currentPoints = [];
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Points are stored normalized; the painter handles display
    setState(() {
      _currentPoints.add(StrokePoint(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
      ));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentPoints.isNotEmpty) {
      final stroke = Stroke(
        points: List.from(_currentPoints),
        color: widget.isEraser ? 0x00000000 : widget.brushColor.value,
        opacity: widget.isEraser ? 1.0 : widget.brushOpacity,
        width: widget.brushSize,
        brushType: widget.brushType,
      );
      widget.onStrokeUpdate(widget.layer.addStroke(stroke));
      widget.onStrokeEnd();
    }
    setState(() => _currentPoints = []);
  }
}

class _DrawingPainter extends CustomPainter {
  final DrawingLayer layer;
  final Color brushColor;
  final double brushSize;
  final double brushOpacity;
  final bool isEraser;
  final List<StrokePoint> currentPoints;

  _DrawingPainter({
    required this.layer,
    required this.brushColor,
    required this.brushSize,
    required this.brushOpacity,
    required this.isEraser,
    required this.currentPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw existing strokes
    for (final stroke in layer.strokes) {
      _drawStroke(canvas, size, stroke);
    }

    // Draw current stroke in progress
    if (currentPoints.length >= 2) {
      final paint = Paint()
        ..color = brushColor.withValues(alpha: brushOpacity)
        ..strokeWidth = brushSize * math.min(size.width, size.height)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < currentPoints.length - 1; i++) {
        final p0 = currentPoints[i];
        final p1 = currentPoints[i + 1];
        canvas.drawLine(
          Offset(p0.x, p0.y),
          Offset(p1.x, p1.y),
          paint,
        );
      }
    }
  }

  void _drawStroke(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..strokeWidth =
          stroke.width * math.min(size.width, size.height)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final color = Color(stroke.color);
    if (stroke.brushType == BrushType.soft) {
      paint
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          stroke.width * math.min(size.width, size.height) * 0.5,
        );
    }

    paint.color = color.withValues(alpha: stroke.opacity);

    for (var i = 0; i < stroke.points.length - 1; i++) {
      final p0 = stroke.points[i];
      final p1 = stroke.points[i + 1];
      canvas.drawLine(
        Offset(p0.x, p0.y),
        Offset(p1.x, p1.y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
