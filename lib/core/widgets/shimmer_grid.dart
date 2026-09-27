import 'package:flutter/material.dart';

/// Grid-shaped skeleton loader shown while photo results load.
///
/// A static spinner gives no sense of what's coming; a shimmer grid matching
/// the result layout feels faster and avoids layout jump when tiles arrive.
class ShimmerGrid extends StatefulWidget {
  const ShimmerGrid({
    super.key,
    this.columns = 3,
    this.itemCount = 12,
    this.spacing = 4,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 8,
  });

  final int columns;
  final int itemCount;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  State<ShimmerGrid> createState() => _ShimmerGridState();
}

class _ShimmerGridState extends State<ShimmerGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final brightness = theme.brightness;
    final highlight = Color.lerp(
      base,
      brightness == Brightness.dark ? Colors.white : Colors.black,
      0.10,
    )!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.columns,
            crossAxisSpacing: widget.spacing,
            mainAxisSpacing: widget.spacing,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            // Stagger the sweep per tile so the shimmer travels across the grid.
            final phase = (index % widget.columns) / widget.columns;
            final t = (_controller.value + phase) % 1.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [base, highlight, base],
                  stops: [
                    (t - 0.35).clamp(0.0, 1.0),
                    t,
                    (t + 0.35).clamp(0.0, 1.0),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
