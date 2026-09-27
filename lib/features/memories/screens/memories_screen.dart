import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/memory_providers.dart';
import '../widgets/memory_card.dart';
import '../widgets/automatic_album_card.dart';
import '../../../domain/models/memory/memory.dart';
import '../../../domain/models/memory/automatic_album.dart';
import 'memory_detail_screen.dart';
import 'album_detail_screen.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(memoriesProvider);
    final albumsAsync = ref.watch(automaticAlbumsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Memories', icon: Icon(Icons.auto_awesome)),
            Tab(text: 'Albums', icon: Icon(Icons.collections_bookmark)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMemoriesTab(memoriesAsync),
          _buildAlbumsTab(albumsAsync),
        ],
      ),
    );
  }

  Widget _buildMemoriesTab(AsyncValue<List<Memory>> memoriesAsync) {
    return memoriesAsync.when(
      data: (memories) {
        if (memories.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No memories yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                SizedBox(height: 8),
                Text('Memories will appear as you add more photos',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: memories.length,
          itemBuilder: (context, index) {
            final memory = memories[index];
            return MemoryCard(
              memory: memory,
              onTap: () => _showMemoryDetail(memory),
              onDismiss: () => _dismissMemory(memory),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildAlbumsTab(AsyncValue<List<AutomaticAlbum>> albumsAsync) {
    return albumsAsync.when(
      data: (albums) {
        if (albums.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.collections_bookmark, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No albums yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                SizedBox(height: 8),
                Text('Automatic albums will be generated from your photos',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return AutomaticAlbumCard(
              album: album,
              onTap: () => _showAlbumDetail(album),
              onHide: () => _hideAlbum(album),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _showMemoryDetail(Memory memory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryDetailScreen(memory: memory),
      ),
    );
  }

  void _showAlbumDetail(AutomaticAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(album: album),
      ),
    );
  }

  void _dismissMemory(Memory memory) async {
    final service = ref.read(memoryServiceProvider);
    await service.dismissMemory(memory.memoryId);
    ref.invalidate(memoriesProvider);
  }

  void _hideAlbum(AutomaticAlbum album) async {
    final service = ref.read(memoryServiceProvider);
    await service.hideAlbum(album.albumId);
    ref.invalidate(automaticAlbumsProvider);
  }
}
