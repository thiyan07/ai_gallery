import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_operation.dart';
import 'edit_plan.dart';

const _uuid = Uuid();

/// Maps natural language editing prompts to ordered edit plans.
///
/// Uses rule-based keyword matching — no external model required.
/// Each rule maps a set of keywords/phrases to a sequence of edit operations.
class EditPlanService {
  EditPlanService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  /// Analyze a user prompt and generate an EditPlan.
  EditPlan analyzePrompt(String prompt, {String? photoId}) {
    final normalized = prompt.toLowerCase().trim();
    final steps = <EditPlanStep>[];

    // --- Lighting adjustments ---
    if (_matchesAny(normalized, [
      'brighten', 'bright', 'lighter', 'more light',
    ])) {
      steps.add(_makeStep(
        description: 'Increase brightness',
        operation: EditOperation.adjustment(exposure: 0.25),
        rationale: 'User requested brighter image',
        confidence: 0.9,
      ));
    }

    if (_matchesAny(normalized, [
      'darken', 'darker', 'more dark', 'reduce light',
    ])) {
      steps.add(_makeStep(
        description: 'Decrease brightness',
        operation: EditOperation.adjustment(exposure: -0.25),
        rationale: 'User requested darker image',
        confidence: 0.9,
      ));
    }

    if (_matchesAny(normalized, [
      'more contrast', 'increase contrast', 'punchy', 'crisp',
    ])) {
      steps.add(_makeStep(
        description: 'Increase contrast',
        operation: EditOperation.adjustment(contrast: 0.3),
        rationale: 'User requested higher contrast',
        confidence: 0.85,
      ));
    }

    if (_matchesAny(normalized, [
      'less contrast', 'reduce contrast', 'flat',
    ])) {
      steps.add(_makeStep(
        description: 'Decrease contrast',
        operation: EditOperation.adjustment(contrast: -0.2),
        rationale: 'User requested lower contrast',
        confidence: 0.8,
      ));
    }

    // --- Color adjustments ---
    if (_matchesAny(normalized, [
      'warmer', 'warm', 'golden', 'sunset',
    ])) {
      steps.add(_makeStep(
        description: 'Warm up color temperature',
        operation: EditOperation.adjustment(temperature: 0.3),
        rationale: 'User requested warmer tones',
        confidence: 0.85,
      ));
    }

    if (_matchesAny(normalized, [
      'cooler', 'cool', 'cold', 'blueish',
    ])) {
      steps.add(_makeStep(
        description: 'Cool down color temperature',
        operation: EditOperation.adjustment(temperature: -0.3),
        rationale: 'User requested cooler tones',
        confidence: 0.85,
      ));
    }

    if (_matchesAny(normalized, [
      'more saturation', 'vibrant', 'vivid',
      'colorful', 'saturate',
    ])) {
      steps.add(_makeStep(
        description: 'Increase saturation',
        operation: EditOperation.adjustment(saturation: 0.35),
        rationale: 'User requested more vibrant colors',
        confidence: 0.9,
      ));
    }

    if (_matchesAny(normalized, [
      'desaturate', 'less saturation', 'muted',
      'b&w', 'black and white', 'monochrome', 'grayscale',
    ])) {
      steps.add(_makeStep(
        description: 'Desaturate to grayscale',
        operation: EditOperation.adjustment(saturation: -1.0),
        rationale: 'User requested desaturated/grayscale look',
        confidence: 0.9,
      ));
    }

    // --- Detail ---
    if (_matchesAny(normalized, [
      'sharper', 'sharpen', 'more detail',
    ])) {
      steps.add(_makeStep(
        description: 'Increase sharpness',
        operation: EditOperation.adjustment(sharpness: 0.4),
        rationale: 'User requested sharper image',
        confidence: 0.85,
      ));
    }

    // --- Shadow/Highlight ---
    if (_matchesAny(normalized, [
      'lift shadow', 'brighten shadow', 'open shadow',
    ])) {
      steps.add(_makeStep(
        description: 'Lift shadows',
        operation: EditOperation.adjustment(shadows: 0.3),
        rationale: 'User requested to brighten shadow areas',
        confidence: 0.85,
      ));
    }

    if (_matchesAny(normalized, [
      'recover highlight', 'save highlight',
    ])) {
      steps.add(_makeStep(
        description: 'Recover highlights',
        operation: EditOperation.adjustment(highlights: -0.3),
        rationale: 'User requested to recover highlight detail',
        confidence: 0.85,
      ));
    }

    // --- Composite presets ---
    if (_matchesAny(normalized, [
      'hdr', 'high dynamic range', 'dramatic',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Increase contrast for HDR effect',
          operation: EditOperation.adjustment(contrast: 0.35),
          rationale: 'HDR requires strong contrast base',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Lift shadows for dynamic range',
          operation: EditOperation.adjustment(shadows: 0.3),
          rationale: 'Recover shadow detail for HDR',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Recover highlights for dynamic range',
          operation: EditOperation.adjustment(highlights: -0.3),
          rationale: 'Recover highlight detail for HDR',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Boost saturation for HDR look',
          operation: EditOperation.adjustment(saturation: 0.2),
          rationale: 'Vibrant color for HDR aesthetic',
          confidence: 0.75,
        ),
      ]);
    }

