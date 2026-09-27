import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/intent_resolver.dart';
import '../services/structured_retriever.dart';
import '../services/gallery_assistant.dart';
import '../services/action_registry.dart';
import '../services/action_executor.dart';
import '../services/tool_registry.dart';
import '../services/tool_executor.dart';
import '../services/assistant_security_guard.dart';

/// Provider for the ActionRegistry singleton (legacy validation).
final actionRegistryProvider = Provider<ActionRegistry>((ref) {
  return ActionRegistry();
});

/// Provider for the IntentResolver.
final intentResolverProvider = Provider<IntentResolver>((ref) {
  throw UnimplementedError('Override in main providers.dart');
});

/// Provider for the StructuredRetriever.
final structuredRetrieverProvider = Provider<StructuredRetriever>((ref) {
  throw UnimplementedError('Override in main providers.dart');
});

/// Provider for the GalleryAssistant.
final galleryAssistantProvider = Provider<GalleryAssistant>((ref) {
  throw UnimplementedError('Override in main providers.dart');
});

/// Provider for the ActionExecutor (legacy).
final actionExecutorProvider = Provider<ActionExecutor>((ref) {
  throw UnimplementedError('Override in main providers.dart');
});

/// Provider for the ToolRegistry.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  throw UnimplementedError('Override in main providers.dart');
});

/// Provider for the ToolExecutor.
final toolExecutorProvider = Provider<ToolExecutor>((ref) {
  final registry = ref.watch(toolRegistryProvider);
  return ToolExecutor(registry: registry);
});

/// Provider for the AssistantSecurityGuard.
final securityGuardProvider = Provider<AssistantSecurityGuard>((ref) {
  return AssistantSecurityGuard();
});
