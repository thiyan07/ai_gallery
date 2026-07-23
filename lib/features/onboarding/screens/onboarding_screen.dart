import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import '../providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late ConfettiController _confettiController;
  bool _hasPlayedConfetti = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingProvider);
    final theme = Theme.of(context);

    // Play confetti only once when reaching step 5
    if (onboardingState.currentStep == 5 && !_hasPlayedConfetti) {
      _hasPlayedConfetti = true;
      _confettiController.play();
    }

    // Reset confetti flag if user goes back from step 5
    if (onboardingState.currentStep != 5) {
      _hasPlayedConfetti = false;
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Main page layout with transitions
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0.0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildStepContent(
                onboardingState.currentStep,
                onboardingState,
                theme,
              ),
            ),

            // Top Header: Skip button & Step indicator
            if (onboardingState.currentStep < 5)
              Positioned(
                top: 16,
                left: 24,
                right: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${onboardingState.currentStep} of 4',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(onboardingProvider.notifier)
                            .completeOnboarding();
                      },
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),

            // Confetti implementation
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  Colors.green,
                  Colors.blue,
                  Colors.pink,
                  Colors.orange,
                  Colors.purple,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(int step, OnboardingState state, ThemeData theme) {
    switch (step) {
      case 1:
        return _buildWelcomeStep(theme);
      case 2:
        return _buildPermissionsStep(state, theme);
      case 3:
        return _buildStorageStep(state, theme);
      case 4:
        return _buildApiKeysStep(state, theme);
      case 5:
        return _buildDoneStep(theme);
      default:
        return _buildWelcomeStep(theme);
    }
  }

  // STEP 1: Welcome Page
  Widget _buildWelcomeStep(ThemeData theme) {
    return Padding(
      key: const ValueKey(1),
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo or Icon with a beautiful circular background gradient
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'AI Gallery',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Smart AI photo gallery for your memories.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Features List
          _buildFeatureRow(
            theme,
            Icons.search,
            'Semantic Search',
            'Find photos by describing them in natural language.',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            theme,
            Icons.security,
            'Privacy First',
            'Local-only indexing keeps your personal data private.',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            theme,
            Icons.auto_awesome,
            'AI Organization',
            'Smart categorization of people, scenes, objects, and moods.',
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () {
              ref.read(onboardingProvider.notifier).setStep(2);
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Get Started'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // STEP 2: Permissions Page
  Widget _buildPermissionsStep(OnboardingState state, ThemeData theme) {
    final notifier = ref.read(onboardingProvider.notifier);
    return Padding(
      key: const ValueKey(2),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 80),
          Text(
            'App Permissions',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please grant permissions so we can load and analyze your media library.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // Camera
          _buildPermissionTile(
            theme: theme,
            title: 'Camera',
            subtitle:
                'Required to take new photos and scan documents directly in the app.',
            icon: Icons.camera_alt,
            isGranted: state.cameraPermissionGranted,
            onChanged: (val) => notifier.togglePermission('camera'),
          ),
          const SizedBox(height: 16),
          // Photos / Storage
          _buildPermissionTile(
            theme: theme,
            title: 'Photos & Files',
            subtitle:
                'Allows the app to display your media files and load metadata.',
            icon: Icons.photo_size_select_actual,
            isGranted: state.photosPermissionGranted,
            onChanged: (val) => notifier.togglePermission('photos'),
          ),
          const SizedBox(height: 16),
          // Microphone
          _buildPermissionTile(
            theme: theme,
            title: 'Microphone',
            subtitle:
                'Used for conversational voice search and dictation features.',
            icon: Icons.mic,
            isGranted: state.microphonePermissionGranted,
            onChanged: (val) => notifier.togglePermission('microphone'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              notifier.setStep(3);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // STEP 3: Storage Setup Page
  Widget _buildStorageStep(OnboardingState state, ThemeData theme) {
    final notifier = ref.read(onboardingProvider.notifier);
    return Padding(
      key: const ValueKey(3),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 80),
          Text(
            'Storage & Security',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose where your metadata and database will reside.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // Choice Card 1: Local Only
          InkWell(
            onTap: () => notifier.setStorageMode('local'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: state.storageMode == 'local'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: state.storageMode == 'local' ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                color: state.storageMode == 'local'
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                    : null,
              ),
              child: Row(
                children: [
                  Radio<String>(
                    value: 'local',
                    groupValue: state.storageMode,
                    onChanged: (val) => notifier.setStorageMode(val!),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Only Mode',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'All data remains on your device. Zero cloud uploads. Fully offline-first.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Choice Card 2: Cloud Backup
          InkWell(
            onTap: () => notifier.setStorageMode('cloud'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: state.storageMode == 'cloud'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: state.storageMode == 'cloud' ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                color: state.storageMode == 'cloud'
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                    : null,
              ),
              child: Row(
                children: [
                  Radio<String>(
                    value: 'cloud',
                    groupValue: state.storageMode,
                    onChanged: (val) => notifier.setStorageMode(val!),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hybrid Cloud Backup',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sync encrypted metadata to the cloud for multi-device access. Optional image backup.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Storage Details info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Free Space:'),
                    Text(
                      '128.4 GB Available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Default Library Location:'),
                    Text(
                      state.customStoragePath ?? 'Device Sandbox',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              notifier.setStep(4);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // STEP 4: API Keys (Prompt 1.2 / 1.3)
  Widget _buildApiKeysStep(OnboardingState state, ThemeData theme) {
    final notifier = ref.read(onboardingProvider.notifier);
    return Padding(
      key: const ValueKey(4),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 80),
          Text(
            'AI Providers Config',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'To enable cloud features, you can configure AI providers. You can also skip this and set them up later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // Explanation Panel
          Card(
            elevation: 0,
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Bring Your Own Keys',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use OpenAI, Google Vision, or Anthropic services for cloud analysis. All keys are encrypted and stored locally in the secure keystore.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () async {
              // Mark complete and we will guide user to API Key settings later
              await notifier.completeOnboarding();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Configure Later (Skip)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              // Complete onboarding and show done screen, which will lead to the app
              await notifier.completeOnboarding();
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Agree & Continue'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // STEP 5: Done Page
  Widget _buildDoneStep(ThemeData theme) {
    return Padding(
      key: const ValueKey(5),
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 100,
            color: Colors.green,
          ),
          const SizedBox(height: 32),
          Text(
            'Gallery is ready!',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your smart offline photo gallery is set up and ready to organize your memories.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: () {
              // Simply notify the app flow to load the home gallery
              // We've already completed onboarding, state will trigger rebuild
              // of main wrapper.
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Start Importing Photos'),
          ),
        ],
      ),
    );
  }

  // UI HELPER: Feature Row
  Widget _buildFeatureRow(
    ThemeData theme,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // UI HELPER: Permission Tile
  Widget _buildPermissionTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 28,
            color: isGranted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: isGranted, onChanged: onChanged),
        ],
      ),
    );
  }
}