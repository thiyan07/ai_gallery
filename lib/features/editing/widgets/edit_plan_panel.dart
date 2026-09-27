import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../domain/models/edit/edit_operation.dart';
import '../providers/edit_session_provider.dart';
import '../services/edit_plan.dart';
import '../services/edit_plan_service.dart';

/// Panel that shows an AI-generated edit plan with accept/reject per step.
///
/// Takes a prompt, generates a plan via EditPlanService, displays each
/// step with its description, rationale, confidence, and lets the user
/// accept individual steps or the entire plan.
class EditPlanPanel extends ConsumerStatefulWidget {
  final String photoId;

  const EditPlanPanel({super.key, required this.photoId});

  @override
  ConsumerState<EditPlanPanel> createState() => _EditPlanPanelState();
}

class _EditPlanPanelState extends ConsumerState<EditPlanPanel> {
  final _promptController = TextEditingController();
  EditPlan? _plan;
  final Set<String> _acceptedSteps = {};
  bool _allAccepted = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _generatePlan() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final logger = ref.read(appLoggerProvider);
    final service = EditPlanService(logger: logger);
    final plan = service.analyzePrompt(prompt, photoId: widget.photoId);
    setState(() {
      _plan = plan;
      _acceptedSteps.clear();
      _allAccepted = false;
    });
  }

  void _applyPlan() {
    if (_plan == null) return;
    final controller =
        ref.read(editSessionProvider(widget.photoId));

    final ops = _plan!.steps
        .where((s) => _acceptedSteps.contains(s.id))
        .map((s) => s.operation)
        .toList();

    if (ops.isEmpty) return;
    controller.applyOperations(ops);
  }

  void _toggleAll() {
    if (_plan == null) return;
    setState(() {
      if (_allAccepted) {
        _acceptedSteps.clear();
        _allAccepted = false;
      } else {
        _acceptedSteps.addAll(_plan!.steps.map((s) => s.id));
        _allAccepted = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: 280,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _promptController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. "make it warmer and more vibrant"',
                hintStyle: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.send,
                    color: Colors.blue,
                    size: 18,
                  ),
                  onPressed: _generatePlan,
                ),
              ),
              onSubmitted: (_) => _generatePlan(),
            ),
          ),
          if (_plan == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Describe what you want to change,\n'
                  'and AI will suggest edits.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (_plan!.steps.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _plan!.summary,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          _plan!.summary,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _toggleAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _allAccepted
                                  ? Colors.blue.withAlpha(40)
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _allAccepted
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _acceptedSteps.isNotEmpty
                              ? _applyPlan
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _acceptedSteps.isNotEmpty
                                  ? Colors.blue
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Apply (${_acceptedSteps.length})',
                              style: TextStyle(
                                color: _acceptedSteps.isNotEmpty
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      itemCount: _plan!.steps.length,
                      itemBuilder: (context, index) {
                        final step = _plan!.steps[index];
                        final isAccepted =
                            _acceptedSteps.contains(step.id);
                        return _EditPlanStepTile(
                          step: step,
                          isAccepted: isAccepted,
                          onTap: () {
                            setState(() {
                              if (isAccepted) {
                                _acceptedSteps.remove(step.id);
                              } else {
                                _acceptedSteps.add(step.id);
                              }
                              _allAccepted = _acceptedSteps.length ==
                                  _plan!.steps.length;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EditPlanStepTile extends StatelessWidget {
  final EditPlanStep step;
  final bool isAccepted;
  final VoidCallback onTap;

  const _EditPlanStepTile({
    required this.step,
    required this.isAccepted,
    required this.onTap,
  });

  Color get _confidenceColor {
    if (step.confidence >= 0.85) return Colors.green;
    if (step.confidence >= 0.7) return Colors.orange;
    return Colors.red.shade300;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isAccepted
              ? Colors.blue.withAlpha(30)
              : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isAccepted
                ? Colors.blue.withAlpha(100)
                : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: isAccepted ? Colors.blue : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isAccepted ? Colors.blue : Colors.white38,
                ),
              ),
              child: isAccepted
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.description,
                    style: TextStyle(
                      color: isAccepted
                          ? Colors.white
                          : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.rationale,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: _confidenceColor.withAlpha(40),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${(step.confidence * 100).round()}%',
                style: TextStyle(
                  color: _confidenceColor,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
