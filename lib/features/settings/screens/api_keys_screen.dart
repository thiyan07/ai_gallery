import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart' as di_providers;
import '../providers/settings_providers.dart';
import '../services/api_connection_tester.dart';

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  // Key configuration status
  bool _isOpenAIConfigured = false;
  bool _isGoogleVisionConfigured = false;
  bool _isAnthropicConfigured = false;

  // Masked key display strings
  String _openAIMasked = 'Not configured';
  String _googleVisionMasked = 'Not configured';
  String _anthropicMasked = 'Not configured';

  // Loading states for connection testing
  bool _isTestingOpenAI = false;
  bool _isTestingVision = false;
  bool _isTestingAnthropic = false;

  @override
  void initState() {
    super.initState();
    _loadKeysStatus();
  }

  Future<void> _loadKeysStatus() async {
    final secureStorage = ref.read(di_providers.secureStorageServiceProvider);
    final openai = await secureStorage.getOpenAIKey();
    final vision = await secureStorage.getGoogleVisionKey();
    final anthropic = await secureStorage.getAnthropicKey();

    if (mounted) {
      setState(() {
        _isOpenAIConfigured = openai != null && openai.isNotEmpty;
        _openAIMasked = _isOpenAIConfigured
            ? _maskKey(openai!)
            : 'Not configured';

        _isGoogleVisionConfigured = vision != null && vision.isNotEmpty;
        _googleVisionMasked = _isGoogleVisionConfigured
            ? _maskKey(vision!)
            : 'Not configured';

        _isAnthropicConfigured = anthropic != null && anthropic.isNotEmpty;
        _anthropicMasked = _isAnthropicConfigured
            ? _maskKey(anthropic!)
            : 'Not configured';
      });
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8)
      return '••••${key.substring(key.length > 4 ? key.length - 4 : 0)}';
    return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
  }

  Future<void> _addOrEditKey(String provider, String currentMasked) async {
    final controller = TextEditingController();
    final isEditing = currentMasked != 'Not configured';

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${isEditing ? 'Edit' : 'Add'} $provider API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your secret $provider API key. It will be stored securely using device-level encryption.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '$provider API Key',
                  border: const OutlineInputBorder(),
                  hintText: 'sk-...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      // Validate simple formats (standard keys start with prefixes)
      if (provider == 'OpenAI' && !result.startsWith('sk-')) {
        _showErrorSnackBar('Invalid OpenAI key format (should start with sk-)');
        return;
      }

      final secureStorage = ref.read(di_providers.secureStorageServiceProvider);
      if (provider == 'OpenAI') {
        await secureStorage.setOpenAIKey(result);
      } else if (provider == 'Google Vision') {
        await secureStorage.setGoogleVisionKey(result);
      } else if (provider == 'Anthropic') {
        await secureStorage.setAnthropicKey(result);
      }

      await _loadKeysStatus();
      _showSuccessSnackBar('$provider API Key saved successfully.');
    }
  }

  Future<void> _confirmDeleteKey(String provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete $provider Key?'),
          content: Text(
            'Are you sure you want to remove the saved $provider API key? Cloud capabilities relying on this provider will be disabled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final secureStorage = ref.read(di_providers.secureStorageServiceProvider);
      if (provider == 'OpenAI') {
        await secureStorage.deleteOpenAIKey();
      } else if (provider == 'Google Vision') {
        await secureStorage.deleteGoogleVisionKey();
      } else if (provider == 'Anthropic') {
        await secureStorage.deleteAnthropicKey();
      }
      await _loadKeysStatus();
      _showSuccessSnackBar('$provider key deleted.');
    }
  }

  Future<void> _testConnection(String provider) async {
    setState(() {
      if (provider == 'OpenAI') _isTestingOpenAI = true;
      if (provider == 'Google Vision') _isTestingVision = true;
      if (provider == 'Anthropic') _isTestingAnthropic = true;
    });

    final secureStorage = ref.read(di_providers.secureStorageServiceProvider);
    final tester = ApiConnectionTester(secureStorage);

    ConnectionTestResult result;
    switch (provider) {
      case 'OpenAI':
        result = await tester.testOpenAI();
      case 'Google Vision':
        result = await tester.testGoogleVision();
      case 'Anthropic':
        result = await tester.testAnthropic();
      default:
        result = const ConnectionTestResult(
          success: false,
          message: 'Unknown provider.',
        );
    }

    if (mounted) {
      setState(() {
        if (provider == 'OpenAI') _isTestingOpenAI = false;
        if (provider == 'Google Vision') _isTestingVision = false;
        if (provider == 'Anthropic') _isTestingAnthropic = false;
      });

      _showConnectionResultDialog(provider, result.success, result.message);
    }
  }

  void _showConnectionResultDialog(String provider, bool success, [String? message]) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(success ? 'Connection Successful' : 'Connection Failed'),
            ],
          ),
          content: Text(
            message ??
                (success
                    ? 'Successfully established connection with $provider servers. Your API key is valid and working.'
                    : 'Unable to connect to $provider. Please check your network connection and ensure your API key is correct.'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = ref.watch(apiKeysModeProvider);
    final modeNotifier = ref.read(apiKeysModeProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('API Providers Config')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Operation Modes Segmented Selector
          Text(
            'Operational Mode',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'local',
                icon: Icon(Icons.phone_android),
                label: Text('Local Only'),
              ),
              ButtonSegment<String>(
                value: 'hybrid',
                icon: Icon(Icons.sync),
                label: Text('Hybrid'),
              ),
              ButtonSegment<String>(
                value: 'byok',
                icon: Icon(Icons.vpn_key),
                label: Text('BYO Key'),
              ),
            ],
            selected: {activeMode},
            onSelectionChanged: (Set<String> newSelection) {
              modeNotifier.setMode(newSelection.first);
            },
          ),
          const SizedBox(height: 16),

          // Operational Mode Description Card
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getModeTitle(activeMode),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getModeDescription(activeMode),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // API Key Fields Section
          Text(
            'Provider API Keys',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // OpenAI Card
          _buildProviderKeyCard(
            theme: theme,
            name: 'OpenAI',
            maskedKey: _openAIMasked,
            isConfigured: _isOpenAIConfigured,
            isTesting: _isTestingOpenAI,
            helpText:
                'Used for advanced image description and smart natural language search reasoning. Get a key at platform.openai.com.',
          ),
          const SizedBox(height: 16),

          // Google Vision Card
          _buildProviderKeyCard(
            theme: theme,
            name: 'Google Vision',
            maskedKey: _googleVisionMasked,
            isConfigured: _isGoogleVisionConfigured,
            isTesting: _isTestingVision,
            helpText:
                'Powers high-accuracy Optical Character Recognition (OCR) and scene tagging in cloud modes. Get a key at console.cloud.google.com.',
          ),
          const SizedBox(height: 16),

          // Anthropic Card
          _buildProviderKeyCard(
            theme: theme,
            name: 'Anthropic',
            maskedKey: _anthropicMasked,
            isConfigured: _isAnthropicConfigured,
            isTesting: _isTestingAnthropic,
            helpText:
                'Provides alternative LLM intelligence for conversational search and tagging. Get a key at console.anthropic.com.',
          ),
        ],
      ),
    );
  }

  Widget _buildProviderKeyCard({
    required ThemeData theme,
    required String name,
    required String maskedKey,
    required bool isConfigured,
    required bool isTesting,
    required String helpText,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConfigured
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
          width: isConfigured ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row with Name, Config Status, Edit/Delete
            Row(
              children: [
                Icon(
                  Icons.key,
                  color: isConfigured
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                // Indicator Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isConfigured
                        ? Colors.green.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isConfigured ? 'Configured' : 'Missing',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isConfigured
                          ? Colors.green[800]
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Actions
                if (isConfigured) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _confirmDeleteKey(name),
                    tooltip: 'Remove Key',
                  ),
                ],
                IconButton(
                  icon: Icon(
                    isConfigured
                        ? Icons.edit_outlined
                        : Icons.add_circle_outline,
                  ),
                  onPressed: () => _addOrEditKey(name, maskedKey),
                  tooltip: isConfigured ? 'Edit Key' : 'Add Key',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Masked key display
            Text(
              'Key: $maskedKey',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: isConfigured
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Help description
            Text(
              helpText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Test Connection Button
            if (isConfigured) ...[
              OutlinedButton.icon(
                onPressed: isTesting ? null : () => _testConnection(name),
                icon: isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(isTesting ? 'Testing...' : 'Test Connection'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getModeTitle(String mode) {
    switch (mode) {
      case 'hybrid':
        return 'Hybrid Cloud Integration';
      case 'byok':
        return 'Bring Your Own API Key';
      case 'local':
      default:
        return 'Local Only Mode';
    }
  }

  String _getModeDescription(String mode) {
    switch (mode) {
      case 'hybrid':
        return 'Processes core metadata and standard images locally using on-device models. Utilizes Google/OpenAI Cloud APIs for advanced categorization and reasoning when connected.';
      case 'byok':
        return 'You provide and manage credentials for OpenAI, Google Vision, and Anthropic. All cloud AI features are billed directly to your account keys.';
      case 'local':
      default:
        return 'All processing occurs directly on this device. Privacy guaranteed. No network requests or external API calls are made.';
    }
  }
}
