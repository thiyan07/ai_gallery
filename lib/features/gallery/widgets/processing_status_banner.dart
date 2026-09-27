import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/jobs/background_job_worker.dart';

/// Shows background AI processing status without being intrusive.
///
/// Displays as a compact banner when processing is active.
/// Shows progress and cancel option.
class ProcessingStatusBanner extends ConsumerWidget {
  const ProcessingStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(backgroundJobQueueProvider);

    return queueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (queue) {
        return StreamBuilder<WorkerStatus>(
          stream: queue.watchWorkerStatus(),
          builder: (context, snapshot) {
            final status = snapshot.data;
            if (status == null || (!status.isRunning && !status.isProcessing)) {
              return const SizedBox.shrink();
            }

            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 4,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Analyzing media...',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${status.jobsProcessed} processed'
                              '${status.jobsFailed > 0 ? ' · ${status.jobsFailed} failed' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => queue.cancelAll(),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
