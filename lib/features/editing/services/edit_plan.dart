import 'dart:convert';

import '../../../domain/models/edit/edit_operation.dart';

/// A single step in an AI-suggested edit plan.
class EditPlanStep {
  final String id;
  final String description;
  final EditOperation operation;
  final String rationale;
  final double confidence;

  const EditPlanStep({
    required this.id,
    required this.description,
    required this.operation,
    required this.rationale,
    this.confidence = 1.0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'description': description,
        'operation': operation.toMap(),
        'rationale': rationale,
        'confidence': confidence,
      };

  factory EditPlanStep.fromMap(Map<String, dynamic> map) => EditPlanStep(
        id: map['id'] as String,
        description: map['description'] as String,
        operation:
            EditOperation.fromMap(map['operation'] as Map<String, dynamic>),
        rationale: map['rationale'] as String,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      );

  String toJson() => jsonEncode(toMap());
  factory EditPlanStep.fromJson(String json) =>
      EditPlanStep.fromMap(jsonDecode(json) as Map<String, dynamic>);
}

/// A complete AI-suggested edit plan consisting of ordered steps.
class EditPlan {
  final String planId;
  final String prompt;
  final String summary;
  final List<EditPlanStep> steps;
  final DateTime createdAt;
  final double overallConfidence;

  const EditPlan({
    required this.planId,
    required this.prompt,
    required this.summary,
    required this.steps,
    required this.createdAt,
    this.overallConfidence = 1.0,
  });

  /// Convert all steps to EditOperations for application to a recipe.
  List<EditOperation> toOperations() =>
      steps.map((s) => s.operation).toList();

  Map<String, dynamic> toMap() => {
        'plan_id': planId,
        'prompt': prompt,
        'summary': summary,
        'steps': steps.map((s) => s.toMap()).toList(),
        'created_at': createdAt.toIso8601String(),
        'overall_confidence': overallConfidence,
      };

  factory EditPlan.fromMap(Map<String, dynamic> map) => EditPlan(
        planId: map['plan_id'] as String,
        prompt: map['prompt'] as String,
        summary: map['summary'] as String,
        steps: (map['steps'] as List)
            .map((e) => EditPlanStep.fromMap(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(map['created_at'] as String),
        overallConfidence:
            (map['overall_confidence'] as num?)?.toDouble() ?? 1.0,
      );

  String toJson() => jsonEncode(toMap());
  factory EditPlan.fromJson(String json) =>
      EditPlan.fromMap(jsonDecode(json) as Map<String, dynamic>);
}
