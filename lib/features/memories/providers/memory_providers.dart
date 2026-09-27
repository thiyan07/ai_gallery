import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/memory/memory.dart';
import '../../../domain/models/memory/automatic_album.dart';
import '../services/memory_service.dart';

final memoryServiceProvider = Provider<MemoryService>((ref) {
  throw UnimplementedError('Override in providers.dart');
});

final memoriesProvider = FutureProvider<List<Memory>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getActiveMemories();
});

final automaticAlbumsProvider = FutureProvider<List<AutomaticAlbum>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getVisibleAlbums();
});

final memoryCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getMemoryCount();
});
