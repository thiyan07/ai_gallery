import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../gallery/providers/gallery_providers.dart';
import '../../gallery/providers/navigation_provider.dart';
import '../../memories/providers/memory_providers.dart';
import '../../memories/screens/memories_screen.dart';
import '../../memories/screens/memory_detail_screen.dart';
import '../../memories/widgets/memory_card.dart';
import '../../people/providers/people_providers.dart';
import '../../people/screens/people_screen.dart';
import '../../events/screens/events_screen.dart';
import '../../search/screens/search_screen.dart';
import '../../assistant/screens/assistant_screen.dart';
import '../../../core/di/providers.dart';
import '../../../domain/models/photo_event.dart';

/// Smart home screen — the first thing users see.
///
/// Adapts sections based on available content:
/// - New library: onboarding / useful suggestions
/// - Small library: recent media + search
/// - Large library: memories + events + people + smart discovery
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final permAsync = ref.watch(mediaPermissionProvider);

    return permAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _permissionDeniedState(context),
      data: (granted) {
        if (!granted) return _permissionDeniedState(context);
        return _HomeContent();
      },
    );
  }

  Widget _permissionDeniedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 72,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to AI Gallery',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant photo access to see your memories, people, and events.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Grant Access'),
              onPressed: () => PhotoManager.openSetting(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(photoListProvider);
    final gridSize = ref.watch(gridSizeProvider);

    return CustomScrollView(
      slivers: [
        // ── Search bar ──
        SliverToBoxAdapter(child: _SearchBar()),

        // ── Recent media ──
        photos.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox()),
          data: (photoList) {
            if (photoList.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
            return SliverToBoxAdapter(
              child: _RecentMediaSection(photos: photoList, gridSize: gridSize),
            );
          },
        ),

        // ── Memories ──
        const SliverToBoxAdapter(child: _MemoriesSection()),

        // ── Events ──
        const SliverToBoxAdapter(child: _EventsSection()),

        // ── People ──
        const SliverToBoxAdapter(child: _PeopleSection()),

        // ── Smart suggestions ──
        const SliverToBoxAdapter(child: _SmartSuggestionsSection()),
      ],
    );
  }
}

// ── Search Bar ──────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          key: const Key('home_search_bar'),
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search photos, people, events...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Assistant button - keep separate so it doesn't block main bar tap
                IconButton(
                  key: const Key('home_assistant_button'),
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  tooltip: 'AI Assistant',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AssistantScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Recent Media Section ────────────────────────────────────────

class _RecentMediaSection extends ConsumerWidget {
  final List<AssetEntity> photos;
  final int gridSize;

  const _RecentMediaSection({required this.photos, required this.gridSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = photos.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  ref.read(activeTabProvider.notifier).switchTo(1);
                },
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recent.length,
            itemBuilder: (context, index) {
              final asset = recent[index];
              return Padding(
                padding: const EdgeInsets.all(4),
                child: _HomeThumbnail(asset: asset, size: 180),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Memories Section ────────────────────────────────────────────

class _MemoriesSection extends ConsumerWidget {
  const _MemoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = ref.watch(memoriesProvider);

    return memoriesAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (memories) {
        if (memories.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Memories',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MemoriesScreen()),
                      );
                    },
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: memories.length.clamp(0, 5),
                itemBuilder: (context, index) {
                  final memory = memories[index];
                  return Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      width: 280,
                      child: MemoryCard(
                        memory: memory,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MemoryDetailScreen(
                                memory: memory,
                              ),
                            ),
                          );
                        },
                        onDismiss: null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Events Section ──────────────────────────────────────────────

class _EventsSection extends ConsumerWidget {
  const _EventsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(appDatabaseProvider);

    return dbAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (db) {
        return FutureBuilder<List<PhotoEvent>>(
          future: db.events.getAll(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox();
            }

            final events = snapshot.data!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Events',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const EventsScreen()),
                      );
                    },
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Padding(
                        padding: const EdgeInsets.all(4),
                        child: _EventCard(event: event),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final PhotoEvent event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
                child: Center(
                  child: Icon(
                    event.locationLabel != null
                        ? Icons.location_on_outlined
                        : Icons.event_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateRange(event),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${event.photoCount} photos',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(PhotoEvent event) {
    final start = event.startTime;
    final end = event.endTime;
    final d = start.day == end.day && start.month == end.month;
    if (d) return '${start.day}/${start.month}/${start.year}';
    return '${start.day}/${start.month} - ${end.day}/${end.month}';
  }
}

// ── People Section ──────────────────────────────────────────────

class _PeopleSection extends ConsumerWidget {
  const _PeopleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clustersAsync = ref.watch(peopleClustersProvider);

    return clustersAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (clusters) {
        if (clusters.isEmpty) return const SizedBox();

        final named = clusters
            .where((c) => !c.label.startsWith('Unknown Person'))
            .toList();

        if (named.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'People',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(activeTabProvider.notifier).switchTo(3);
                    },
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: named.length.clamp(0, 10),
                itemBuilder: (context, index) {
                  final cluster = named[index];
                  return Padding(
                    padding: const EdgeInsets.all(4),
                    child: _PersonChip(
                      label: cluster.label,
                      count: cluster.faceCount,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonChip extends StatelessWidget {
  final String label;
  final int count;

  const _PersonChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            label.isNotEmpty ? label[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Smart Suggestions ───────────────────────────────────────────

class _SmartSuggestionsSection extends ConsumerWidget {
  const _SmartSuggestionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(photoListProvider);

    return photosAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (photos) {
        if (photos.length < 10) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Discover',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SuggestionChip(
                      icon: Icons.photo_library_outlined,
                      label: 'All Photos',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SuggestionChip(
                      icon: Icons.videocam_outlined,
                      label: 'Videos',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SuggestionChip(
                      icon: Icons.auto_awesome,
                      label: 'AI Insights',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AssistantScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail Widget ────────────────────────────────────────────

class _HomeThumbnail extends StatelessWidget {
  final AssetEntity asset;
  final double size;

  const _HomeThumbnail({required this.asset, this.size = 180});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: ThumbnailSize.square(size.toInt()),
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: size,
                height: size,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              );
            },
          ),
          if (asset.type == AssetType.video)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
