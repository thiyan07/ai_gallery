import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/edit_operation.dart';
import '../providers/edit_session_provider.dart';

enum _CurveChannel { rgb, red, green, blue }

class CurvesPanel extends ConsumerStatefulWidget {
  final String photoId;

  const CurvesPanel({super.key, required this.photoId});

  @override
  ConsumerState<CurvesPanel> createState() => _CurvesPanelState();
}

class _CurvesPanelState extends ConsumerState<CurvesPanel> {
  _CurveChannel _selectedChannel = _CurveChannel.rgb;
  int? _draggingPointIndex;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;
    final curvesOp = session.recipe.operations
        .where((op) => op.type == EditOperationType.curves)
        .fold<EditOperation?>(null, (_, op) => op);
    final intensity = curvesOp?.curvesIntensity ?? 1.0;

    return Container(
      color: Colors.black,
      height: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          _buildChannelTabs(),
          const SizedBox(height: 8),
          Expanded(
            child: _buildCurveGraph(controller, curvesOp),
          ),
          const SizedBox(height: 8),
          _buildIntensitySlider(controller, intensity),
        ],
      ),
    );
  }

  Widget _buildChannelTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _CurveChannel.values.map((ch) {
        final isSelected = ch == _selectedChannel;
        final color = _channelColor(ch);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(
              ch.name.toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: color.withAlpha(77),
            backgroundColor: Colors.white10,
            side: BorderSide(
              color: isSelected ? color : Colors.white24,
            ),
            onSelected: (_) => setState(() => _selectedChannel = ch),
          ),
        );
      }).toList(),
    );
  }

  Color _channelColor(_CurveChannel ch) {
    return switch (ch) {
      _CurveChannel.rgb => Colors.white,
      _CurveChannel.red => Colors.redAccent,
      _CurveChannel.green => Colors.greenAccent,
      _CurveChannel.blue => Colors.blueAccent,
    };
  }

  Widget _buildCurveGraph(
    EditSessionController controller,
    EditOperation? curvesOp,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (d) =>
              _onPanStart(d, constraints, curvesOp, controller),
          onPanUpdate: (d) =>
              _onPanUpdate(d, constraints, curvesOp, controller),
          onPanEnd: (_) => _onPanEnd(controller),
          onTapUp: (d) =>
              _onTapAddPoint(d, constraints, curvesOp, controller),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _CurvePainter(
              channel: _selectedChannel,
              rgbPoints: curvesOp?.curvesRgbPoints ?? _defaultPoints(),
              channelPoints: curvesOp?.curvesChannelPoints ?? {},
            ),
          ),
        );
      },
    );
  }

  List<Map<String, double>> _defaultPoints() => const [
        {'x': 0.0, 'y': 0.0},
        {'x': 1.0, 'y': 1.0},
      ];

  List<Map<String, double>> _currentPoints(EditOperation? curvesOp) {
    if (curvesOp == null) return _defaultPoints();
    return switch (_selectedChannel) {
      _CurveChannel.rgb => curvesOp.curvesRgbPoints,
      _CurveChannel.red =>
        curvesOp.curvesChannelPoints['r'] ?? _defaultPoints(),
      _CurveChannel.green =>
        curvesOp.curvesChannelPoints['g'] ?? _defaultPoints(),
      _CurveChannel.blue =>
        curvesOp.curvesChannelPoints['b'] ?? _defaultPoints(),
    };
  }

  void _onPanStart(
    DragStartDetails details,
    BoxConstraints constraints,
    EditOperation? curvesOp,
    EditSessionController controller,
  ) {
    final points = _currentPoints(curvesOp);
    final dx = details.localPosition.dx / constraints.maxWidth;
    final dy = 1.0 - details.localPosition.dy / constraints.maxHeight;

    var bestIdx = -1;
    var bestDist = 0.05;
    for (var i = 0; i < points.length; i++) {
      final px = points[i]['x']!;
      final py = points[i]['y']!;
      final dist = math.sqrt((dx - px) * (dx - px) + (dy - py) * (dy - py));
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    setState(() => _draggingPointIndex = bestIdx >= 0 ? bestIdx : null);
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    BoxConstraints constraints,
    EditOperation? curvesOp,
    EditSessionController controller,
  ) {
    if (_draggingPointIndex == null) return;
    final points = List<Map<String, double>>.from(_currentPoints(curvesOp));
    final idx = _draggingPointIndex!;
    if (idx >= points.length) return;

    final isFirst = idx == 0;
    final isLast = idx == points.length - 1;

    var dx = details.localPosition.dx / constraints.maxWidth;
    var dy = 1.0 - details.localPosition.dy / constraints.maxHeight;

    dx = dx.clamp(0.0, 1.0);
    dy = dy.clamp(0.0, 1.0);

    if (isFirst) dx = 0.0;
    if (isLast) dx = 1.0;

    if (!isFirst && idx > 0) {
      final minX = points[idx - 1]['x']! + 0.01;
      if (dx < minX) dx = minX;
    }
    if (!isLast && idx < points.length - 1) {
      final maxX = points[idx + 1]['x']! - 0.01;
      if (dx > maxX) dx = maxX;
    }

    points[idx] = {'x': dx, 'y': dy};
    _applyPoints(points, controller);
  }

  void _onPanEnd(EditSessionController controller) {
    setState(() => _draggingPointIndex = null);
    controller.commitAdjustment();
  }

  void _onTapAddPoint(
    TapUpDetails details,
    BoxConstraints constraints,
    EditOperation? curvesOp,
    EditSessionController controller,
  ) {
    final dx = details.localPosition.dx / constraints.maxWidth;
    final dy = 1.0 - details.localPosition.dy / constraints.maxHeight;

    final points = _currentPoints(curvesOp);
    for (final p in points) {
      final dist = math.sqrt(
          (dx - p['x']!) * (dx - p['x']!) + (dy - p['y']!) * (dy - p['y']!));
      if (dist < 0.05) return;
    }

    final newPoints = List<Map<String, double>>.from(points)
      ..add({'x': dx.clamp(0.0, 1.0), 'y': dy.clamp(0.0, 1.0)});
    newPoints.sort((a, b) => a['x']!.compareTo(b['x']!));
    _applyPoints(newPoints, controller);
  }

  void _applyPoints(
    List<Map<String, double>> points,
    EditSessionController controller,
  ) {
    final recipe = controller.state.recipe;
    final existing = recipe.operations
        .where((op) => op.type == EditOperationType.curves)
        .fold<EditOperation?>(null, (_, op) => op);

    Map<String, List<Map<String, double>>> channelPoints =
        Map<String, List<Map<String, double>>>.from(
      existing?.curvesChannelPoints ?? {},
    );

    switch (_selectedChannel) {
      case _CurveChannel.rgb:
        final newOp = EditOperation.curves(
          rgbPoints: points,
          channelPoints: channelPoints,
          intensity: existing?.curvesIntensity ?? 1.0,
        );
        _replaceOrAddOp(newOp, controller);
        return;
      case _CurveChannel.red:
        channelPoints = Map.from(channelPoints)..['r'] = points;
      case _CurveChannel.green:
        channelPoints = Map.from(channelPoints)..['g'] = points;
      case _CurveChannel.blue:
        channelPoints = Map.from(channelPoints)..['b'] = points;
    }

    final newOp = EditOperation.curves(
      rgbPoints: existing?.curvesRgbPoints ?? _defaultPoints(),
      channelPoints: channelPoints,
      intensity: existing?.curvesIntensity ?? 1.0,
    );
    _replaceOrAddOp(newOp, controller);
  }

  void _replaceOrAddOp(EditOperation newOp, EditSessionController controller) {
    final ops = List<EditOperation>.from(controller.state.recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.curves)
      ..add(newOp);
    final newRecipe = controller.state.recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    controller.replaceRecipe(newRecipe);
  }

  Widget _buildIntensitySlider(
    EditSessionController controller,
    double intensity,
  ) {
    return Row(
      children: [
        const Text(
          'Intensity',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: intensity,
              min: 0.0,
              max: 1.0,
              onChanged: (v) => _setIntensity(v, controller),
              onChangeEnd: (_) => controller.commitAdjustment(),
            ),
          ),
        ),
        Text(
          '${(intensity * 100).round()}%',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  void _setIntensity(double value, EditSessionController controller) {
    final existing = controller.state.recipe.operations
        .where((op) => op.type == EditOperationType.curves)
        .fold<EditOperation?>(null, (_, op) => op);
    if (existing == null) return;

    final newOp = EditOperation.curves(
      rgbPoints: existing.curvesRgbPoints,
      channelPoints: existing.curvesChannelPoints,
      intensity: value,
    );
    _replaceOrAddOp(newOp, controller);
  }
}

class _CurvePainter extends CustomPainter {
  final _CurveChannel channel;
  final List<Map<String, double>> rgbPoints;
  final Map<String, List<Map<String, double>>> channelPoints;

  _CurvePainter({
    required this.channel,
    required this.rgbPoints,
    required this.channelPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background grid
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final frac = i / 4.0;
      canvas.drawLine(
        Offset(frac * w, 0),
        Offset(frac * w, h),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, (1 - frac) * h),
        Offset(w, (1 - frac) * h),
        gridPaint,
      );
    }

    // Diagonal reference line
    final refPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(w, 0), refPaint);

    // Draw RGB curve if viewing a per-channel tab
    if (channel != _CurveChannel.rgb) {
      _drawCurve(canvas, w, h, rgbPoints, Colors.white24, 1.0);
    }

    // Draw active channel curve
    final activePoints = _activePoints();
    final activeColor = _channelPaintColor();
    _drawCurve(canvas, w, h, activePoints, activeColor, 2.0);

    // Draw control points
    final pointPaint = Paint()..color = activeColor;
    for (final p in activePoints) {
      final px = p['x']! * w;
      final py = (1 - p['y']!) * h;
      canvas.drawCircle(const Offset(0, 0), 5, Paint());
      canvas.drawCircle(
        Offset(px, py),
        5,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(px, py),
        4,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  List<Map<String, double>> _activePoints() {
    return switch (channel) {
      _CurveChannel.rgb => rgbPoints,
      _CurveChannel.red => channelPoints['r'] ?? rgbPoints,
      _CurveChannel.green => channelPoints['g'] ?? rgbPoints,
      _CurveChannel.blue => channelPoints['b'] ?? rgbPoints,
    };
  }

  Color _channelPaintColor() {
    return switch (channel) {
      _CurveChannel.rgb => Colors.white,
      _CurveChannel.red => Colors.redAccent,
      _CurveChannel.green => Colors.greenAccent,
      _CurveChannel.blue => Colors.blueAccent,
    };
  }

  void _drawCurve(
    Canvas canvas,
    double w,
    double h,
    List<Map<String, double>> points,
    Color color,
    double strokeWidth,
  ) {
    if (points.length < 2) return;
    final sorted = List<Map<String, double>>.from(points)
      ..sort((a, b) => a['x']!.compareTo(b['x']!));

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(sorted[0]['x']! * w, (1 - sorted[0]['y']!) * h);
    for (var i = 1; i < sorted.length; i++) {
      path.lineTo(sorted[i]['x']! * w, (1 - sorted[i]['y']!) * h);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) =>
      channel != oldDelegate.channel ||
      rgbPoints != oldDelegate.rgbPoints ||
      channelPoints != oldDelegate.channelPoints;
}
