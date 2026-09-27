import 'package:flutter/material.dart';

import '../../../domain/models/memory/memory.dart';

class MemoryCard extends StatelessWidget {
  final Memory memory;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const MemoryCard({
    super.key,
    required this.memory,
    this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCoverPhoto(),
            _buildInfo(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPhoto() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _themeColor.withValues(alpha: 0.15),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              _themeIcon,
              size: 48,
              color: _themeColor.withValues(alpha: 0.6),
            ),
          ),
          if (memory.personIds.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${memory.personIds.length} people',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          if (onDismiss != null)
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (memory.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              memory.subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_themeIcon, size: 14, color: _themeColor),
              const SizedBox(width: 4),
              Text(
                _themeLabel,
                style: TextStyle(fontSize: 12, color: _themeColor),
              ),
              const Spacer(),
              Text(
                '${memory.photoCount} photos',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color get _themeColor {
    switch (memory.theme) {
      case MemoryTheme.trip:
        return Colors.blue;
      case MemoryTheme.birthday:
        return Colors.pink;
      case MemoryTheme.seasonal:
        return Colors.green;
      case MemoryTheme.event:
        return Colors.orange;
      case MemoryTheme.people:
        return Colors.purple;
      case MemoryTheme.milestone:
        return Colors.amber;
      case MemoryTheme.everyday:
        return Colors.teal;
    }
  }

  IconData get _themeIcon {
    switch (memory.theme) {
      case MemoryTheme.trip:
        return Icons.flight;
      case MemoryTheme.birthday:
        return Icons.cake;
      case MemoryTheme.seasonal:
        return Icons.wb_sunny;
      case MemoryTheme.event:
        return Icons.celebration;
      case MemoryTheme.people:
        return Icons.people;
      case MemoryTheme.milestone:
        return Icons.emoji_events;
      case MemoryTheme.everyday:
        return Icons.auto_awesome;
    }
  }

  String get _themeLabel {
    switch (memory.theme) {
      case MemoryTheme.trip:
        return 'Trip';
      case MemoryTheme.birthday:
        return 'Birthday';
      case MemoryTheme.seasonal:
        return 'Seasonal';
      case MemoryTheme.event:
        return 'Event';
      case MemoryTheme.people:
        return 'People';
      case MemoryTheme.milestone:
        return 'Milestone';
      case MemoryTheme.everyday:
        return 'Memory';
    }
  }
}
