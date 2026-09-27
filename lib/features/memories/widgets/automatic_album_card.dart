import 'package:flutter/material.dart';

import '../../../domain/models/memory/automatic_album.dart';

class AutomaticAlbumCard extends StatelessWidget {
  final AutomaticAlbum album;
  final VoidCallback? onTap;
  final VoidCallback? onHide;

  const AutomaticAlbumCard({
    super.key,
    required this.album,
    this.onTap,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCover(),
            _buildInfo(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    return Expanded(
      flex: 3,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _typeColor.withValues(alpha: 0.15),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                _typeIcon,
                size: 36,
                color: _typeColor.withValues(alpha: 0.6),
              ),
            ),
            if (onHide != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onHide,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.visibility_off, color: Colors.white, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              album.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${album.photoCount} photos',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _typeColor {
    switch (album.type) {
      case AutomaticAlbumType.bestOfYear:
        return Colors.amber;
      case AutomaticAlbumType.monthlyHighlights:
        return Colors.blue;
      case AutomaticAlbumType.trip:
        return Colors.teal;
      case AutomaticAlbumType.event:
        return Colors.orange;
      case AutomaticAlbumType.people:
        return Colors.purple;
      case AutomaticAlbumType.seasonal:
        return Colors.green;
      case AutomaticAlbumType.recurring:
        return Colors.indigo;
      case AutomaticAlbumType.place:
        return Colors.red;
    }
  }

  IconData get _typeIcon {
    switch (album.type) {
      case AutomaticAlbumType.bestOfYear:
        return Icons.star;
      case AutomaticAlbumType.monthlyHighlights:
        return Icons.auto_awesome;
      case AutomaticAlbumType.trip:
        return Icons.flight;
      case AutomaticAlbumType.event:
        return Icons.celebration;
      case AutomaticAlbumType.people:
        return Icons.people;
      case AutomaticAlbumType.seasonal:
        return Icons.wb_sunny;
      case AutomaticAlbumType.recurring:
        return Icons.repeat;
      case AutomaticAlbumType.place:
        return Icons.location_on;
    }
  }
}
