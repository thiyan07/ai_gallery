import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../domain/models/edit/edit_operation.dart';
import '../providers/edit_session_provider.dart';
import '../services/edit_export_service.dart';
import '../services/edit_transformation_engine.dart';
import '../widgets/filter_panel.dart';
import '../widgets/effects_panel.dart';
import '../widgets/text_panel.dart';
import '../widgets/frame_panel.dart';
import '../widgets/curves_panel.dart';
import '../widgets/hsl_panel.dart';
import '../widgets/edit_plan_panel.dart';

/// Main photo editing screen with crop, rotate, straighten, flip,
/// and adjustment tools.
class EditScreen extends ConsumerStatefulWidget {
  final String photoId;

  const EditScreen({super.key, required this.photoId});

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends ConsumerState<EditScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && session.hasEdits) _autoSaveOnExit(controller);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(session, controller),
        body: Column(
          children: [
            Expanded(child: _buildPreview(session, controller)),
            if (session.isStraightenMode)
              _buildStraightenSlider(session, controller),
            _buildBottomBar(session, controller),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    EditSessionState session,
    EditSessionController controller,
  ) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          if (session.hasEdits) {
            _showDiscardDialog(controller);
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      title: const Text('Edit'),
      actions: [
        if (controller.canUndo)
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: controller.undo,
          ),
        if (controller.canRedo)
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: controller.redo,
          ),
        if (session.hasEdits)
          TextButton(
            onPressed: () => _resetAll(controller),
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        TextButton(
          onPressed: session.isLoading
              ? null
              : session.isSaving
                  ? () => _cancelExport()
                  : () => _saveAndPop(controller),
          child: session.isSaving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Cancel',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ],
                )
              : const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPreview(
    EditSessionState session,
    EditSessionController controller,
  ) {
    if (session.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (session.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              session.error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final preview = controller.previewImage;
    if (preview == null) {
      return const Center(
        child: Text(
          'No image loaded',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _ImagePreview(
          image: preview,
          showCropOverlay: session.isCropMode,
          cropRect: session.currentCrop,
        ),
      ),
    );
  }

  Widget _buildStraightenSlider(
    EditSessionState session,
    EditSessionController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          const Icon(Icons.straighten, color: Colors.white70, size: 20),
          Expanded(
            child: Slider(
              value: session.straightenDegrees,
              min: -45,
              max: 45,
              divisions: 90,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChangeStart: (_) {},
              onChanged: controller.setStraighten,
              onChangeEnd: (_) => controller.commitAdjustment(),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${session.straightenDegrees.toStringAsFixed(1)}°',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    EditSessionState session,
    EditSessionController controller,
  ) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.isAdjustMode)
            AdjustmentsPanel(photoId: widget.photoId),
          if (session.isFilterMode)
            FilterPanel(photoId: widget.photoId),
          if (session.isEffectsMode)
            EffectsPanel(photoId: widget.photoId),
          if (session.isTextMode)
            TextPanel(photoId: widget.photoId),
          if (session.isFrameMode)
            FramePanel(photoId: widget.photoId),
          if (session.isCurvesMode)
            CurvesPanel(photoId: widget.photoId),
          if (session.isHslMode)
            HslPanel(photoId: widget.photoId),
          if (session.isPromptMode)
            EditPlanPanel(photoId: widget.photoId),
          if (session.isCropMode ||
              session.isRotateMode ||
              session.isStraightenMode)
            _buildModeBar(session, controller),
          _buildToolButtons(session, controller),
        ],
      ),
    );
  }

  Widget _buildModeBar(
    EditSessionState session,
    EditSessionController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: controller.exitEditMode,
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            session.isCropMode
                ? 'Crop'
                : session.isRotateMode
                    ? 'Rotate'
                    : 'Straighten',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            onPressed: controller.exitEditMode,
            child: const Text(
              'Done',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButtons(
    EditSessionState session,
    EditSessionController controller,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary tools row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ToolButton(
                icon: Icons.crop,
                label: 'Crop',
                isActive: session.isCropMode,
                onTap: controller.enterCropMode,
              ),
              _ToolButton(
                icon: Icons.rotate_right,
                label: 'Rotate',
                isActive: session.isRotateMode,
                onTap: controller.enterRotateMode,
              ),
              _ToolButton(
                icon: Icons.straighten,
                label: 'Straighten',
                isActive: session.isStraightenMode,
                onTap: controller.enterStraightenMode,
              ),
              _ToolButton(
                icon: Icons.flip,
                label: 'Flip H',
                isActive: session.isFlippedH,
                onTap: controller.toggleHorizontalFlip,
              ),
              _ToolButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip V',
                isActive: session.isFlippedV,
                onTap: controller.toggleVerticalFlip,
              ),
              _ToolButton(
                icon: Icons.photo_size_select_large,
                label: 'Resize',
                onTap: () => _showResizeDialog(context, controller, session),
              ),
              _ToolButton(
                icon: Icons.tune,
                label: 'Adjust',
                isActive: session.isAdjustMode,
                onTap: controller.enterAdjustMode,
              ),
            ],
          ),
        ),
        // Creative tools row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ToolButton(
                icon: Icons.photo_filter,
                label: 'Filter',
                isActive: session.isFilterMode,
                onTap: controller.enterFilterMode,
              ),
              _ToolButton(
                icon: Icons.auto_awesome,
                label: 'Effects',
                isActive: session.isEffectsMode,
                onTap: controller.enterEffectsMode,
              ),
              _ToolButton(
                icon: Icons.brush,
                label: 'Draw',
                isActive: session.isDrawMode,
                onTap: controller.enterDrawMode,
              ),
              _ToolButton(
                icon: Icons.text_fields,
                label: 'Text',
                isActive: session.isTextMode,
                onTap: controller.enterTextMode,
              ),
              _ToolButton(
                icon: Icons.photo_size_select_large,
                label: 'Frame',
                isActive: session.isFrameMode,
                onTap: controller.enterFrameMode,
              ),
              _ToolButton(
                icon: Icons.show_chart,
                label: 'Curves',
                isActive: session.isCurvesMode,
                onTap: controller.enterCurvesMode,
              ),
              _ToolButton(
                icon: Icons.color_lens,
                label: 'HSL',
                isActive: session.isHslMode,
                onTap: controller.enterHslMode,
              ),
              _ToolButton(
                icon: Icons.auto_awesome_outlined,
                label: 'AI Edit',
                isActive: session.isPromptMode,
                onTap: controller.enterPromptMode,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDiscardDialog(EditSessionController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard edits?'),
        content: const Text('You have unsaved edits. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.resetAll();
              Navigator.of(context).pop();
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _resetAll(EditSessionController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all edits?'),
        content: const Text(
          'This will remove all edits and revert to the original.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.resetAll();
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndPop(EditSessionController controller) async {
    final saved = await controller.saveRecipe();
    if (saved && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _cancelExport() async {
    final controller = ref.read(editSessionProvider(widget.photoId));
    controller.cancelExport();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _autoSaveOnExit(EditSessionController controller) {
    if (controller.state.hasEdits && !controller.state.isSaving) {
      controller.saveRecipe();
    }
  }

  void _showResizeDialog(BuildContext context, EditSessionController controller, EditSessionState session) {
    final origW = session.originalWidth > 0 ? session.originalWidth : 1920;
    final origH = session.originalHeight > 0 ? session.originalHeight : 1080;
    final currentResize = session.recipe.operations.where((op) => op.type == EditOperationType.resize).toList();
    final initW = currentResize.isNotEmpty ? currentResize.first.resizeWidth : origW;
    final initH = currentResize.isNotEmpty ? currentResize.first.resizeHeight : origH;
    final wCtrl = TextEditingController(text: '$initW');
    final hCtrl = TextEditingController(text: '$initH');
    bool maintain = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Resize'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Original: ${origW}×${origH}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(controller: wCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width')),
              TextField(controller: hCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height')),
              Row(children: [Checkbox(value: maintain, onChanged: (v){ setD(()=> maintain = v ?? true); }), const Text('Maintain aspect')]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ActionChip(label: const Text('25%'), onPressed: (){ final w=(origW*0.25).round(); final h=(origH*0.25).round(); wCtrl.text='$w'; hCtrl.text='$h'; }),
                ActionChip(label: const Text('50%'), onPressed: (){ final w=(origW*0.5).round(); final h=(origH*0.5).round(); wCtrl.text='$w'; hCtrl.text='$h'; }),
                ActionChip(label: const Text('75%'), onPressed: (){ final w=(origW*0.75).round(); final h=(origH*0.75).round(); wCtrl.text='$w'; hCtrl.text='$h'; }),
                ActionChip(label: const Text('Original'), onPressed: (){ wCtrl.text='$origW'; hCtrl.text='$origH'; }),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: (){ controller.removeResize(); Navigator.pop(ctx); }, child: const Text('Remove')),
            FilledButton(onPressed: (){
              final w = int.tryParse(wCtrl.text) ?? origW;
              final h = int.tryParse(hCtrl.text) ?? origH;
              if (w <=0 || h<=0 || w>8000 || h>8000) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid size (1-8000)'))); return; }
              controller.setResize(width: w, height: h, maintainAspect: maintain);
              Navigator.pop(ctx);
            }, child: const Text('Apply')),
          ],
        ),
      ),
    );
  }
}

/// Displays an img.Image using PNG encoding for the editor preview.
class _ImagePreview extends StatelessWidget {
  final img.Image image;
  final bool showCropOverlay;
  final CropRect cropRect;

  const _ImagePreview({
    required this.image,
    this.showCropOverlay = false,
    this.cropRect = const CropRect(left: 0, top: 0, width: 1, height: 1),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Image.memory(
                  Uint8List.fromList(img.encodePng(image)),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (showCropOverlay)
              _CropOverlay(
                cropRect: cropRect,
                imageSize: Size(
                  image.width.toDouble(),
                  image.height.toDouble(),
                ),
                containerSize: Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Crop overlay showing the crop rectangle with dimming and handles.
class _CropOverlay extends StatelessWidget {
  final CropRect cropRect;
  final Size imageSize;
  final Size containerSize;

  const _CropOverlay({
    required this.cropRect,
    required this.imageSize,
    required this.containerSize,
  });

  @override
  Widget build(BuildContext context) {
    final scaleX = containerSize.width / imageSize.width;
    final scaleY = containerSize.height / imageSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final displayWidth = imageSize.width * scale;
    final displayHeight = imageSize.height * scale;
    final offsetX = (containerSize.width - displayWidth) / 2;
    final offsetY = (containerSize.height - displayHeight) / 2;

    final cropLeft = offsetX + cropRect.left * displayWidth;
    final cropTop = offsetY + cropRect.top * displayHeight;
    final cropWidth = cropRect.width * displayWidth;
    final cropHeight = cropRect.height * displayHeight;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CropDimmerPainter(
              cropRect: ui.Rect.fromLTWH(
                cropLeft,
                cropTop,
                cropWidth,
                cropHeight,
              ),
            ),
          ),
        ),
        Positioned(
          left: cropLeft,
          top: cropTop,
          width: cropWidth,
          height: cropHeight,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: CustomPaint(painter: _RuleOfThirdsPainter()),
          ),
        ),
      ],
    );
  }
}

class _CropDimmerPainter extends CustomPainter {
  final ui.Rect cropRect;
  _CropDimmerPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cropRect.top), paint);
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        cropRect.bottom,
        size.width,
        size.height - cropRect.bottom,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        cropRect.right,
        cropRect.top,
        size.width - cropRect.right,
        cropRect.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropDimmerPainter old) =>
      old.cropRect != cropRect;
}

