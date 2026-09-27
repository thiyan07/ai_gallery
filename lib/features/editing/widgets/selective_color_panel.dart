import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/edit_mask.dart';
import '../providers/edit_session_provider.dart';

/// Selective color panel — applies HSL adjustments within a masked region.
///
/// Reuses the existing [EditMask] infrastructure for region selection.
/// The mask is shared with other mask-based operations (background removal,
/// object removal). If no mask exists, the user can paint one inline.
class SelectiveColorPanel extends ConsumerStatefulWidget {
  final String photoId;

  const SelectiveColorPanel({super.key, required this.photoId});

  @override
  ConsumerState<SelectiveColorPanel> createState() =>
      _SelectiveColorPanelState();
}

class _SelectiveColorPanelState extends ConsumerState<SelectiveColorPanel> {
  String _selectedChannel = 'red';
  double _feather = 0.02;

  static const _channels = [
    ('red', Color(0xFFE53935)),
    ('orange', Color(0xFFFF9800)),
    ('yellow', Color(0xFFFFEB3B)),
    ('green', Color(0xFF4CAF50)),
    ('aqua', Color(0xFF00BCD4)),
    ('blue', Color(0xFF2196F3)),
    ('purple', Color(0xFF9C27B0)),
    ('magenta', Color(0xFFE91E63)),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;
    final selColorOp = session.recipe.operations
        .where((op) => op.type == EditOperationType.selectiveColor)
        .fold<EditOperation?>(
          null,
          (_, op) => op,
        );
    final channels = selColorOp?.selectiveColorChannels ?? {};
    final hasMask = selColorOp?.maskId != null;

    return Container(
      color: Colors.black,
      height: 260,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          if (!hasMask)
            _buildNoMaskNotice()
          else ...[
            _buildChannelSelector(),
            const SizedBox(height: 8),
            Expanded(
              child: _buildSliders(channels, controller, selColorOp),
            ),
            _buildFeatherSlider(controller, selColorOp),
          ],
        ],
      ),
    );
  }

  Widget _buildNoMaskNotice() {
    return const Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush, color: Colors.white24, size: 40),
            SizedBox(height: 12),
            Text(
              'Paint a mask first\nto enable selective color',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelSelector() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final (name, color) = _channels[index];
          final isSelected = name == _selectedChannel;
          return GestureDetector(
            onTap: () => setState(() => _selectedChannel = name),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(60) : Colors.white10,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : Colors.white24,
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSliders(
    Map<String, Map<String, double>> allChannels,
    EditSessionController controller,
    EditOperation? existing,
  ) {
    final channelValues = allChannels[_selectedChannel] ?? {};
    final hue = channelValues['hue'] ?? 0.0;
    final sat = channelValues['saturation'] ?? 0.0;
    final lum = channelValues['luminance'] ?? 0.0;

    return Column(
      children: [
        _buildSlider(
          label: 'Hue',
          value: hue,
          displayValue: '${(hue * 180).round()}°',
          onChanged: (v) => _updateChannel('hue', v, controller, existing),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
        _buildSlider(
          label: 'Saturation',
          value: sat,
          displayValue: '${(sat * 100).round()}%',
          onChanged: (v) =>
              _updateChannel('saturation', v, controller, existing),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
        _buildSlider(
          label: 'Luminance',
          value: lum,
          displayValue: '${(lum * 100).round()}%',
          onChanged: (v) =>
              _updateChannel('luminance', v, controller, existing),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required String displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(-1.0, 1.0),
                min: -1.0,
                max: 1.0,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              displayValue,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatherSlider(
    EditSessionController controller,
    EditOperation? existing,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text(
              'Feather',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white54,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white54,
              ),
              child: Slider(
                value: _feather,
                min: 0.0,
                max: 0.1,
                onChanged: (v) => setState(() => _feather = v),
                onChangeEnd: (_) => _updateFeather(controller, existing),
              ),
            ),
          ),
          Text(
            '${(_feather * 1000).round()}px',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _updateChannel(
    String param,
    double value,
    EditSessionController controller,
    EditOperation? existing,
  ) {
    if (existing == null) return;
    final recipe = controller.state.recipe;

    Map<String, Map<String, double>> channels =
        Map<String, Map<String, double>>.from(
      existing.selectiveColorChannels,
    );

    final currentChannel = Map<String, double>.from(
      channels[_selectedChannel] ?? {'hue': 0, 'saturation': 0, 'luminance': 0},
    );
    currentChannel[param] = value.clamp(-1.0, 1.0);
    channels[_selectedChannel] = currentChannel;

    final newOp = EditOperation.selectiveColor(
      maskId: existing.maskId!,
      channels: channels,
      feather: existing.maskFeather,
    );
    final ops = List<EditOperation>.from(recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.selectiveColor)
      ..add(newOp);
    final newRecipe = recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    controller.replaceRecipe(newRecipe);
  }

  void _updateFeather(
    EditSessionController controller,
    EditOperation? existing,
  ) {
    if (existing == null) return;
    final recipe = controller.state.recipe;

    final newOp = EditOperation.selectiveColor(
      maskId: existing.maskId!,
      channels: existing.selectiveColorChannels,
      feather: _feather,
    );
    final ops = List<EditOperation>.from(recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.selectiveColor)
      ..add(newOp);
    final newRecipe = recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    controller.replaceRecipe(newRecipe);
  }
}
