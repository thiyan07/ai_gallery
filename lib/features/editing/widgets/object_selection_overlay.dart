import 'package:flutter/material.dart';

import '../../../domain/models/object_detection_model.dart';

/// Overlay that displays detected object bounding boxes and allows selection.
///
/// Renders detection boxes as tappable labels over the image preview.
/// When a detection is tapped, it's highlighted and its label shown.
/// Supports tap-to-select and long-press for multi-select.
class ObjectSelectionOverlay extends StatelessWidget {
  final List<DetectedObject> detections;
  final Set<int> selectedIndices;
  final ValueChanged<int> onToggleSelection;
  final VoidCallback? onClearSelection;
  final String? selectedLabel;

  const ObjectSelectionOverlay({
    super.key,
    required this.detections,
    this.selectedIndices = const {},
    required this.onToggleSelection,
    this.onClearSelection,
    this.selectedLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        // Detection boxes
        ...detections.asMap().entries.map((entry) {
          final i = entry.key;
          final det = entry.value;
          final isSelected = selectedIndices.contains(i);
          return _DetectionBox(
            detection: det,
            index: i,
            isSelected: isSelected,
            onTap: () => onToggleSelection(i),
          );
        }),

        // Clear selection button
        if (selectedIndices.isNotEmpty && onClearSelection != null)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onClearSelection,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${selectedIndices.length} selected ×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),

        // Selected label badge
        if (selectedLabel != null)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                selectedLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetectionBox extends StatelessWidget {
  final DetectedObject detection;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _DetectionBox({
    required this.detection,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ltrb = detection.boundingBoxLTRB;

    return Positioned(
      left: ltrb[0],
      top: ltrb[1],
      width: ltrb[2] - ltrb[0],
      height: ltrb[3] - ltrb[1],
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.white54,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? Colors.blue.withAlpha(30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.black54,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Text(
                '${detection.label} ${(detection.confidence * 100).round()}%',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