class _RuleOfThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
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
            color: isActive ? Colors.blue : Colors.white70,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.blue : Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ADJUSTMENTS PANEL
// =============================================================================

/// Full adjustments panel shown when the Adjustments tool is active.
/// Contains grouped sliders for Light, Color, and Detail adjustments.
class AdjustmentsPanel extends ConsumerWidget {
  final String photoId;

  const AdjustmentsPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editSessionProvider(photoId));
    final session = controller.state;

    return Container(
      color: Colors.black,
      height: 280,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildGroupHeader('Light'),
          ...AdjustmentDefaults.lightGroup.map(
            (key) => _buildSlider(
              context: context,
              name: key,
              value: session.adjustmentValue(key),
              controller: controller,
            ),
          ),
          const SizedBox(height: 12),
          _buildGroupHeader('Color'),
          ...AdjustmentDefaults.colorGroup.map(
            (key) => _buildSlider(
              context: context,
              name: key,
              value: session.adjustmentValue(key),
              controller: controller,
            ),
          ),
          const SizedBox(height: 12),
          _buildGroupHeader('Detail'),
          ...AdjustmentDefaults.detailGroup.map(
            (key) => _buildSlider(
              context: context,
              name: key,
              value: session.adjustmentValue(key),
              controller: controller,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required BuildContext context,
    required String name,
    required double value,
    required EditSessionController controller,
  }) {
    final label = AdjustmentDefaults.labels[name] ?? name;
    final displayValue = (value * 100).round();
    final isNeutral = value == 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: isNeutral ? Colors.white54 : Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          // Reset button (tap to reset individual adjustment)
          GestureDetector(
            onTap: isNeutral ? null : () => controller.resetAdjustment(name),
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isNeutral ? Colors.white12 : Colors.white24,
              ),
              child: Icon(
                Icons.close,
                size: 12,
                color: isNeutral ? Colors.white24 : Colors.white70,
              ),
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: isNeutral ? Colors.white54 : Colors.blue,
                inactiveTrackColor: Colors.white12,
                thumbColor: isNeutral ? Colors.white54 : Colors.white,
                overlayColor: Colors.white12,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                value: value,
                min: -1.0,
                max: 1.0,
                onChanged: (v) => controller.setAdjustment(name, v),
                onChangeStart: (_) {},
                onChangeEnd: (_) => controller.commitAdjustment(),
              ),
            ),
          ),
          // Value display
          SizedBox(
            width: 40,
            child: Text(
              '$displayValue',
              style: TextStyle(
                color: isNeutral ? Colors.white38 : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
