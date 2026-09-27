import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Before/After split view for comparing edits.
///
/// Displays the original image on the left and the edited image on the right,
/// separated by a draggable divider. Long-press to toggle full before/after.
class BeforeAfterView extends StatefulWidget {
  final ui.Image? beforeImage;
  final ui.Image? afterImage;

  const BeforeAfterView({
    super.key,
    this.beforeImage,
    this.afterImage,
  });

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<BeforeAfterView>
    with SingleTickerProviderStateMixin {
  double _splitPosition = 0.5;
  bool _showBefore = false;
  bool _isDragging = false;

  late AnimationController _animController;
  late Animation<double> _animFade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.beforeImage == null || widget.afterImage == null) {
      return const Center(
        child: Text('Loading...', style: TextStyle(color: Colors.white54)),
      );
    }

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            children: [
              // Full edited image (background)
              SizedBox(
                width: w,
                height: h,
                child: RawImage(
                  image: widget.afterImage,
                  fit: BoxFit.contain,
                  width: w,
                  height: h,
                ),
              ),
              // Clipped original image
              ClipRect(
                clipper: _SplitClipper(
                  _showBefore ? 1.0 : _splitPosition,
                ),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: RawImage(
                    image: widget.beforeImage,
                    fit: BoxFit.contain,
                    width: w,
                    height: h,
                  ),
                ),
              ),
              // Divider line
              if (!_showBefore)
                Positioned(
                  left: _splitPosition * w - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.white,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(80),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.swap_horiz,
                          size: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              // Labels
              if (!_showBefore) ...[
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildLabel('Before'),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildLabel('After'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _showBefore = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localX = box.globalToLocal(details.globalPosition).dx;
    setState(() {
      _splitPosition = (localX / box.size.width).clamp(0.05, 0.95);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _showBefore = true;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    setState(() {
      _showBefore = false;
    });
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double fraction;

  _SplitClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_SplitClipper oldClipper) =>
      fraction != oldClipper.fraction;
}
