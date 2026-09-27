import '../services/tool_registry.dart';
import '../services/action_registry.dart';
import 'search_photos_tool.dart';
import 'count_photos_tool.dart';
import 'get_gallery_stats_tool.dart';
import 'find_duplicates_tool.dart';
import 'filter_by_quality_tool.dart';
import 'find_best_photos_tool.dart';
import 'query_knowledge_graph_tool.dart';
import 'search_videos_tool.dart';
import 'get_video_chapters_tool.dart';
import 'get_video_highlights_tool.dart';
import 'get_video_summary_tool.dart';
import 'create_album_tool.dart';
import 'create_memory_tool.dart';
import 'add_favorites_tool.dart';
import 'remove_favorites_tool.dart';
import 'delete_photos_tool.dart';
import 'navigation_tools.dart';

/// Assembles and registers all gallery assistant tools.
///
/// Use [createToolRegistry] to build a fully-configured registry
/// with concrete callback implementations.
ToolRegistry createToolRegistry({
  required ActionRegistry legacyRegistry,
  required Future<List<String>> Function(Map<String, dynamic>) onSearch,
  required Future<int> Function(Map<String, dynamic>) onCount,
  required Future<Map<String, dynamic>> Function() onGetStats,
  required Future<Map<String, dynamic>> Function() onFindDuplicates,
  required Future<List<String>> Function(Map<String, dynamic>) onFilterQuality,
  required Future<List<String>> Function(Map<String, dynamic>) onFindBest,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onQueryKnowledgeGraph,
  required Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>)
      onSearchVideos,
  required Future<List<Map<String, dynamic>>> Function(String) onGetVideoChapters,
  required Future<List<Map<String, dynamic>>> Function(String) onGetVideoHighlights,
  required Future<Map<String, dynamic>?> Function(String) onGetVideoSummary,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onCreateAlbum,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onCreateMemory,
  required Future<int> Function(List<String>) onAddFavorites,
  required Future<int> Function(List<String>) onRemoveFavorites,
  required Future<int> Function(List<String>) onDeletePhotos,
  Future<bool> Function(String albumId)? onDeleteAlbum,
  Future<bool> Function(String memoryId)? onDeleteMemory,
  Future<int> Function(List<String>)? onUndoAddFavorites,
  Future<int> Function(List<String>)? onUndoRemoveFavorites,
}) {
  final registry = ToolRegistry();

  // Read-only tools
  registry.register(SearchPhotosTool(onSearch: onSearch));
  registry.register(CountPhotosTool(onCount: onCount));
  registry.register(GetGalleryStatsTool(onGetStats: onGetStats));
  registry.register(FindDuplicatesTool(onFind: onFindDuplicates));
  registry.register(FilterByQualityTool(onFilter: onFilterQuality));
  registry.register(FindBestPhotosTool(onFind: onFindBest));
  registry.register(QueryKnowledgeGraphTool(onQuery: onQueryKnowledgeGraph));
  registry.register(SearchVideosTool(onSearch: onSearchVideos));
  registry.register(GetVideoChaptersTool(onGetChapters: onGetVideoChapters));
  registry.register(GetVideoHighlightsTool(onGetHighlights: onGetVideoHighlights));
  registry.register(GetVideoSummaryTool(onGetSummary: onGetVideoSummary));

  // Write tools
  registry.register(CreateAlbumTool(onCreate: onCreateAlbum, onDelete: onDeleteAlbum));
  registry.register(CreateMemoryTool(onCreate: onCreateMemory, onDelete: onDeleteMemory));
  registry.register(AddFavoritesTool(onAdd: onAddFavorites, onUndoAdd: onUndoAddFavorites));
  registry.register(RemoveFavoritesTool(onRemove: onRemoveFavorites, onUndoRemove: onUndoRemoveFavorites));
  registry.register(DeletePhotosTool(onDelete: onDeletePhotos));

  // Navigation tools
  registry.register(OpenPhotoTool());
  registry.register(OpenPersonTool());
  registry.register(OpenEventTool());
  registry.register(OpenAlbumTool());
  registry.register(OpenEditorTool());

  return registry;
}

/// Register all tools into an existing registry.
void registerAllTools(ToolRegistry registry, {
  required Future<List<String>> Function(Map<String, dynamic>) onSearch,
  required Future<int> Function(Map<String, dynamic>) onCount,
  required Future<Map<String, dynamic>> Function() onGetStats,
  required Future<Map<String, dynamic>> Function() onFindDuplicates,
  required Future<List<String>> Function(Map<String, dynamic>) onFilterQuality,
  required Future<List<String>> Function(Map<String, dynamic>) onFindBest,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onQueryKnowledgeGraph,
  required Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>)
      onSearchVideos,
  required Future<List<Map<String, dynamic>>> Function(String) onGetVideoChapters,
  required Future<List<Map<String, dynamic>>> Function(String) onGetVideoHighlights,
  required Future<Map<String, dynamic>?> Function(String) onGetVideoSummary,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onCreateAlbum,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      onCreateMemory,
  required Future<int> Function(List<String>) onAddFavorites,
  required Future<int> Function(List<String>) onRemoveFavorites,
  required Future<int> Function(List<String>) onDeletePhotos,
  Future<bool> Function(String albumId)? onDeleteAlbum,
  Future<bool> Function(String memoryId)? onDeleteMemory,
  Future<int> Function(List<String>)? onUndoAddFavorites,
  Future<int> Function(List<String>)? onUndoRemoveFavorites,
}) {
  registry.register(SearchPhotosTool(onSearch: onSearch));
  registry.register(CountPhotosTool(onCount: onCount));
  registry.register(GetGalleryStatsTool(onGetStats: onGetStats));
  registry.register(FindDuplicatesTool(onFind: onFindDuplicates));
  registry.register(FilterByQualityTool(onFilter: onFilterQuality));
  registry.register(FindBestPhotosTool(onFind: onFindBest));
  registry.register(QueryKnowledgeGraphTool(onQuery: onQueryKnowledgeGraph));
  registry.register(SearchVideosTool(onSearch: onSearchVideos));
  registry.register(GetVideoChaptersTool(onGetChapters: onGetVideoChapters));
  registry.register(GetVideoHighlightsTool(onGetHighlights: onGetVideoHighlights));
  registry.register(GetVideoSummaryTool(onGetSummary: onGetVideoSummary));
  registry.register(CreateAlbumTool(onCreate: onCreateAlbum, onDelete: onDeleteAlbum));
  registry.register(CreateMemoryTool(onCreate: onCreateMemory, onDelete: onDeleteMemory));
  registry.register(AddFavoritesTool(onAdd: onAddFavorites, onUndoAdd: onUndoAddFavorites));
  registry.register(RemoveFavoritesTool(onRemove: onRemoveFavorites, onUndoRemove: onUndoRemoveFavorites));
  registry.register(DeletePhotosTool(onDelete: onDeletePhotos));
  registry.register(OpenPhotoTool());
  registry.register(OpenPersonTool());
  registry.register(OpenEventTool());
  registry.register(OpenAlbumTool());
  registry.register(OpenEditorTool());
}
