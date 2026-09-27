import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/text_layer.dart';
import '../providers/edit_session_provider.dart';

/// Text editing panel with input, styling, and positioning controls.
class TextPanel extends ConsumerStatefulWidget {
  final String photoId;

  const TextPanel({super.key, required this.photoId});

  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  final _textController = TextEditingController();
  Color _selectedColor = Colors.white;
  double _fontSize = 0.05;
  double _rotation = 0.0;
  double _opacity = 1.0;
  TextAlignment _alignment = TextAlignment.center;
  bool _hasBackground = false;
  int _backgroundColor = 0xFF000000;
  int? _editingIndex;

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
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;
    final textLayers = session.recipe.textLayers;

    return Container(
      color: Colors.black,
      height: 320,
      child: Column(
        children: [
          // Text input
          _buildTextInput(),
          // Style controls
          _buildStyleControls(),
          // Layer list
          Expanded(
            child: _buildLayerList(controller, textLayers),
          ),
          // Action buttons
          _buildActions(controller, textLayers),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _textController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter text...',
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Color picker
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _presetColors.length,
              itemBuilder: (context, index) {
                final color = _presetColors[index];
                final isSelected = _selectedColor.value == color.value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            isSelected ? Colors.blue : Colors.white24,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          // Font size
          Row(
            children: [
              const SizedBox(
                width: 50,
                child: Text('Size',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 0.02,
                  max: 0.15,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ],
          ),
          // Opacity
          Row(
            children: [
              const SizedBox(
                width: 50,
                child: Text('Alpha',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ),
              Expanded(
                child: Slider(
                  value: _opacity,
                  min: 0.1,
                  max: 1.0,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
              ),
            ],
          ),
          // Alignment buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AlignButton(
                icon: Icons.format_align_left,
                isActive: _alignment == TextAlignment.left,
                onTap: () =>
                    setState(() => _alignment = TextAlignment.left),
              ),
              _AlignButton(
                icon: Icons.format_align_center,
                isActive: _alignment == TextAlignment.center,
                onTap: () =>
                    setState(() => _alignment = TextAlignment.center),
              ),
              _AlignButton(
                icon: Icons.format_align_right,
                isActive: _alignment == TextAlignment.right,
                onTap: () =>
                    setState(() => _alignment = TextAlignment.right),
              ),
              const SizedBox(width: 16),
              _AlignButton(
                icon: _hasBackground
                    ? Icons.highlight
                    : Icons.highlight_off,
                isActive: _hasBackground,
                onTap: () =>
                    setState(() => _hasBackground = !_hasBackground),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList(
    EditSessionController controller,
    List<TextLayer> layers,
  ) {
    if (layers.isEmpty) {
      return const Center(
        child: Text(
          'No text layers. Type above and tap Add.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: layers.length,
      itemBuilder: (context, index) {
        final layer = layers[index];
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.text_fields,
            color: Color(layer.color),
            size: 20,
          ),
          title: Text(
            layer.text,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                color: Colors.white54,
                onPressed: () => _editLayer(controller, layers, index),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 18),
                color: Colors.red,
                onPressed: () => _deleteLayer(controller, layers, index),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions(
    EditSessionController controller,
    List<TextLayer> layers,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: _textController.text.isNotEmpty
                ? () => _addLayer(controller, layers)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(_editingIndex != null ? 'Update' : 'Add'),
          ),
          if (_editingIndex != null)
            TextButton(
              onPressed: () {
                setState(() => _editingIndex = null);
                _textController.clear();
              },
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  void _addLayer(EditSessionController controller, List<TextLayer> layers) {
    final newLayer = TextLayer(
      text: _textController.text,
      x: 0.5,
      y: 0.5,
      color: _selectedColor.value,
      opacity: _opacity,
      fontSize: _fontSize,
      rotation: _rotation,
      alignment: _alignment,
      hasBackground: _hasBackground,
      backgroundColor: _backgroundColor,
    );

    List<TextLayer> newLayers;
    if (_editingIndex != null && _editingIndex! < layers.length) {
      newLayers = List.from(layers);
      newLayers[_editingIndex!] = newLayer;
    } else {
      newLayers = [...layers, newLayer];
    }

    controller.setTextLayers(newLayers);
    setState(() => _editingIndex = null);
    _textController.clear();
  }

  void _editLayer(
    EditSessionController controller,
    List<TextLayer> layers,
    int index,
  ) {
    final layer = layers[index];
    setState(() {
      _editingIndex = index;
      _textController.text = layer.text;
      _selectedColor = Color(layer.color);
      _fontSize = layer.fontSize;
      _opacity = layer.opacity;
      _rotation = layer.rotation;
      _alignment = layer.alignment;
      _hasBackground = layer.hasBackground;
      _backgroundColor = layer.backgroundColor;
    });
  }

  void _deleteLayer(
    EditSessionController controller,
    List<TextLayer> layers,
    int index,
  ) {
    final newLayers = List<TextLayer>.from(layers)..removeAt(index);
    controller.setTextLayers(newLayers);
  }
}

class _AlignButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _AlignButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withValues(alpha: 0.3) : Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.blue : Colors.white54,
          size: 18,
        ),
      ),
    );
  }
}
