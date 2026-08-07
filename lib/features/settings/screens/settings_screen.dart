import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/core/theme/app_theme.dart';
import 'package:ai_gallery/core/theme/theme_providers.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../indexing/screens/indexing_screen.dart';
import '../screens/api_keys_screen.dart';
import '../screens/local_models_screen.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accentColor = ref.watch(accentColorProvider);
    final telemetryEnabled = ref.watch(telemetryEnabledProvider);
    final cloudBackupEnabled = ref.watch(cloudBackupEnabledProvider);
    final syncWifiOnly = ref.watch(syncWifiOnlyProvider);
    final syncFrequency = ref.watch(syncFrequencyProvider);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // THEME SECTION
          _buildSectionHeader(theme, 'Appearance'),

          // Theme Mode Dropdown
          ListTile(
            title: const Text('Theme Mode'),
            subtitle: Text(_getThemeModeName(themeMode)),
            leading: const Icon(Icons.palette_outlined),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(themeModeProvider.notifier).setThemeMode(mode);
                }
              },
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System (Auto)'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Light Mode'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark Mode'),
                ),
              ],
            ),
          ),

          // Custom Accent Color Picker
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Accent Color'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppTheme.accentColors.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final color = AppTheme.accentColors[index];
                      final isSelected =
                          accentColor.toARGB32() == color.toARGB32();

                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(accentColorProvider.notifier)
                              .setAccentColor(color);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Theme Live Preview Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.15,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Live Theme Preview',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 1,
                          color: theme.colorScheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Example Card',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'This card reflects your settings.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: () {},
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(
                                      double.infinity,
                                      32,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text(
                                    'Primary',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          elevation: 1,
                          color: theme.colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Secondary Panel',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Accent palette styling.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme
                                        .onSecondaryContainer
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(
                                      double.infinity,
                                      32,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text(
                                    'Secondary',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),

          // CLOUD AND SYNC SECTION
          _buildSectionHeader(theme, 'Cloud & Synchronization'),

          // Cloud Backup Mode Toggle
          SwitchListTile(
            title: const Text('Cloud Backup Enable'),
            subtitle: const Text(
              'Encrypt and upload metadata to cloud servers.',
            ),
            secondary: const Icon(Icons.cloud_upload_outlined),
            value: cloudBackupEnabled,
            onChanged: (val) {
              ref.read(cloudBackupEnabledProvider.notifier).setEnabled(val);
            },
          ),

          // If Cloud Backup is Enabled, show sync options
          if (cloudBackupEnabled) ...[
            SwitchListTile(
              title: const Text('Sync on Wi-Fi Only'),
              subtitle: const Text(
                'Restricts syncing to Wi-Fi connections to save mobile data.',
              ),
              secondary: const Icon(Icons.wifi_outlined),
              value: syncWifiOnly,
              onChanged: (val) {
                ref.read(syncWifiOnlyProvider.notifier).toggle(val);
              },
            ),
            ListTile(
              title: const Text('Sync Frequency'),
              subtitle: Text('Frequency: $syncFrequency'),
              leading: const Icon(Icons.sync_outlined),
              trailing: DropdownButton<String>(
                value: syncFrequency,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(syncFrequencyProvider.notifier).setFrequency(val);
                  }
                },
                items: const [
                  DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                ],
              ),
            ),
            // Sync status Dashboard
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Last Synced:'),
                          Text(
                            'Today, 12:45 PM',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pending Items:'),
                          Text(
                            '0 files',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cloud Storage Used:'),
                          Text(
                            '1.2 GB / 100 GB',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // AI Indexing Section
          _buildSectionHeader(theme, 'AI Indexing'),
          ListTile(
            title: const Text('Index Photos'),
            subtitle: const Text(
              'Scan photos, extract metadata, and prepare for AI search.',
            ),
            leading: const Icon(Icons.auto_awesome_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const IndexingScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          // API Keys Settings Trigger
          ListTile(
            title: const Text('AI Provider Credentials'),
            subtitle: const Text(
              'Configure API keys for Google Vision, OpenAI, Anthropic.',
            ),
            leading: const Icon(Icons.vpn_key_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ApiKeysScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          // Local Models Settings
          ListTile(
            title: const Text('Local Models'),
            subtitle: const Text(
              'Download and manage on-device embedding models for semantic search.',
            ),
            leading: const Icon(Icons.model_training_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LocalModelsScreen()),
              );
            },
          ),
          const Divider(height: 32),

          // SECURITY & TELEMETRY SECTION
          _buildSectionHeader(theme, 'Security & Telemetry'),

          // Telemetry Toggle
          SwitchListTile(
            title: const Text('Anonymous Telemetry'),
            subtitle: const Text(
              'Opt-in to send crash reports and usage statistics. No media content is gathered.',
            ),
            secondary: const Icon(Icons.analytics_outlined),
            value: telemetryEnabled,
            onChanged: (val) {
              ref.read(telemetryEnabledProvider.notifier).toggle(val);
            },
          ),

          // Storage Path location
          ListTile(
            title: const Text('Storage Location'),
            subtitle: const Text('/home/thiyan/projects/ai_gallery/data'),
            leading: const Icon(Icons.folder_open_outlined),
          ),

          const Divider(height: 32),

          // RESET / DEBUGGING SECTION
          _buildSectionHeader(theme, 'Advanced & Maintenance'),

          ListTile(
            title: const Text(
              'Reset Onboarding Wizard',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text(
              'Restarts the first-time welcome tutorial on next launch.',
            ),
            leading: const Icon(Icons.restart_alt, color: Colors.red),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Onboarding?'),
                  content: const Text(
                    'Are you sure you want to reset the onboarding wizard? The app will close and restart in configuration mode.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(onboardingProvider.notifier).resetOnboarding();
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.system:
        return 'System (Auto)';
    }
  }
}
