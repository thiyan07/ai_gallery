import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: query_knowledge_graph — Query the knowledge graph for connections.
///
/// READ-only. No confirmation required.
class QueryKnowledgeGraphTool extends AssistantTool {
  QueryKnowledgeGraphTool({required this.onQuery});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) onQuery;

  @override
  String get name => 'query_knowledge_graph';

  @override
  String get description => 'Query knowledge graph for people, places, and connections';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final queryType = parameters['queryType'] as String?;
    if (queryType == null || queryType.isEmpty) {
      return 'queryType is required (personCoOccurrences, personEvents, personPlaces, eventPeople, graphStats)';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final result = await onQuery(parameters);
    final queryType = parameters['queryType'] as String? ?? 'unknown';

    final text = result['text'] as String? ?? 'Query completed.';
    final photoIds = (result['photoIds'] as List?)?.cast<String>() ?? [];

    return ActionResult.informational(
      text,
      data: {...result, 'queryType': queryType},
      photoIds: photoIds,
    );
  }
}