    if (_matchesAny(normalized, [
      'cinematic', 'film look', 'movie',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Slightly increase contrast',
          operation: EditOperation.adjustment(contrast: 0.2),
          rationale: 'Film look starts with contrast',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Warm the highlights',
          operation: EditOperation.adjustment(temperature: 0.15),
          rationale: 'Warm highlights mimic film stock',
          confidence: 0.75,
        ),
        _makeStep(
          description: 'Slightly desaturate for film tone',
          operation: EditOperation.adjustment(saturation: -0.15),
          rationale: 'Muted saturation for cinematic feel',
          confidence: 0.7,
        ),
      ]);
    }

    if (_matchesAny(normalized, [
      'portrait', 'skin', 'beauty', 'flattering',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Lift shadows for flattering light',
          operation: EditOperation.adjustment(shadows: 0.15),
          rationale: 'Soft shadow lift flatters skin',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Reduce contrast slightly',
          operation: EditOperation.adjustment(contrast: -0.1),
          rationale: 'Lower contrast softens skin',
          confidence: 0.75,
        ),
        _makeStep(
          description: 'Warm color temperature',
          operation: EditOperation.adjustment(temperature: 0.1),
          rationale: 'Warm tones flatter skin',
          confidence: 0.75,
        ),
      ]);
    }

    if (_matchesAny(normalized, [
      'landscape', 'nature', 'scenic',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Increase saturation for vivid landscape',
          operation: EditOperation.adjustment(saturation: 0.25),
          rationale: 'Landscapes benefit from vivid color',
          confidence: 0.85,
        ),
        _makeStep(
          description: 'Increase sharpness for detail',
          operation: EditOperation.adjustment(sharpness: 0.3),
          rationale: 'Landscape detail benefits from sharpening',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Boost contrast',
          operation: EditOperation.adjustment(contrast: 0.15),
          rationale: 'Contrast adds depth to landscapes',
          confidence: 0.8,
        ),
      ]);
    }

    if (_matchesAny(normalized, [
      'vintage', 'retro', 'faded',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Slightly desaturate',
          operation: EditOperation.adjustment(saturation: -0.2),
          rationale: 'Vintage look uses muted colors',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Lift blacks for faded look',
          operation: EditOperation.adjustment(blacks: 0.2),
          rationale: 'Faded blacks give vintage feel',
          confidence: 0.8,
        ),
        _makeStep(
          description: 'Add warmth',
          operation: EditOperation.adjustment(temperature: 0.2),
          rationale: 'Warm tones enhance vintage aesthetic',
          confidence: 0.75,
        ),
      ]);
    }

    if (_matchesAny(normalized, [
      'noir', 'dark moody', 'moody',
    ])) {
      steps.addAll([
        _makeStep(
          description: 'Convert to grayscale',
          operation: EditOperation.adjustment(saturation: -1.0),
          rationale: 'Noir requires grayscale base',
          confidence: 0.9,
        ),
        _makeStep(
          description: 'Boost contrast',
          operation: EditOperation.adjustment(contrast: 0.4),
          rationale: 'High contrast for dramatic noir',
          confidence: 0.85,
        ),
        _makeStep(
          description: 'Darken exposure',
          operation: EditOperation.adjustment(exposure: -0.15),
          rationale: 'Dark tones for moody noir',
          confidence: 0.8,
        ),
      ]);
    }

    // Build the plan
    final planId = _uuid.v4();
    final summary = steps.isEmpty
        ? 'No matching edit operations found for this prompt'
        : '${steps.length} adjustment${steps.length > 1 ? 's' : ''} suggested';

    final plan = EditPlan(
      planId: planId,
      prompt: prompt,
      summary: summary,
      steps: steps,
      createdAt: DateTime.now(),
      overallConfidence: steps.isEmpty
          ? 0.0
          : steps.map((s) => s.confidence).reduce((a, b) => a + b) /
              steps.length,
    );

    _logger.info(
      'Generated edit plan "$planId": ${steps.length} steps',
    );
    return plan;
  }

  bool _matchesAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  EditPlanStep _makeStep({
    required String description,
    required EditOperation operation,
    required String rationale,
    required double confidence,
  }) =>
      EditPlanStep(
        id: _uuid.v4(),
        description: description,
        operation: operation,
        rationale: rationale,
        confidence: confidence,
      );
}
