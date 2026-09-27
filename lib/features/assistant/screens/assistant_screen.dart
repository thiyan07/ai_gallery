import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assistant_response.dart';
import '../models/gallery_action.dart';
import '../models/gallery_intent.dart';
import '../models/action_state.dart';
import '../services/tool_executor.dart';
import '../services/tool_interface.dart';
import '../services/chat_history_service.dart';
import '../services/assistant_security_guard.dart';
import '../widgets/assistant_photo_grid.dart';
import '../widgets/action_preview_card.dart';
import '../providers/assistant_providers.dart';

/// Main gallery assistant screen.
///
/// Provides a conversational interface for querying, exploring,
/// and acting on gallery data.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  ChatHistoryService? _chatHistory;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  void _loadChatHistory() {
    // Load chat history from persistence (async, non-blocking)
    Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      _chatHistory = ChatHistoryService(prefs);
      final saved = _chatHistory!.loadMessages();
      if (saved.isNotEmpty && mounted) {
        setState(() {
          _messages.addAll(saved.map((m) => _ChatMessage._(
                isUser: m.isUser,
                text: m.text,
                photoIds: m.photoIds,
                intent: m.intent,
              )));
        });
        _scrollToBottom();
      }
    });
  }

  void _persistMessages() {
    _chatHistory?.saveMessages(
      _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => ChatMessage(
                isUser: m.isUser,
                text: m.text,
                photoIds: m.photoIds,
                intent: m.intent,
              ))
          .toList(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendQuery() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    // Security: input validation
    final securityGuard = ref.read(securityGuardProvider);
    final inputError = securityGuard.validateInput(text);
    if (inputError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(inputError)),
        );
      }
      return;
    }

    // Security: rate limiting
    final rateError = securityGuard.checkRateLimit();
    if (rateError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(rateError)),
        );
      }
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(text));
      _isLoading = true;
    });
    _persistMessages();
    _controller.clear();
    _scrollToBottom();

    try {
      final assistant = ref.read(galleryAssistantProvider);
      final response = await assistant.processQuery(text);

      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage.assistant(response));
          _isLoading = false;
        });
        _persistMessages();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage.error('$e'));
          _isLoading = false;
        });
        _persistMessages();
        _scrollToBottom();
      }
    }
  }

  Future<void> _executeAction(GalleryAction action) async {
    final toolExecutor = ref.read(toolExecutorProvider);
    final securityGuard = ref.read(securityGuardProvider);
    final tracked = toolExecutor.trackFromGalleryAction(action);

    // Security: batch size validation
    final photoIds = action.parameters['photoIds'] as List<String>?;
    if (photoIds != null) {
      final sizeError = securityGuard.validateBatchSize(
        itemCount: photoIds.length,
        isDestructive: tracked.isDestructive,
      );
      if (sizeError != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sizeError)),
          );
        }
        toolExecutor.cancel(tracked);
        return;
      }
    }

    // Show confirmation for actions that require it
    if (tracked.canCancel) {
      // Double confirmation for large destructive batches
      if (photoIds != null &&
          securityGuard.requiresDoubleConfirmation(
            itemCount: photoIds.length,
            isDestructive: tracked.isDestructive,
          )) {
        final doubleConfirmed = await _showDoubleConfirmationDialog(
          photoIds.length,
          securityGuard,
        );
        if (!doubleConfirmed) {
          toolExecutor.cancel(tracked);
          return;
        }
      } else {
        final confirmed = await _showConfirmationDialog(tracked);
        if (!confirmed) {
          toolExecutor.cancel(tracked);
          return;
        }
      }
    }

    // Execute directly — tools handle their own logic internally
    final result = await toolExecutor.confirmAndExecute(tracked);

    if (mounted) {
      if (result.type == ActionResultType.navigation) {
        _handleNavigation(action);
      } else {
        _showResult(result, tracked);
      }
    }
  }

  void _showResult(ActionResult result, TrackedAction tracked) {
    if (result.success) {
      final snackBar = SnackBar(
        content: Text(result.message),
        action: tracked.canUndo
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => _undoAction(tracked),
              )
            : null,
        duration: const Duration(seconds: 4),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _undoAction(TrackedAction tracked) async {
    final toolExecutor = ref.read(toolExecutorProvider);
    final success = await toolExecutor.undo(tracked);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Action undone.' : 'Could not undo action.'),
        ),
      );
    }
  }

  void _handleNavigation(GalleryAction action) {
    Navigator.of(context).pop({
      'action': action.type.name,
      'parameters': action.parameters,
    });
  }

  Future<bool> _showConfirmationDialog(TrackedAction tracked) async {
    final photoIds = tracked.parameters['photoIds'] as List<String>?;

    // Use rich preview card for actions with photos
    if (photoIds != null && photoIds.isNotEmpty) {
      return showDialog<bool>(
        context: context,
        builder: (ctx) => ActionPreviewCard(
          tracked: tracked,
          onConfirm: () => Navigator.of(ctx).pop(true),
          onCancel: () => Navigator.of(ctx).pop(false),
        ),
      ).then((v) => v ?? false);
    }

    // Plain dialog for other actions
    final isDestructive = tracked.isDestructive;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: isDestructive
            ? const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48)
            : const Icon(Icons.help_outline, size: 48),
        title: Text(isDestructive ? 'Confirm Deletion' : 'Confirm Action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _describeAction(tracked),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (isDestructive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be easily undone.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                : null,
            child: Text(isDestructive ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  /// Double confirmation for large destructive batches (10+ items).
  /// User must type a confirmation phrase to proceed.
  Future<bool> _showDoubleConfirmationDialog(
    int itemCount,
    AssistantSecurityGuard securityGuard,
  ) async {
    final controller = TextEditingController();
    final expectedPhrase = securityGuard.getConfirmationPhrase(itemCount);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
        title: const Text('Confirm Batch Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to permanently delete $itemCount photos.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('This action CANNOT be undone.'),
            const SizedBox(height: 12),
            Text(
              'Type "$expectedPhrase" to confirm:',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type confirmation phrase',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.of(ctx).pop(false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final valid = securityGuard.validateConfirmationPhrase(
                userInput: controller.text,
                itemCount: itemCount,
              );
              controller.dispose();
              Navigator.of(ctx).pop(valid);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  String _describeAction(TrackedAction tracked) {
    switch (tracked.toolName) {
      case 'delete_photos':
        final count = (tracked.parameters['photoIds'] as List?)?.length ?? 0;
        return 'Delete $count photo${count == 1 ? '' : 's'} permanently?';
      case 'add_favorites':
        final count = (tracked.parameters['photoIds'] as List?)?.length ?? 0;
        return 'Add $count photo${count == 1 ? '' : 's'} to favorites?';
      case 'remove_favorites':
        final count = (tracked.parameters['photoIds'] as List?)?.length ?? 0;
        return 'Remove $count photo${count == 1 ? '' : 's'} from favorites?';
      case 'create_album':
        final title = tracked.parameters['title'] as String? ?? 'Untitled';
        return 'Create album "$title"?';
      case 'create_memory':
        final title = tracked.parameters['memoryTitle'] as String? ?? 'My Memory';
        return 'Create memory "$title"?';
      default:
        return tracked.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery Assistant'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear Chat'),
                    content: const Text('Delete all chat history?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  setState(() => _messages.clear());
                  _chatHistory?.clearHistory();
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : _buildMessageList(theme),
          ),
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              'Gallery Assistant',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything about your photos.\n'
              'I can search, count, find duplicates, and more.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildQuickActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    final actions = [
      ('Show recent photos', Icons.history),
      ('How many photos do I have?', Icons.query_stats),
      ('Find duplicates', Icons.content_copy),
      ('Show blurry photos', Icons.blur_on),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: actions.map((a) {
        return ActionChip(
          avatar: Icon(a.$2, size: 18),
          label: Text(a.$1),
          onPressed: () {
            _controller.text = a.$1;
            _sendQuery();
          },
        );
      }).toList(),
    );
  }

  Widget _buildMessageList(ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const _TypingIndicator();
        }
        return _buildMessage(_messages[index], theme);
      },
    );
  }

  Widget _buildMessage(_ChatMessage message, ThemeData theme) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Assistant',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (message.photoIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AssistantPhotoGrid(
                      photoIds: message.photoIds,
                      onTap: () => _handleNavigation(
                        GalleryAction(
                          type: GalleryActionType.showSearchResults,
                          parameters: {'photoIds': message.photoIds},
                          description: 'View all photos',
                        ),
                      ),
                    ),
                  ],
                  if (message.suggestedActions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SuggestedActions(
                      actions: message.suggestedActions,
                      onExecute: _executeAction,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Ask about your photos...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendQuery(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isLoading ? null : _sendQuery,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to use'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Try asking:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• "How many photos do I have?"'),
              Text('• "Show me photos from 2024"'),
              Text('• "Find photos with Alex"'),
              Text('• "Show blurry photos"'),
              Text('• "Find duplicates"'),
              Text('• "Create album from beach photos"'),
              Text('• "What\'s in my gallery?"'),
              SizedBox(height: 12),
              Text('Follow-ups:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• "Only the ones with Alex"'),
              Text('• "Just the recent ones"'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Chat message model.
class _ChatMessage {
  final bool isUser;
  final String text;
  final List<String> photoIds;
  final List<GalleryAction> suggestedActions;
  final GalleryIntent? intent;

  const _ChatMessage._({
    required this.isUser,
    required this.text,
    this.photoIds = const [],
    this.suggestedActions = const [],
    this.intent,
  });

  factory _ChatMessage.user(String text) =>
      _ChatMessage._(isUser: true, text: text);

  factory _ChatMessage.assistant(AssistantResponse response) =>
      _ChatMessage._(
        isUser: false,
        text: response.text,
        photoIds: response.photoIds,
        suggestedActions: response.suggestedActions,
        intent: response.intent,
      );

  factory _ChatMessage.error(String message) =>
      _ChatMessage._(isUser: false, text: 'Error: $message');
}

/// Typing indicator widget.
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Thinking...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggested actions chips.
class _SuggestedActions extends StatelessWidget {
  final List<GalleryAction> actions;
  final Function(GalleryAction) onExecute;

  const _SuggestedActions({required this.actions, required this.onExecute});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: actions.map((action) {
        return ActionChip(
          label: Text(action.description),
          onPressed: () => onExecute(action),
        );
      }).toList(),
    );
  }
}
